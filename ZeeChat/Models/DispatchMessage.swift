import Foundation

/// Mirror of dispatch.models.Message — the on-wire shape the daemon's
/// /peer/deliver endpoint expects (and what /observer/api/messages returns).
struct DispatchMessage: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let from_role: String       // "ceo" | "pm" | "swe"
    let to_role: String
    var cc: [String] = []
    let type: String            // "message" | "ack" | ...
    let subject: String
    let body: String
    var thread_id: String? = nil
    let priority: String        // "low" | "normal" | "high" | "urgent"
    let status: String
    let direction: String       // "in" | "out"
    var attempts: Int = 0
    let checksum: String        // "sha256:<64-hex>"
    let created_at: String
    var updated_at: String
    var delivered_at: String? = nil
    var read_at: String? = nil
    var error: String? = nil
    var is_cc: Bool = false

    // MARK: - v2.0 Conversation Studio wire fields (additive, optional)
    //
    // All five are nil until SWE's backend lands the new schema. Decoder
    // tolerates absence (Optional => nil on missing key). On SWE wire
    // ship, no iOS decode change needed.
    /// One of: "text" (default) | "spec" | "image" | "refine_request" |
    /// "refine_response" | "voice_turn". Treated as "text" when nil.
    var kind: String? = nil
    /// Full image URL (served via SWE's /api/attachments/{sha256}).
    var attachment_url: String? = nil
    /// Base64-encoded JPEG thumbnail (~10KB), inlined for low-latency
    /// render before the full image fetches.
    var attachment_preview: String? = nil
    /// SHA256 hex of full image bytes — used for upload dedup.
    var attachment_sha256: String? = nil
    /// UUID matching a refine_request to its refine_response.
    var refine_id: String? = nil

    /// Build a fresh CEO-originated message ready for /peer/deliver.
    static func makeFromCEO(to: ContactRole, subject: String, body: String,
                            priority: String = "normal",
                            threadId: String? = nil) -> DispatchMessage {
        let now = ISO8601.utcNow()
        return DispatchMessage(
            id: DispatchID.new(),
            from_role: "ceo",
            to_role: to.rawValue,
            cc: [],
            type: "message",
            subject: subject,
            body: body,
            thread_id: threadId,
            priority: priority,
            status: "queued",
            direction: "out",
            attempts: 0,
            checksum: Checksum.sha256Prefix(body),
            created_at: now,
            updated_at: now,
            delivered_at: nil,
            read_at: nil,
            error: nil,
            is_cc: false
        )
    }
}

/// Stable identity for the two Claude contacts.
enum ContactRole: String, CaseIterable, Identifiable, Codable {
    case pm = "pm"
    case swe = "swe"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .pm: return "Mac Claude"
        case .swe: return "PC Claude"
        }
    }
    var subtitle: String {
        switch self {
        case .pm: return "rishis-macbook-pro · pm"
        case .swe: return "zee-cloud · swe"
        }
    }
}

enum DispatchID {
    /// 12-char lowercase hex, matching dispatch.models.new_id().
    static func new() -> String {
        let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return String(uuid.prefix(12))
    }
}

enum ISO8601 {
    /// "yyyy-MM-ddTHH:mm:ssZ" — matches dispatch.models.utcnow().
    static func utcNow() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f.string(from: Date())
    }

    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f.date(from: s)
    }
}

extension ISO8601DateFormatter {
    static func utc(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f.string(from: date)
    }
}

enum Checksum {
    /// Pure-Swift SHA-256 — keeps us off CommonCrypto interop noise for an MVP.
    static func sha256Prefix(_ body: String) -> String {
        let bytes = Array(body.utf8)
        let digest = SHA256.hash(bytes)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }
}
