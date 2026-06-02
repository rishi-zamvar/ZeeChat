import Foundation

/// On-disk persistence for chat threads. Survives launches, app kill,
/// and reinstalls (Documents dir is iCloud-excluded but device-local).
///
/// One JSON file per contact (`thread-pm.json`, `thread-swe.json`) so a
/// corrupt write only loses one side. Atomic write via temp + rename
/// keeps reads consistent if the app is killed mid-save.
struct ThreadStore {
    static let shared = ThreadStore()

    private let dir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask).first
                   ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.dir = docs.appendingPathComponent("threads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
    }

    private func url(for role: ContactRole) -> URL {
        dir.appendingPathComponent("thread-\(role.rawValue).json")
    }

    func load(for role: ContactRole) -> [DispatchMessage] {
        let path = url(for: role)
        guard let data = try? Data(contentsOf: path) else { return [] }
        return (try? JSONDecoder().decode([DispatchMessage].self, from: data)) ?? []
    }

    func save(_ messages: [DispatchMessage], for role: ContactRole) {
        let path = url(for: role)
        guard let data = try? JSONEncoder().encode(messages) else { return }
        let tmp = path.appendingPathExtension("tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.removeItem(at: path)
            try FileManager.default.moveItem(at: tmp, to: path)
        } catch {
            // Silent — disk-full or sandbox issue. Next save will retry.
        }
    }

    /// Per-role cursor + per-role read-watermark. Both small enough to
    /// store in UserDefaults; saving them per-thread keeps things simple.
    func loadCursor(for role: ContactRole) -> String? {
        UserDefaults.standard.string(forKey: "zeechat.cursor.\(role.rawValue)")
    }

    func saveCursor(_ cursor: String?, for role: ContactRole) {
        UserDefaults.standard.set(cursor, forKey: "zeechat.cursor.\(role.rawValue)")
    }

    /// Watermark = id of the last message the user has actually viewed.
    /// Anything created_at > watermark counts as unread for badge math.
    func loadReadWatermark(for role: ContactRole) -> String? {
        UserDefaults.standard.string(forKey: "zeechat.readwm.\(role.rawValue)")
    }

    func saveReadWatermark(_ id: String, for role: ContactRole) {
        UserDefaults.standard.set(id, forKey: "zeechat.readwm.\(role.rawValue)")
    }
}
