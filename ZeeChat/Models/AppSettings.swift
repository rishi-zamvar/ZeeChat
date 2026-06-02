import Foundation

/// Persistent per-daemon endpoint + token. Stored in UserDefaults for the
/// host/port (non-secret) and Keychain for the bearer tokens.
///
/// Tokens are per-daemon — the iPhone-facing `/api/v1/chat/*` shim uses
/// its own bearer (chat_token) that is distinct from the inter-daemon
/// peer_token. Mac and PC each issue their own chat_token; the phone
/// holds both so it can talk to either side.
///
/// Daemons:
///   - Mac (pm) at rishis-macbook-pro:8770 — macChatToken for /api/v1/chat
///   - PC  (swe) at zee-cloud:8770         — pcChatToken  for /api/v1/chat
///   - Observer at <Mac>:8772              — observerToken (read-only diag)
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

    /// Legacy: original peer plane bearer. Retained so existing keychain
    /// entries aren't orphaned, but new sends go through chat tokens below.
    @Published var peerToken: String {
        didSet { Keychain.save(Keys.peerToken, value: peerToken) }
    }
    @Published var observerToken: String {
        didSet { Keychain.save(Keys.observerToken, value: observerToken) }
    }
    /// PC daemon `/api/v1/chat/*` bearer. Distinct trust domain from peerToken.
    @Published var pcChatToken: String {
        didSet { Keychain.save(Keys.pcChatToken, value: pcChatToken) }
    }
    /// Mac daemon `/api/v1/chat/*` bearer. Lands when Mac-side shim ships.
    @Published var macChatToken: String {
        didSet { Keychain.save(Keys.macChatToken, value: macChatToken) }
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
        if let pc = env["ZEECHAT_PC_CHAT_TOKEN"], !pc.isEmpty {
            Keychain.save(Keys.pcChatToken, value: pc)
            self.pcChatToken = pc
        } else {
            self.pcChatToken = Keychain.load(Keys.pcChatToken) ?? ""
        }
        if let mac = env["ZEECHAT_MAC_CHAT_TOKEN"], !mac.isEmpty {
            Keychain.save(Keys.macChatToken, value: mac)
            self.macChatToken = mac
        } else {
            self.macChatToken = Keychain.load(Keys.macChatToken) ?? ""
        }
    }

    func chatToken(for role: ContactRole) -> String {
        switch role {
        case .pm: return macChatToken
        case .swe: return pcChatToken
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

    /// Configured = at least one chat token present so we can reach one daemon.
    /// Mac-side shim is optional (lands later); PC-side is the primary path.
    var isConfigured: Bool {
        !pcChatToken.isEmpty || !macChatToken.isEmpty
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
        static let pcChatToken = "zeechat.pcChatToken"
        static let macChatToken = "zeechat.macChatToken"
    }
}
