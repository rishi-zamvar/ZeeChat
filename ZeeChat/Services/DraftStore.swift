import Foundation

/// A spec draft staged in the spec composer before dispatch. The user
/// can edit + refine + clone across sessions; persists locally and
/// (in a later ship) syncs to ZeeCloud.
struct SpecDraft: Codable, Equatable, Identifiable {
    let id: String
    var target: SpecTarget
    var body: String
    var updatedAt: Date
}

/// Spec composer target chip. Mirrors `dispatch_to_team(target=...)`
/// semantics — single role or fan-out to both PM + SWE.
enum SpecTarget: String, Codable, Equatable {
    case pm
    case swe
    case both
}

/// Local-first persistence for in-progress specs. One JSON file per
/// draft under the configured directory; atomic write via tmp-then-
/// rename so a crash mid-flush leaves the prior version intact. Bad
/// files are skipped on load rather than crashing the Specs tab.
///
/// ZeeCloud sync (push + pull + conflict resolution) is a separate
/// concern; this store is just the local source of truth.
struct DraftStore {
    /// Directory holding per-draft JSON files. Caller chooses
    /// (production = Documents/drafts/; tests = isolated tmp).
    let directory: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Persist a draft. Atomic: writes to <id>.json.writing then
    /// renames to <id>.json. On any failure (encoding, disk, rename),
    /// throws — leaving any prior version of the file untouched.
    func save(_ draft: SpecDraft) throws {
        try ensureDirectory()
        let dest = path(forId: draft.id)
        let tmp = dest.appendingPathExtension("writing")
        let data = try encoder.encode(draft)
        // If tmp exists (prior crashed write OR test fixture), nuke it
        // first so the write call below doesn't fail with EEXIST. If
        // tmp IS a directory (test fixture corner), the write will
        // throw and the prior dest file is untouched.
        try? FileManager.default.removeItem(at: tmp)
        try data.write(to: tmp, options: .atomic)
        // POSIX rename is atomic — either the new file is in place or
        // the old one is. Use _ = to ignore the return.
        _ = try FileManager.default.replaceItemAt(dest, withItemAt: tmp)
    }

    /// Load by id. Returns nil if file is missing OR unreadable
    /// (corrupt JSON, wrong shape). Never crashes the caller.
    func load(id: String) throws -> SpecDraft? {
        let p = path(forId: id)
        guard FileManager.default.fileExists(atPath: p.path) else { return nil }
        guard let data = try? Data(contentsOf: p) else { return nil }
        return try? decoder.decode(SpecDraft.self, from: data)
    }

    /// All drafts, newest-first by updatedAt. Skips files that fail
    /// to decode rather than aborting — one bad file doesn't break
    /// the Specs tab.
    func listAll() throws -> [SpecDraft] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        let drafts: [SpecDraft] = entries.compactMap { url in
            guard url.lastPathComponent.hasPrefix("draft-"),
                  url.pathExtension == "json"
            else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(SpecDraft.self, from: data)
        }
        return drafts.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Delete a draft. No-op if it doesn't exist.
    func delete(id: String) throws {
        let p = path(forId: id)
        guard FileManager.default.fileExists(atPath: p.path) else { return }
        try FileManager.default.removeItem(at: p)
    }

    // MARK: -

    private func ensureDirectory() throws {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }

    private func path(forId id: String) -> URL {
        directory.appendingPathComponent("draft-\(id).json")
    }
}
