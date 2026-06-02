import Foundation

/// Persistent per-daemon endpoint + token. Stored in UserDefaults for the
/// host/port (non-secret) and Keychain for the bearer tokens.
///
/// Two daemons, two tokens:
///   - Mac (pm) at rishis-macbook-pro:8770  -- peer_token from secrets.toml
///   - PC  (swe) at zee-cloud:8770          -- same peer_token (shared)
///   - Observer at <Mac>:8772               -- observer_token from secrets.toml
final class AppSettings: ObservableObject {
    @Published var macHost: String {
        didSet { UserDefaults.standard.set(macHost, forKey: Keys.macHost) }
    }
    @Published var macPort: Int {
        didSet { UserDefaults.standard.set(macPort, forKey: Keys.macPort) }
    }
    @Published var pcHost: String {
        didSet { UserDefaults.standard.set(pcHost, forKey: Keys.pcHost) }
    }
    @Published var pcPort: Int {
        didSet { UserDefaults.standard.set(pcPort, forKey: Keys.pcPort) }
    }
    @Published var observerHost: String {
        didSet { UserDefaults.standard.set(observerHost, forKey: Keys.observerHost) }
    }
    @Published var observerPort: Int {
        didSet { UserDefaults.standard.set(observerPort, forKey: Keys.observerPort) }
    }

    @Published var peerToken: String {
        didSet { Keychain.save(Keys.peerToken, value: peerToken) }
    }
    @Published var observerToken: String {
        didSet { Keychain.save(Keys.observerToken, value: observerToken) }
    }

    init() {
        let d = UserDefaults.standard
        self.macHost = d.string(forKey: Keys.macHost) ?? "rishis-macbook-pro"
        self.macPort = d.object(forKey: Keys.macPort) as? Int ?? 8770
        self.pcHost = d.string(forKey: Keys.pcHost) ?? "zee-cloud"
        self.pcPort = d.object(forKey: Keys.pcPort) as? Int ?? 8770
        self.observerHost = d.string(forKey: Keys.observerHost) ?? "rishis-macbook-pro"
        self.observerPort = d.object(forKey: Keys.observerPort) as? Int ?? 8772
        // Tokens: prefer Keychain, but allow env-var seed for sim verification
        // (e.g. `xcrun simctl launch ... --env ZEECHAT_PEER_TOKEN=...`).
        // The env value is persisted into Keychain so a relaunch without
        // the env still works.
        let env = ProcessInfo.processInfo.environment
        if let p = env["ZEECHAT_PEER_TOKEN"], !p.isEmpty {
            Keychain.save(Keys.peerToken, value: p)
            self.peerToken = p
        } else {
            self.peerToken = Keychain.load(Keys.peerToken) ?? ""
        }
        if let o = env["ZEECHAT_OBSERVER_TOKEN"], !o.isEmpty {
            Keychain.save(Keys.observerToken, value: o)
            self.observerToken = o
        } else {
            self.observerToken = Keychain.load(Keys.observerToken) ?? ""
        }
    }

    func peerBaseURL(for role: ContactRole) -> URL? {
        switch role {
        case .pm: return URL(string: "http://\(macHost):\(macPort)")
        case .swe: return URL(string: "http://\(pcHost):\(pcPort)")
        }
    }

    func observerBaseURL() -> URL? {
        URL(string: "http://\(observerHost):\(observerPort)")
    }

    var isConfigured: Bool {
        !peerToken.isEmpty && !observerToken.isEmpty
    }

    private enum Keys {
        static let macHost = "zeechat.macHost"
        static let macPort = "zeechat.macPort"
        static let pcHost = "zeechat.pcHost"
        static let pcPort = "zeechat.pcPort"
        static let observerHost = "zeechat.observerHost"
        static let observerPort = "zeechat.observerPort"
        static let peerToken = "zeechat.peerToken"
        static let observerToken = "zeechat.observerToken"
    }
}
