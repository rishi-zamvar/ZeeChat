import Foundation
import SwiftUI

/// Per-contact chat state — owns the in-memory thread, drives sends,
/// and runs the polling loop that surfaces replies from each daemon's
/// /api/v1/chat/inbox shim. Inbox is daemon-local so we poll Mac for the
/// PM thread and PC for the SWE thread, each with its own cursor.
@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var threads: [ContactRole: [DispatchMessage]] = [
        .pm: [], .swe: [],
    ]
    @Published private(set) var lastError: String? = nil
    @Published private(set) var isPolling: Bool = false

    private let client: DispatchClient
    private var pollTask: Task<Void, Never>? = nil
    private let settings: AppSettings
    /// Per-daemon cursors so each inbox poll only fetches deltas.
    private var cursors: [ContactRole: String] = [:]

    /// Subject prefix that scopes "what counts as a ZeeChat message" so we
    /// don't surface unrelated PM<->SWE traffic in the iPhone UI.
    static let subjectPrefix = "ZeeChat:"

    init(settings: AppSettings) {
        self.settings = settings
        self.client = DispatchClient(settings: settings)
        if ProcessInfo.processInfo.environment["ZEECHAT_SEED_DEMO"] == "1" {
            seedDemoThreads()
        }
    }

    /// Verification-only: pre-populate both threads with sample messages so a
    /// screenshot of the chat view shows real bubbles without needing a live
    /// daemon reply. Gated by env var; never runs in normal operation.
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
        let msg = DispatchMessage.makeFromCEO(to: role,
                                              subject: subject,
                                              body: trimmed)
        // Optimistic: drop it into the local thread immediately so the UI
        // updates without waiting for the round-trip. Mark as outbound.
        threads[role, default: []].append(msg)
        do {
            _ = try await client.send(msg, to: role)
            lastError = nil
        } catch {
            lastError = "Send failed: \(error.localizedDescription)"
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

    /// One-shot reload — polls each daemon's chat inbox (Mac for the PM
    /// thread, PC for the SWE thread) using its per-role cursor. Skips a
    /// daemon silently if its chat token isn't configured (Mac shim ships
    /// after PC; phone keeps working with one side wired up).
    func refreshOnce() async {
        var firstError: String? = nil
        for role in ContactRole.allCases {
            guard !settings.chatToken(for: role).isEmpty else { continue }
            do {
                let resp = try await client.fetchChatInbox(for: role, since: cursors[role])
                mergeInbox(resp.messages, for: role)
                if let c = resp.cursor, !c.isEmpty { cursors[role] = c }
            } catch {
                if firstError == nil {
                    firstError = "\(role.displayName) refresh failed: \(error.localizedDescription)"
                }
            }
        }
        lastError = firstError
    }

    /// Merge inbox rows into the thread for one daemon. Each row from
    /// `<role>`'s inbox is a CEO↔<role> exchange, so we accept rows where
    /// CEO is one end and the contact-role is the other AND the subject
    /// starts with the ZeeChat prefix (keeps autonomous traffic out of UI).
    private func mergeInbox(_ rows: [DispatchMessage], for role: ContactRole) {
        let filtered = rows.filter { m in
            guard m.subject.hasPrefix(Self.subjectPrefix) else { return false }
            let isCEOPair = (m.from_role == "ceo" && m.to_role == role.rawValue)
                || (m.to_role == "ceo" && m.from_role == role.rawValue)
            return isCEOPair
        }
        let existing = threads[role] ?? []
        var byId: [String: DispatchMessage] = [:]
        for m in existing { byId[m.id] = m }
        for m in filtered { byId[m.id] = m }
        threads[role] = byId.values.sorted { $0.created_at < $1.created_at }
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
