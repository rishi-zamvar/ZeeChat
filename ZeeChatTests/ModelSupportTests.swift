import XCTest
@testable import ZeeChat

/// Unit coverage for the pure model + utility layer that the wire and UI
/// build on: timestamp formatting, checksums, id minting, contact
/// identity, the compact send payload, and the error/probe value types.
///
/// Everything here is deterministic and offline — no network, no
/// UserDefaults, no Keychain — so it runs cleanly in any environment.
final class ModelSupportTests: XCTestCase {

    // MARK: - ISO8601 (daemon wire timestamps)

    func test_iso8601_roundTripsWireFormat() {
        let s = "2026-06-07T16:00:00Z"
        let date = ISO8601.parse(s)
        XCTAssertNotNil(date)
        XCTAssertEqual(ISO8601.string(from: date!), s)
    }

    func test_iso8601_utcNow_matchesWireShape() {
        let now = ISO8601.utcNow()
        // yyyy-MM-ddTHH:mm:ssZ — exactly 20 chars, trailing Z.
        XCTAssertEqual(now.count, 20)
        XCTAssertTrue(now.hasSuffix("Z"))
        // Must be parseable back into a Date.
        XCTAssertNotNil(ISO8601.parse(now))
    }

    func test_iso8601_parse_nilOrMalformed_returnsNil() {
        XCTAssertNil(ISO8601.parse(nil))
        XCTAssertNil(ISO8601.parse(""))
        XCTAssertNil(ISO8601.parse("not-a-timestamp"))
        // Missing the trailing Z the daemon always emits.
        XCTAssertNil(ISO8601.parse("2026-06-07 16:00:00"))
    }

    // MARK: - Checksum / SHA256

    /// Known-answer vector: SHA256("abc") is a fixed, well-published
    /// value. Guards against any accidental change to the digest path.
    func test_sha256_knownAnswerVector() {
        let hex = SHA256.hex(of: Data("abc".utf8))
        XCTAssertEqual(hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(hex.count, 64)
    }

    func test_checksum_prefixesSha256() {
        let c = Checksum.sha256Prefix("abc")
        XCTAssertEqual(c, "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertTrue(c.hasPrefix("sha256:"))
    }

    func test_checksum_isDeterministicAndBodySensitive() {
        XCTAssertEqual(Checksum.sha256Prefix("hello"), Checksum.sha256Prefix("hello"))
        XCTAssertNotEqual(Checksum.sha256Prefix("hello"), Checksum.sha256Prefix("hello "))
    }

    // MARK: - DispatchID

    func test_dispatchID_is12LowercaseHexChars() {
        for _ in 0..<50 {
            let id = DispatchID.new()
            XCTAssertEqual(id.count, 12, "id must be 12 chars to match dispatch.models.new_id()")
            XCTAssertTrue(id.allSatisfy { $0.isHexDigit && !$0.isUppercase },
                          "id must be lowercase hex; got '\(id)'")
        }
    }

    func test_dispatchID_isReasonablyUnique() {
        let ids = (0..<200).map { _ in DispatchID.new() }
        XCTAssertEqual(Set(ids).count, ids.count, "12-hex ids should not collide across 200 mints")
    }

    // MARK: - ContactRole

    func test_contactRole_identityAndDisplay() {
        XCTAssertEqual(ContactRole.pm.rawValue, "pm")
        XCTAssertEqual(ContactRole.swe.rawValue, "swe")
        XCTAssertEqual(ContactRole.pm.id, "pm")
        XCTAssertEqual(ContactRole.pm.displayName, "Mac Claude")
        XCTAssertEqual(ContactRole.swe.displayName, "PC Claude")
        XCTAssertTrue(ContactRole.pm.subtitle.contains("pm"))
        XCTAssertTrue(ContactRole.swe.subtitle.contains("swe"))
        XCTAssertEqual(ContactRole.allCases, [.pm, .swe])
    }

    func test_contactRole_decodesFromRawValue() throws {
        let decoded = try JSONDecoder().decode(ContactRole.self,
                                               from: Data("\"swe\"".utf8))
        XCTAssertEqual(decoded, .swe)
    }

    // MARK: - ChatSendRequest wire shape

    /// The compact send payload must carry to/subject/body/priority and
    /// must NOT include from_role — the shim hard-codes it to "ceo"
    /// server-side and dropping it client-side prevents spoofing.
    func test_chatSendRequest_omitsFromRole() throws {
        let req = ChatSendRequest(to: "swe", subject: "ZeeChat: hi",
                                  body: "hello there", priority: "normal")
        let json = String(data: try JSONEncoder().encode(req), encoding: .utf8) ?? ""
        for key in ["to", "subject", "body", "priority"] {
            XCTAssertTrue(json.contains("\"\(key)\""), "send payload must include '\(key)'")
        }
        XCTAssertFalse(json.contains("from_role"), "send payload must NOT include from_role")
    }

    // MARK: - NetError

    func test_netError_descriptions() {
        XCTAssertEqual(NetError.misconfigured("no host").errorDescription,
                       "Misconfigured: no host")
        XCTAssertEqual(NetError.transport("dropped").errorDescription,
                       "Network error: dropped")
    }

    /// Server error bodies are truncated to keep the inline banner sane;
    /// long bodies gain an ellipsis, short ones pass through verbatim.
    func test_netError_server_truncatesLongBodies() {
        let long = String(repeating: "x", count: 500)
        let desc = NetError.server(status: 500, body: long).errorDescription ?? ""
        XCTAssertTrue(desc.hasPrefix("Server 500: "))
        XCTAssertTrue(desc.hasSuffix("…"), "over-200-char bodies should be ellipsized")
        XCTAssertLessThan(desc.count, long.count)

        let short = NetError.server(status: 404, body: "not found").errorDescription ?? ""
        XCTAssertEqual(short, "Server 404: not found")
        XCTAssertFalse(short.hasSuffix("…"))
    }

    // MARK: - ProbeOutcome

    func test_probeOutcome_okAndFail() {
        XCTAssertTrue(ProbeOutcome.ok.isOk)
        XCTAssertEqual(ProbeOutcome.ok.detail, "OK")

        let fail = ProbeOutcome.fail("HTTP 503")
        XCTAssertFalse(fail.isOk)
        XCTAssertEqual(fail.detail, "HTTP 503")
        XCTAssertEqual(fail, ProbeOutcome.fail("HTTP 503"))
        XCTAssertNotEqual(fail, ProbeOutcome.ok)
    }
}
