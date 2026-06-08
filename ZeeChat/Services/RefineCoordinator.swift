import Foundation

/// Errors a refine round-trip can fail with.
enum RefineError: Error, Equatable {
    case timeout
    case cancelled
}

/// Async correlation layer for spec-composer Refine round-trips.
///
/// Wire model (per RESEARCH.md):
///   iOS  -> kind="refine_request" + refine_id + body  -> PM/SWE inbox
///   PM/SWE Claude session reads it, re-prompts, dispatches:
///   PM/SWE -> kind="refine_response" + same refine_id + refined body  -> iOS inbox
///   iOS matches by refine_id, hands the refined body back to the
///   composer.
///
/// This actor owns the in-flight refine_id -> continuation map and the
/// timeout watchdog. It knows nothing about the dispatch layer beyond
/// a `send` callback (caller wires that to DispatchClient) and
/// `handleIncoming` (caller calls when the inbox poller sees a
/// kind=refine_response). Trivial to unit-test without network.
actor RefineCoordinator {
    /// Default 30s — covers Claude cold-prompt latency + a buffer.
    /// Tests override to 1s for fast timeout coverage.
    private let timeout: TimeInterval

    /// refine_id -> continuation. When a response lands matching an id,
    /// resume the continuation with the refined body. On timeout,
    /// resume with .timeout error.
    private var pending: [String: CheckedContinuation<String, Error>] = [:]

    /// Test-visible accessor for the current in-flight refine_ids.
    var inFlightIds: Set<String> {
        Set(pending.keys)
    }

    init(timeout: TimeInterval = 30) {
        self.timeout = timeout
    }

    /// Send a refine request and await the matching response. Throws
    /// `RefineError.timeout` if no matching `handleIncoming` arrives
    /// within `timeout` seconds.
    ///
    /// `send` is called synchronously inside this method with the
    /// minted refine_id; the caller wires it to DispatchClient or any
    /// other dispatcher. The send is fire-and-forget — if it actually
    /// fails to land on the wire, the timeout still fires.
    func refine(
        body: String,
        target: SpecTarget,
        send: (_ kind: String, _ body: String, _ refineId: String) -> Void
    ) async throws -> String {
        let refineId = UUID().uuidString
        // Kick off the timeout watchdog. If it fires first, resume
        // with .timeout; if a response lands first, the watchdog's
        // resume becomes a no-op because the continuation is consumed.
        let timeoutTask = Task { [timeout] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            await self.failPending(refineId, with: .timeout)
        }
        defer { timeoutTask.cancel() }

        // Fire the send synchronously so the caller's mock can capture
        // the id before the test resumes.
        send("refine_request", body, refineId)

        return try await withCheckedThrowingContinuation { cont in
            pending[refineId] = cont
        }
    }

    /// Called by the inbox poller when a kind="refine_response" lands.
    /// Unknown refine_ids are silently dropped — stale responses from
    /// a previous session, double-delivery, etc.
    func handleIncoming(refineId: String, body: String) {
        guard let cont = pending.removeValue(forKey: refineId) else { return }
        cont.resume(returning: body)
    }

    /// Watchdog timeout: fail + remove the pending continuation if
    /// still in-flight. Idempotent (no-op if the response arrived
    /// first).
    private func failPending(_ refineId: String, with error: RefineError) {
        guard let cont = pending.removeValue(forKey: refineId) else { return }
        cont.resume(throwing: error)
    }
}
