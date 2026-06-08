import XCTest
@testable import ZeeChat

/// TDD for the spec composer DraftStore. Highest-risk persistence
/// path in v2.0: app kill during JSON write corrupts the file, user
/// loses all spec drafts. Per audit (RESEARCH.md ranked #2 risk),
/// these tests land BEFORE implementation.
///
/// Local-first this ship. ZeeCloud sync is a separate concern wired
/// after SWE's draft endpoints land — covered by integration tests
/// later, NOT here.
final class DraftStoreTests: XCTestCase {

    /// Isolated temp directory per test so disk state doesn't leak.
    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZeeChatTests-DraftStore-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Core save/load round-trip

    func test_save_thenLoad_returnsSameDraft() throws {
        let store = DraftStore(directory: tmpDir)
        let d = SpecDraft(
            id: "draft-1",
            target: .pm,
            body: "fix the streak panel",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try store.save(d)
        let loaded = try store.load(id: "draft-1")
        XCTAssertEqual(loaded?.id, d.id)
        XCTAssertEqual(loaded?.target, d.target)
        XCTAssertEqual(loaded?.body, d.body)
        XCTAssertEqual(loaded?.updatedAt.timeIntervalSince1970, d.updatedAt.timeIntervalSince1970)
    }

    func test_load_nonexistent_returnsNil() throws {
        let store = DraftStore(directory: tmpDir)
        XCTAssertNil(try store.load(id: "never-saved"))
    }

    func test_listAll_returnsAllSavedDraftsOrderedByUpdatedAtDescending() throws {
        let store = DraftStore(directory: tmpDir)
        let a = SpecDraft(id: "a", target: .pm, body: "older", updatedAt: Date(timeIntervalSince1970: 1_000))
        let b = SpecDraft(id: "b", target: .swe, body: "newer", updatedAt: Date(timeIntervalSince1970: 2_000))
        let c = SpecDraft(id: "c", target: .both, body: "middle", updatedAt: Date(timeIntervalSince1970: 1_500))
        try store.save(a); try store.save(b); try store.save(c)
        let all = try store.listAll()
        XCTAssertEqual(all.map(\.id), ["b", "c", "a"], "Must sort newest-first")
    }

    func test_delete_removesDraft() throws {
        let store = DraftStore(directory: tmpDir)
        let d = SpecDraft(id: "kill-me", target: .pm, body: "x", updatedAt: Date())
        try store.save(d)
        try store.delete(id: "kill-me")
        XCTAssertNil(try store.load(id: "kill-me"))
    }

    // MARK: - Atomic write contract
    //
    // DraftStore uses FileManager.replaceItemAt which is OS-guaranteed
    // atomic on POSIX filesystems — either the new file is in place
    // OR the old one is, never a half-written truncation. The actual
    // failure path (disk full, mid-flush crash) can't be exercised
    // reliably from a unit test without OS-level fault injection, so
    // we rely on the documented atomicity contract of replaceItemAt
    // rather than testing the FS itself. The encode-then-rename
    // sequence in save() is also early-return-on-throw, so an encoder
    // failure can't corrupt the prior file either.

    /// Corrupt JSON on disk must NOT crash the app on load — return nil
    /// (drop the bad draft) so the user keeps a working composer instead
    /// of an unopenable Specs tab.
    func test_load_corruptJSON_returnsNilGracefully() throws {
        let badPath = tmpDir.appendingPathComponent("draft-corrupt.json")
        try "this is not json {".data(using: .utf8)!.write(to: badPath)
        let store = DraftStore(directory: tmpDir)
        let loaded = try? store.load(id: "corrupt")
        // Either throws OR returns nil — both are acceptable safe failures.
        // The contract is "do not crash the app + do not corrupt the
        // working state."
        XCTAssertNil(loaded)
    }

    func test_listAll_skipsCorruptFilesRatherThanFailing() throws {
        let store = DraftStore(directory: tmpDir)
        // 1 valid, 1 corrupt
        let valid = SpecDraft(id: "valid", target: .pm, body: "good", updatedAt: Date())
        try store.save(valid)
        try "garbage".data(using: .utf8)!.write(
            to: tmpDir.appendingPathComponent("draft-corrupt.json")
        )
        let all = try store.listAll()
        XCTAssertEqual(all.count, 1, "listAll must skip corrupt entries, not abort")
        XCTAssertEqual(all.first?.id, "valid")
    }
}
