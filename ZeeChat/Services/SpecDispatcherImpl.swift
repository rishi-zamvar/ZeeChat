import Foundation

/// Production wiring of the `SpecDispatcher` protocol. Bridges the spec
/// composer to the live dispatch pipeline (ChatStore.send + the eventual
/// refine round-trip via RefineCoordinator).
///
/// Refine is gated on SWE's v2.0 backend wire fields landing
/// (`kind=refine_request|refine_response` + `refine_id`). Until then, we
/// synthesize a stub refine on-device so the composer's state machine
/// works end-to-end and the UI is shippable. Swap to the real round-trip
/// once `chatStore.sendRaw(kind:body:refineId:to:)` exists.
@MainActor
final class SpecDispatcherImpl: SpecDispatcher {
    let chatStore: ChatStore
    let refineCoordinator: RefineCoordinator

    init(chatStore: ChatStore, refineCoordinator: RefineCoordinator) {
        self.chatStore = chatStore
        self.refineCoordinator = refineCoordinator
    }

    func refine(body: String, target: SpecTarget) async throws -> String {
        // Real round-trip via the shared coordinator. ChatStore's inbox
        // poll routes kind=refine_response messages back into the same
        // coordinator (see ChatStore.mergeInbox). Pre-backend, SWE
        // ignores the [KIND:refine_request] marker and won't reply, so
        // the await fails with .timeout after 30s — composer surfaces
        // the timeout banner, body stays editable, user can just Send.
        let chatStore = self.chatStore
        return try await refineCoordinator.refine(body: body, target: target) { kind, refineBody, refineId in
            let role: ContactRole = (target == .swe) ? .swe : .pm
            Task {
                await chatStore.sendRaw(
                    kind: kind, body: refineBody,
                    refineId: refineId, to: role
                )
            }
        }
    }

    func send(kind: String, body: String, target: SpecTarget) async throws {
        let marker = "[SPEC] "
        let payload = marker + body
        switch target {
        case .pm:
            await chatStore.send(body: payload, to: .pm)
        case .swe:
            await chatStore.send(body: payload, to: .swe)
        case .both:
            await chatStore.send(body: payload, to: .pm)
            await chatStore.send(body: payload, to: .swe)
        }
    }
}
