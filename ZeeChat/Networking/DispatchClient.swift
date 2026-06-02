import Foundation

/// Client for talking to the dispatch daemon's peer + observer planes
/// over Tailscale. Sends go to `/peer/deliver` on the receiving daemon;
/// reads come from the Mac daemon's observer plane.
///
/// Sends use the peer bearer token; observer reads use the observer
/// token (different secret).
struct DispatchClient {
    let settings: AppSettings
    let session: URLSession

    init(settings: AppSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    // MARK: - Send

    /// POST a fresh CEO->{pm|swe} message to that daemon's /peer/deliver.
    /// Returns the DeliveryReceipt body for surfacing send status.
    func send(_ message: DispatchMessage, to role: ContactRole) async throws -> DeliveryReceipt {
        guard let base = settings.peerBaseURL(for: role) else {
            throw NetError.misconfigured("missing host/port for \(role.rawValue)")
        }
        let url = base.appendingPathComponent("peer/deliver")
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(settings.peerToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(message)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw NetError.transport("no HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NetError.server(status: http.statusCode, body: body)
        }
        return try JSONDecoder().decode(DeliveryReceipt.self, from: data)
    }

    // MARK: - Read (observer plane)

    /// GET /observer/api/messages — full message rows, newest-first.
    /// Optional `from_role` filter is supported daemon-side.
    func fetchObserverMessages(limit: Int = 200,
                               fromRole: String? = nil) async throws -> [DispatchMessage] {
        guard let base = settings.observerBaseURL() else {
            throw NetError.misconfigured("missing observer host/port")
        }
        var comps = URLComponents(url: base.appendingPathComponent("observer/api/messages"),
                                  resolvingAgainstBaseURL: false)!
        var q: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let fr = fromRole { q.append(URLQueryItem(name: "from_role", value: fr)) }
        comps.queryItems = q
        guard let url = comps.url else { throw NetError.misconfigured("bad observer URL") }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(settings.observerToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw NetError.transport("no HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NetError.server(status: http.statusCode, body: body)
        }
        // Observer returns rows including all fields. Use lenient decoder so
        // extra/missing optional fields don't blow up our model.
        let decoder = JSONDecoder()
        return try decoder.decode([DispatchMessage].self, from: data)
    }

    /// Cheap health probe for Settings — pings BOTH daemons + the observer
    /// to confirm tokens + reachability before the CEO sends anything.
    func probe() async -> ProbeResult {
        async let mac = pingPeer(role: .pm)
        async let pc = pingPeer(role: .swe)
        async let obs = pingObserver()
        return await ProbeResult(mac: mac, pc: pc, observer: obs)
    }

    private func pingPeer(role: ContactRole) async -> ProbeOutcome {
        guard let base = settings.peerBaseURL(for: role) else { return .fail("no URL") }
        let url = base.appendingPathComponent("peer/ping")
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.setValue("Bearer \(settings.peerToken)", forHTTPHeaderField: "Authorization")
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

struct DeliveryReceipt: Codable {
    let message_id: String
    let accepted: Bool
    var reason: String = ""
    let ts: String
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
