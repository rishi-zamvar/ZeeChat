import XCTest
@testable import ZeeChat

/// First test in the ZeeChat suite — guards the wire shape iOS sends
/// to the dispatch daemon. If the daemon team adds a required field
/// or renames a key, this trips immediately rather than at runtime on
/// CEO's phone.
///
/// v2.0 will extend DispatchMessage with optional fields (kind,
/// attachment_url, attachment_preview, refine_id). When those land,
/// add round-trip cases here.
final class DispatchMessageWireTests: XCTestCase {

    /// JSON round-trip: encode → decode produces an equal message.
    /// Catches Codable drift if a field is added without proper
    /// CodingKeys mapping.
    func test_dispatchMessage_encodeDecodeRoundTrip() throws {
        let original = DispatchMessage(
            id: "abc123def456",
            from_role: "ceo",
            to_role: "pm",
            cc: [],
            type: "message",
            subject: "ZeeChat: hello",
            body: "round-trip test body",
            thread_id: nil,
            priority: "normal",
            status: "queued",
            direction: "out",
            attempts: 0,
            checksum: "sha256:0000000000000000000000000000000000000000000000000000000000000000",
            created_at: "2026-06-07T16:00:00Z",
            updated_at: "2026-06-07T16:00:00Z",
            delivered_at: nil,
            read_at: nil,
            error: nil,
            is_cc: false
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DispatchMessage.self, from: encoded)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.from_role, original.from_role)
        XCTAssertEqual(decoded.body, original.body)
        XCTAssertEqual(decoded.checksum, original.checksum)
    }

    /// Snake-case wire shape: keys must be snake_case (from_role, not
    /// fromRole). Catches accidental keyEncodingStrategy changes that
    /// would silently break the dispatch daemon's parse.
    func test_dispatchMessage_emitsSnakeCaseKeys() throws {
        // Populate Optionals so all keys serialize — default JSONEncoder
        // omits nil keys, which would mask camelCase-vs-snake_case bugs
        // on typically-null fields (thread_id, delivered_at, read_at).
        let msg = DispatchMessage(
            id: "x",
            from_role: "ceo",
            to_role: "pm",
            cc: [],
            type: "message",
            subject: "s",
            body: "b",
            thread_id: "thr1",
            priority: "normal",
            status: "queued",
            direction: "out",
            attempts: 0,
            checksum: "sha256:0",
            created_at: "t",
            updated_at: "t",
            delivered_at: "t",
            read_at: "t",
            error: "none",
            is_cc: false
        )
        let data = try JSONEncoder().encode(msg)
        let str = String(data: data, encoding: .utf8) ?? ""
        for snake in ["from_role", "to_role", "thread_id", "is_cc",
                      "created_at", "updated_at", "delivered_at", "read_at"] {
            XCTAssertTrue(str.contains("\"\(snake)\""), "Wire shape must emit snake_case key '\(snake)'")
        }
        for camel in ["fromRole", "toRole", "threadId", "isCc"] {
            XCTAssertFalse(str.contains("\"\(camel)\""), "Wire shape must NOT emit camelCase key '\(camel)'")
        }
    }

    // MARK: - v2.0 Conversation Studio optional fields

    /// The v2.0 additive fields (kind, attachment_url, attachment_preview,
    /// attachment_sha256, refine_id) must survive a JSON round-trip once
    /// SWE's backend starts populating them. Snake_case keys, no drift.
    func test_dispatchMessage_v2Fields_encodeDecodeRoundTrip() throws {
        var msg = DispatchMessage.makeFromCEO(to: .swe, subject: "ZeeChat: spec",
                                              body: "refine the streak panel")
        msg.kind = "refine_response"
        msg.attachment_url = "http://zee-cloud:8770/api/attachments/deadbeef"
        msg.attachment_preview = "AAAA=="
        msg.attachment_sha256 = "deadbeef"
        msg.refine_id = "11111111-2222-3333-4444-555555555555"

        let encoded = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(DispatchMessage.self, from: encoded)
        XCTAssertEqual(decoded, msg)
        XCTAssertEqual(decoded.kind, "refine_response")
        XCTAssertEqual(decoded.refine_id, "11111111-2222-3333-4444-555555555555")

        let str = String(data: encoded, encoding: .utf8) ?? ""
        for snake in ["attachment_url", "attachment_preview", "attachment_sha256", "refine_id"] {
            XCTAssertTrue(str.contains("\"\(snake)\""), "v2.0 field must emit snake_case key '\(snake)'")
        }
    }

    /// Decoder tolerance: a daemon that has NOT yet shipped the v2.0
    /// schema returns rows carrying the base `Message` fields but none of
    /// the additive v2.0 keys. Because those five are declared Optional,
    /// they decode to nil rather than throwing — the whole forward-compat
    /// contract hinges on this. (Note: the base fields that have Swift
    /// defaults — cc, attempts, is_cc — are still required on the wire,
    /// since synthesized Codable does not substitute defaults for missing
    /// keys; the live daemon always emits them, which is why this row
    /// includes them.)
    func test_dispatchMessage_decodesRow_withoutV2Keys() throws {
        let legacy = """
        {
          "id": "abc123def456",
          "from_role": "swe",
          "to_role": "ceo",
          "cc": [],
          "type": "message",
          "subject": "ZeeChat: hi",
          "body": "no v2 fields here",
          "priority": "normal",
          "status": "delivered",
          "direction": "in",
          "attempts": 0,
          "checksum": "sha256:0",
          "created_at": "2026-06-07T16:00:00Z",
          "updated_at": "2026-06-07T16:00:00Z",
          "is_cc": false
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DispatchMessage.self, from: legacy)
        XCTAssertEqual(decoded.id, "abc123def456")
        // The five additive v2.0 fields are absent → nil, no throw.
        XCTAssertNil(decoded.kind)
        XCTAssertNil(decoded.attachment_url)
        XCTAssertNil(decoded.attachment_preview)
        XCTAssertNil(decoded.attachment_sha256)
        XCTAssertNil(decoded.refine_id)
    }

    /// `makeFromCEO` mints a well-formed outbound row: ceo-originated,
    /// queued, direction out, sha256-prefixed checksum, 12-hex id, and
    /// no v2.0 fields set yet.
    func test_makeFromCEO_producesWellFormedOutboundRow() {
        let msg = DispatchMessage.makeFromCEO(to: .pm, subject: "ZeeChat: hey",
                                              body: "status?")
        XCTAssertEqual(msg.from_role, "ceo")
        XCTAssertEqual(msg.to_role, "pm")
        XCTAssertEqual(msg.direction, "out")
        XCTAssertEqual(msg.status, "queued")
        XCTAssertEqual(msg.type, "message")
        XCTAssertTrue(msg.checksum.hasPrefix("sha256:"))
        XCTAssertEqual(msg.id.count, 12)
        XCTAssertNil(msg.kind)
    }

    /// `withServerAck` re-keys id + status (used to merge the optimistic
    /// bubble with the server's forged row) and leaves everything else
    /// untouched.
    func test_withServerAck_swapsIdAndStatusOnly() {
        let msg = DispatchMessage.makeFromCEO(to: .pm, subject: "s", body: "b")
        let acked = msg.withServerAck(id: "server0000id", status: "delivered")
        XCTAssertEqual(acked.id, "server0000id")
        XCTAssertEqual(acked.status, "delivered")
        XCTAssertEqual(acked.body, msg.body)
        XCTAssertEqual(acked.created_at, msg.created_at)
        XCTAssertEqual(acked.checksum, msg.checksum)
    }
}
