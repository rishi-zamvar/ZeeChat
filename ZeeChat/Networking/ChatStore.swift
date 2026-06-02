import Foundation
import SwiftUI

/// Per-contact chat state — owns the in-memory thread, drives sends, runs
/// the polling loop, surfaces new-inbound notifications, tracks unread
/// counts for the app badge, and persists every thread to disk so a
/// kill/relaunch is invisible.
///
/// Inbox is daemon-local so we poll Mac for the PM thread and PC for the
/// SWE thread, each with its own cursor + read-watermark.
///
/// Read receipts: the daemon stamps `read_at` on a message once the
/// receiving Claude has pulled it via `dispatchctl read <id>`. The UI
/// surfaces that as a "Seen ✓" tick on the user's outgoing bubbles.
///
/// "Typing" indicator: heuristic. When the user sends, we mark that
/// contact as "thinking" for up to 5 minutes; the flag clears on the
/// next inbound from that contact OR on timeout. No backend ping
/// required — the daemon's existing wake-touch is what kicks Claude.
@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var threads: [ContactRole: [DispatchMessage]] = [
        .pm: [], .swe: [],
    ]
    @Published private(set) var lastError: String? = nil
    @Published private(set) var isPolling: Bool = false
    /// Per-contact unread count = messages with created_at > readWatermark
    /// and from_role != ceo (i.e. inbound replies the user hasn't viewed).
    @Published private(set) var unread: [ContactRole: Int] = [.pm: 0, .swe: 0]
    /// True while we're waiting for that contact to reply to the user's
    /// most recent outbound. Drives the animated typing bubble.
    @Published private(set) var thinking: [ContactRole: Bool] = [.pm: false, .swe: false]

    private let client: DispatchClient
    private var pollTask: Task<Void, Never>? = nil
    private let settings: AppSettings
    /// Per-daemon cursors so each inbox poll only fetches deltas.
    private var cursors: [ContactRole: String?] = [:]
    /// Per-contact read watermark (last message id the user actually saw).
    /// Anything created_at > corresponding message's created_at is unread.
    private var readWatermarkId: [ContactRole: String] = [:]
    /// Timers that clear the "thinking" heuristic after 5 minutes.
    private var thinkingTimers: [ContactRole: Task<Void, Never>] = [:]
    /// Currently-visible thread (drives notification suppression so the
    /// foreground user doesn't get a banner for a chat they're staring at).
    @Published var visibleContact: ContactRole? = nil

    static let subjectPrefix = "ZeeChat:"

    init(settings: AppSettings) {
        self.settings = settings
        self.client = DispatchClient(settings: settings)
        for role in ContactRole.allCases {
            let stored = ThreadStore.shared.load(for: role)
            self.threads[role] = stored
            self.cursors[role] = ThreadStore.shared.loadCursor(for: role)
            if let wm = ThreadStore.shared.loadReadWatermark(for: role) {
                self.readWatermarkId[role] = wm
            }
        }
        recomputeUnread()
        if ProcessInfo.processInfo.environment["ZEECHAT_SEED_DEMO"] == "1" {
            seedDemoThreads()
        }
    }

    // MARK: - Demo seed (verification only, env-gated)

    private func seedDemoThreads() {
        func make(from: String, to: String, body: String, ago: TimeInterval) -> DispatchMessage {
            let ts = ISO8601DateFormatter.utc(Date().addingTimeInterval(-ago))
            return DispatchMessage(
                id: DispatchID.new(), from_role: from, to_role: to,
                cc: [], type: "message",
                subject: "\(Self.subjectPrefix) demo",
                body: body, thread_id: nil, priority: "normal",
                status: "delivered", direction: from == "ceo" ? "out" : "in",
                attempts: 0, checksum: Checksum.sha256Prefix(body),
                created_at: ts, updated_at: ts,
                delivered_at: ts, read_at: nil, error: nil, is_cc: false
            )
        }
        threads[.pm] = [
            make(from: "ceo", to: "pm", body: "Hey Mac — what's the status on v2.0 hardening?", ago: 600),
            make(from: "pm", to: "ceo", body: "Phase 1 in progress. Crash-loop guard landed, log redaction next.", ago: 540),
            make(from: "ceo", to: "pm", body: "Cool. Any blockers?", ago: 300),
            make(from: "pm", to: "ceo", body: "Nope — clean burn-in for 5 days, 0 divergences.", ago: 60),
        ]
        threads[.swe] = [
            make(from: "ceo", to: "swe", body: "PC — bump the manga-dl test coverage when you can.", ago: 1800),
            make(from: "swe", to: "ceo", body: "On it. 90% baseline, aiming 95%.", ago: 1740),
        ]
    }

    // MARK: - Send

    func send(body: String, to role: ContactRole) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let subject = "\(Self.subjectPrefix) \(String(trimmed.prefix(60)))"
        let optimistic = DispatchMessage.makeFromCEO(to: role,
                                                     subject: subject,
                                                     body: trimmed)
        threads[role, default: []].append(optimistic)
        persist(role)
        startThinking(for: role)
        do {
            let resp = try await client.send(optimistic, to: role)
            lastError = nil
            // Bug fix: the chat shim doesn't accept a client-supplied id —
            // it forges a fresh one server-side and returns it in resp.id.
            // Without this swap, the next inbox poll surfaces the server's
            // copy under a different id and the dedupe-by-id misses, so
            // the bubble appears TWICE. Swap the optimistic row's id to
            // the server's so the poll's row merges into it.
            if let idx = threads[role]?.firstIndex(where: { $0.id == optimistic.id }) {
                var fixed = threads[role]![idx]
                fixed = DispatchMessage(
                    id: resp.id,
                    from_role: fixed.from_role,
                    to_role: fixed.to_role,
                    cc: fixed.cc,
                    type: fixed.type,
                    subject: fixed.subject,
                    body: fixed.body,
                    thread_id: fixed.thread_id,
                    priority: fixed.priority,
                    status: resp.status,
                    direction: fixed.direction,
                    attempts: fixed.attempts,
                    checksum: fixed.checksum,
                    created_at: fixed.created_at,
                    updated_at: fixed.updated_at,
                    delivered_at: fixed.delivered_at,
                    read_at: fixed.read_at,
                    error: fixed.error,
                    is_cc: fixed.is_cc
                )
                threads[role]?[idx] = fixed
                persist(role)
            }
        } catch {
            lastError = "Send failed: \(error.localizedDescription)"
            stopThinking(for: role)
        }
    }

    // MARK: - Polling

    func startPolling(every seconds: TimeInterval = 5) {
        guard pollTask == nil else { return }
        isPolling = true
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshOnce()
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
    }

    /// One-shot reload — polls each daemon's chat inbox using its
    /// per-role cursor. Silently skips daemons without a configured
    /// chat token (graceful Mac-side gap before Mac shim ships).
    /// Fires local notifications for new inbound messages and updates
    /// the badge afterwards.
    func refreshOnce() async {
        var firstError: String? = nil
        for role in ContactRole.allCases {
            guard !settings.chatToken(for: role).isEmpty else { continue }
            do {
                let resp = try await client.fetchChatInbox(for: role, since: cursors[role] ?? nil)
                mergeInbox(resp.messages, for: role)
                if let c = resp.cursor, !c.isEmpty {
                    cursors[role] = c
                    ThreadStore.shared.saveCursor(c, for: role)
                }
            } catch {
                if firstError == nil {
                    firstError = "\(role.displayName) refresh failed: \(error.localizedDescription)"
                }
            }
        }
        lastError = firstError
        recomputeUnread()
        NotificationService.shared.setBadge(unread.values.reduce(0, +))
    }

    /// Merge inbox rows into the thread for one daemon. Fires a local
    /// notification for any message that is brand-new (not in our
    /// pre-merge set) AND inbound (from_role != ceo) AND not from the
    /// currently-visible thread.
    private func mergeInbox(_ rows: [DispatchMessage], for role: ContactRole) {
        let filtered = rows.filter { m in
            guard m.subject.hasPrefix(Self.subjectPrefix) else { return false }
            let isCEOPair = (m.from_role == "ceo" && m.to_role == role.rawValue)
                || (m.to_role == "ceo" && m.from_role == role.rawValue)
            return isCEOPair
        }
        let existing = threads[role] ?? []
        let existingIds = Set(existing.map { $0.id })
        var byId: [String: DispatchMessage] = [:]
        for m in existing { byId[m.id] = m }
        for m in filtered { byId[m.id] = m }
        let merged = byId.values.sorted { $0.created_at < $1.created_at }
        threads[role] = merged
        persist(role)

        // Notification + thinking-clear for any brand-new inbound replies.
        let newInbound = filtered.filter { m in
            m.from_role != "ceo" && !existingIds.contains(m.id)
        }
        if !newInbound.isEmpty {
            stopThinking(for: role)
            for m in newInbound {
                let suppress = (visibleContact == role)
                NotificationService.shared.notifyInbound(m, from: role, suppress: suppress)
            }
        }
    }

    // MARK: - Read / unread

    /// Mark the thread for `role` as fully read up to the latest message
    /// the user has seen (called when the user opens the thread or scrolls
    /// to the bottom). Updates badge.
    func markRead(role: ContactRole) {
        guard let last = threads[role]?.last else { return }
        readWatermarkId[role] = last.id
        ThreadStore.shared.saveReadWatermark(last.id, for: role)
        recomputeUnread()
        NotificationService.shared.setBadge(unread.values.reduce(0, +))
    }

    private func recomputeUnread() {
        for role in ContactRole.allCases {
            let msgs = threads[role] ?? []
            let wm = readWatermarkId[role]
            // Count inbound messages that are after the watermark.
            let wmIndex = msgs.firstIndex(where: { $0.id == wm }) ?? -1
            var count = 0
            for (i, m) in msgs.enumerated() where i > wmIndex && m.from_role != "ceo" {
                count += 1
            }
            unread[role] = count
        }
    }

    private func persist(_ role: ContactRole) {
        ThreadStore.shared.save(threads[role] ?? [], for: role)
    }

    // MARK: - Thinking heuristic

    private func startThinking(for role: ContactRole) {
        thinking[role] = true
        thinkingTimers[role]?.cancel()
        thinkingTimers[role] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            await MainActor.run {
                self?.thinking[role] = false
            }
        }
    }

    private func stopThinking(for role: ContactRole) {
        thinking[role] = false
        thinkingTimers[role]?.cancel()
        thinkingTimers[role] = nil
    }

    // MARK: - Convenience

    func lastMessagePreview(for role: ContactRole) -> (text: String, ts: Date?)? {
        guard let last = threads[role]?.last else { return nil }
        let prefix = last.from_role == "ceo" ? "You: " : ""
        let raw = last.body.replacingOccurrences(of: "\n", with: " ")
        let text = prefix + String(raw.prefix(80))
        return (text, ISO8601.parse(last.created_at))
    }
}
