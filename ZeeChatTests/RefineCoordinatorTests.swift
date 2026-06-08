import XCTest
@testable import ZeeChat

/// TDD for RefineCoordinator — the spec composer's async round-trip
/// matcher. iOS sends `kind=refine_request + refine_id` via dispatch,
/// PM/SWE Claude responds with `kind=refine_response + same refine_id`,
/// iOS matches by refine_id and drops the refined body back into the
/// composer. Per RESEARCH.md ranked #1 risk: async, race-prone, silent
/// failure mode if refine_id matching breaks.
///
/// Daemon doesn't know what refine means — agents handle the prompt.
/// This coordinator is iOS's correlation + timeout layer; it knows
/// nothing about dispatch internals beyond send + a notification of
/// incoming messages.
final class RefineCoordinatorTests: XCTestCase {

    func test_request_returnsRefinedBody_whenResponseArrivesWithMatchingId() async throws {
        let coord = RefineCoordinator(timeout: 5)
        async let refined = coord.refine(
            body: "fix the streak panel",
            target: .pm,
            send: { kind, body, refineId in
                // Send: dispatcher would post a DispatchMessage with
                // kind=refine_request + refineId. We just record + later
                // simulate the matching reply landing.
                XCTAssertEqual(kind, "refine_request")
                XCTAssertEqual(body, "fix the streak panel")
                XCTAssertFalse(refineId.isEmpty)
            }
        )
        // Simulate the receiving Claude's reply arriving on the dispatch
        // inbox a bit later (need to give the await loop a tick).
        try await Task.sleep(nanoseconds: 50_000_000)
        // The coordinator tracks in-flight refine_ids; grab the current
        // one and dispatch a "response".
        guard let inflight = await coord.inFlightIds.first else {
            XCTFail("Expected one in-flight refine request")
            return
        }
        await coord.handleIncoming(refineId: inflight, body: "## Fix streak panel\n- ...")
        let result = try await refined
        XCTAssertEqual(result, "## Fix streak panel\n- ...")
    }

    func test_request_timesOut_whenNoResponseArrives() async {
        let coord = RefineCoordinator(timeout: 1)
        do {
            _ = try await coord.refine(
                body: "no one will reply",
                target: .pm,
                send: { _, _, _ in /* simulate the request firing but no reply */ }
            )
            XCTFail("Expected timeout error")
        } catch RefineError.timeout {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_multipleInFlight_routesByRefineId() async throws {
        let coord = RefineCoordinator(timeout: 5)
        // Two concurrent refines; each must get its own response back.
        async let a = coord.refine(body: "alpha", target: .pm, send: { _, _, _ in })
        async let b = coord.refine(body: "bravo", target: .swe, send: { _, _, _ in })
        // Both should now be in-flight.
        try await Task.sleep(nanoseconds: 50_000_000)
        let ids = await coord.inFlightIds
        XCTAssertEqual(ids.count, 2, "Both refines should be in-flight")
        // Reply to each by id. Match A's id with payload "ALPHA refined";
        // match B's with "BRAVO refined". Map by send-order: we know A
        // was created first, but actual id ordering depends on Set
        // iteration — so use the SEND callback to capture the id-per-body
        // mapping in a fresh coord.
        // Easier: rebuild with explicit capture.
        let coord2 = RefineCoordinator(timeout: 5)
        var capturedAlpha: String?
        var capturedBravo: String?
        async let r1 = coord2.refine(body: "alpha", target: .pm, send: { _, b, rid in
            if b == "alpha" { capturedAlpha = rid }
        })
        async let r2 = coord2.refine(body: "bravo", target: .swe, send: { _, b, rid in
            if b == "bravo" { capturedBravo = rid }
        })
        try await Task.sleep(nanoseconds: 100_000_000)
        guard let aId = capturedAlpha, let bId = capturedBravo else {
            XCTFail("Captures missing")
            return
        }
        XCTAssertNotEqual(aId, bId, "Each refine must mint a unique refine_id")
        await coord2.handleIncoming(refineId: aId, body: "ALPHA refined")
        await coord2.handleIncoming(refineId: bId, body: "BRAVO refined")
        let aResult = try await r1
        let bResult = try await r2
        XCTAssertEqual(aResult, "ALPHA refined")
        XCTAssertEqual(bResult, "BRAVO refined")
        // Also drain the first coord so its background tasks don't leak.
        _ = try? await a
        _ = try? await b
    }

    func test_handleIncoming_unknownRefineId_isNoOp() async {
        let coord = RefineCoordinator(timeout: 5)
        // No in-flight requests; arrival of a refine_response with a
        // random id must not crash + must not block future requests.
        await coord.handleIncoming(refineId: "stale-uuid-from-old-session", body: "ignored")
        let ids = await coord.inFlightIds
        XCTAssertEqual(ids.count, 0)
    }
}
