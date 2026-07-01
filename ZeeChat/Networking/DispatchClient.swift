import Foundation

/// Client for the dispatch daemon's `/api/v1/chat/*` iPhone-facing shim
/// over Tailscale. Each daemon issues its own chat_token (constant-time
/// compared on the server with hmac.compare_digest). The phone holds
/// PC's token and Mac's token independently so trust domains stay split.
///
/// Wire shape (per dispatch v1.3 / PC commit 6dbbc4c):
///   POST /api/v1/chat/send   body: {to, subject, body, priority}
///                            from_role hard-coded server-side to "ceo"
///                            extra fields ignored (Pydantic extra='ignore')
///                            returns {id, status}
///   GET  /api/v1/chat/inbox?since=<msg_id>&limit=<n>
///                            returns {messages: [...], cursor, ts}
///                            cursor advances; unknown since-id falls through
///                            to all messages so phone never dead-locks.
struct DispatchClient {
    let settings: AppSettings
    let session: URLSession

    /// Shared coders — construction is non-trivial and the inbox poll
    /// hits `decoder` every few seconds, so we reuse one instance each.
    /// Both are thread-safe once configured. The default (no key
    /// strategy) preserves the daemon's snake_case wire keys, which
    /// `DispatchMessage`'s stored properties already match verbatim.
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    init(settings: AppSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    // MARK: - Send

    /// POST /api/v1/chat/send on the target daemon. Body sent as the
    /// shim's compact shape, not the full DispatchMessage row.
    func send(_ message: DispatchMessage, to role: ContactRole) async throws -> ChatSendResponse {
        guard let base = settings.peerBaseURL(for: role) else {
            throw NetError.misconfigured("missing host/port for \(role.rawValue)")
        }
        let token = settings.chatToken(for: role)
        let url = base.appendingPathComponent("api/v1/chat/send")
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let payload = ChatSendRequest(
            to: role.rawValue,
            subject: message.subject,
            body: message.body,
            priority: message.priority
        )
        req.httpBody = try Self.encoder.encode(payload)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw NetError.transport("no HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NetError.server(status: http.statusCode, body: body)
        }
        return try Self.decoder.decode(ChatSendResponse.self, from: data)
    }

    // MARK: - Inbox

    /// GET /api/v1/chat/inbox?since=<cursor>&limit=<n> on the target daemon.
    /// Inbox is daemon-local (the shim queries the daemon's own message
    /// store), so the PM thread polls Mac and the SWE thread polls PC.
    func fetchChatInbox(for role: ContactRole,
                        since cursor: String? = nil,
                        limit: Int = 200) async throws -> ChatInboxResponse {
        guard let base = settings.peerBaseURL(for: role) else {
            throw NetError.misconfigured("missing host/port for \(role.rawValue)")
        }
        let token = settings.chatToken(for: role)
        var comps = URLComponents(url: base.appendingPathComponent("api/v1/chat/inbox"),
                                  resolvingAgainstBaseURL: false)!
        var q: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let c = cursor, !c.isEmpty { q.append(URLQueryItem(name: "since", value: c)) }
        comps.queryItems = q
        guard let url = comps.url else { throw NetError.misconfigured("bad inbox URL") }
        var req = URLRequest(url: url, timeoutInterval: 15)
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw NetError.transport("no HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NetError.server(status: http.statusCode, body: body)
        }
        return try Self.decoder.decode(ChatInboxResponse.self, from: data)
    }

    // MARK: - Probe

    /// Cheap health probe for Settings — pings the chat shim on each
    /// daemon (token-gated). Observer probe retained for diagnostics.
    func probe() async -> ProbeResult {
        async let mac = pingChatInbox(role: .pm)
        async let pc = pingChatInbox(role: .swe)
        async let obs = pingObserver()
        return await ProbeResult(mac: mac, pc: pc, observer: obs)
    }

    private func pingChatInbox(role: ContactRole) async -> ProbeOutcome {
        guard let base = settings.peerBaseURL(for: role) else { return .fail("no URL") }
        let token = settings.chatToken(for: role)
        var comps = URLComponents(url: base.appendingPathComponent("api/v1/chat/inbox"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "limit", value: "1")]
        guard let url = comps.url else { return .fail("bad URL") }
        var req = URLRequest(url: url, timeoutInterval: 5)
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (_, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 { return .ok }
            if let http = resp as? HTTPURLResponse { return .fail("HTTP \(http.statusCode)") }
            return .fail("no http response")
        } catch {
            return .fail(error.localizedDescription)
        }
    }

    private func pingObserver() async -> ProbeOutcome {
        guard let base = settings.observerBaseURL() else { return .fail("no URL") }
        let url = base.appendingPathComponent("observer/api/status")
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.setValue("Bearer \(settings.observerToken)", forHTTPHeaderField: "Authorization")
        do {
            let (_, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 { return .ok }
            if let http = resp as? HTTPURLResponse { return .fail("HTTP \(http.statusCode)") }
            return .fail("no http response")
        } catch {
            return .fail(error.localizedDescription)
        }
    }
}

/// Compact shape the shim expects. `from_role` is intentionally absent —
/// the server hard-codes it to "ceo" and `extra='ignore'` silently drops
/// any client-supplied value to prevent spoofing.
struct ChatSendRequest: Codable {
    let to: String
    let subject: String
    let body: String
    let priority: String
}

struct ChatSendResponse: Codable {
    let id: String
    let status: String
}

/// Cursor-paginated inbox. `cursor` is the next `since=` value to use;
/// echoing it back returns only newer messages. `messages` rows are the
/// daemon's standard DispatchMessage shape.
struct ChatInboxResponse: Codable {
    let messages: [DispatchMessage]
    let cursor: String?
    let ts: String?
}

enum NetError: LocalizedError {
    case misconfigured(String)
    case transport(String)
    case server(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .misconfigured(let s): return "Misconfigured: \(s)"
        case .transport(let s): return "Network error: \(s)"
        case .server(let status, let body):
            let snippet = body.count > 200 ? String(body.prefix(200)) + "…" : body
            return "Server \(status): \(snippet)"
        }
    }
}

enum ProbeOutcome: Equatable {
    case ok
    case fail(String)
    var isOk: Bool { if case .ok = self { return true } else { return false } }
    var detail: String {
        switch self {
        case .ok: return "OK"
        case .fail(let s): return s
        }
    }
}

struct ProbeResult {
    let mac: ProbeOutcome
    let pc: ProbeOutcome
    let observer: ProbeOutcome
}
