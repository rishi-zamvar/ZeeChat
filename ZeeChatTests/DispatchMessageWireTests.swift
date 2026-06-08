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
}
