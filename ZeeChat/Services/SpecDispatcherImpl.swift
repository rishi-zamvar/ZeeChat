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
        // SWE backend wire not landed yet — synth a noticeable placeholder
        // so the composer flow ships now. Real wire replaces this with:
        //   try await refineCoordinator.refine(body:target:send:) { kind, body, refineId in
        //       await chatStore.sendRaw(kind: kind, body: body, refineId: refineId, to: target.toContactRole())
        //   }
        try? await Task.sleep(nanoseconds: 600_000_000)
        return body + "\n\n— (refine round-trip pending backend wire) —"
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
