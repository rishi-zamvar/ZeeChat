import Foundation
import SwiftUI

/// Per-contact chat state — owns the in-memory thread, drives sends,
/// and runs the polling loop that surfaces replies from the observer.
@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var threads: [ContactRole: [DispatchMessage]] = [
        .pm: [], .swe: [],
    ]
    @Published private(set) var lastError: String? = nil
    @Published private(set) var isPolling: Bool = false

    private let client: DispatchClient
    private var pollTask: Task<Void, Never>? = nil

    /// Subject prefix that scopes "what counts as a ZeeChat message" so we
    /// don't surface unrelated PM<->SWE traffic in the iPhone UI.
    static let subjectPrefix = "ZeeChat:"

    init(settings: AppSettings) {
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

    /// One-shot reload from the observer. Pulls all recent messages,
    /// filters to ZeeChat-prefixed traffic involving CEO + a contact,
    /// and merges into the per-contact threads (de-duped by id).
    func refreshOnce() async {
        do {
            let rows = try await client.fetchObserverMessages(limit: 200)
            mergeFromObserver(rows)
            lastError = nil
        } catch {
            lastError = "Refresh failed: \(error.localizedDescription)"
        }
    }

    private func mergeFromObserver(_ rows: [DispatchMessage]) {
        // Group by contact-role: a message belongs to a thread if one end
        // is CEO and the other is pm/swe AND the subject starts with the
        // ZeeChat prefix (keeps the UI focused on phone-originated chats).
        var grouped: [ContactRole: [DispatchMessage]] = [.pm: [], .swe: []]
        for m in rows {
            guard m.subject.hasPrefix(Self.subjectPrefix) else { continue }
            let contactRaw: String
            if m.from_role == "ceo" { contactRaw = m.to_role }
            else if m.to_role == "ceo" { contactRaw = m.from_role }
            else { continue }
            guard let contact = ContactRole(rawValue: contactRaw) else { continue }
            grouped[contact, default: []].append(m)
        }
        for (role, msgs) in grouped {
            let existing = threads[role] ?? []
            // De-dupe by id, prefer the observer's row over the optimistic one.
            var byId: [String: DispatchMessage] = [:]
            for m in existing { byId[m.id] = m }
            for m in msgs { byId[m.id] = m }
            // Sort chronologically (oldest -> newest) for chat-bubble display.
            threads[role] = byId.values.sorted { $0.created_at < $1.created_at }
        }
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
