import XCTest
import Yams
import CSQLite
@testable import Piper

final class PiperTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("piper-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    func testGestureRejectsTypingAndHeldShift() {
        var gesture = ShiftGesture()
        XCTAssertFalse(gesture.shift(down: true, time: 0, otherModifier: false))
        XCTAssertFalse(gesture.shift(down: false, time: 0.08, otherModifier: false))
        XCTAssertFalse(gesture.shift(down: true, time: 0.15, otherModifier: false))
        XCTAssertTrue(gesture.shift(down: false, time: 0.20, otherModifier: false))
        XCTAssertFalse(gesture.shift(down: true, time: 1, otherModifier: false))
        gesture.cancel()
        XCTAssertFalse(gesture.shift(down: false, time: 1.1, otherModifier: false))
        XCTAssertFalse(gesture.shift(down: true, time: 2, otherModifier: false))
        XCTAssertFalse(gesture.shift(down: false, time: 3, otherModifier: false))
        XCTAssertFalse(gesture.shift(down: true, time: 3.1, otherModifier: true))
    }

    @MainActor func testPersistenceMergeUndoAndExactText() throws {
        let url = folder.appendingPathComponent("notes.sqlite")
        let store = AppStore(url: url)
        let text = "  αβ\n\t`code`\n"
        XCTAssertTrue(store.add(text, interpretSection: false))
        XCTAssertTrue(store.add("second", source: "TextEdit"))
        store.selection = Set(store.notes.map(\.id))
        XCTAssertEqual(store.copyText(asList: true), "1.   αβ\n   \t`code`\n   \n\n2. second")
        store.merge()
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.notes[0].text, text + "\n\nsecond")
        store.undo()
        XCTAssertEqual(store.notes.count, 2)
        XCTAssertEqual(AppStore(url: url).notes[0].text, text)
        XCTAssertTrue(store.add("# Research"))
        XCTAssertEqual(AppStore(url: url).activeSection, "Research")
        XCTAssertTrue(store.add("# literal heading", to: "Inbox", interpretSection: false))
        XCTAssertEqual(store.notes.last?.text, "# literal heading")
    }

    @MainActor func testUnsupportedDatabaseDoesNotOverwrite() throws {
        let url = folder.appendingPathComponent("future.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        sqlite3_exec(db, "CREATE TABLE state(id INTEGER PRIMARY KEY, version INTEGER, data BLOB); INSERT INTO state VALUES(1,99,'future');", nil, nil, nil)
        sqlite3_close(db)
        let before = try Data(contentsOf: url)
        let store = AppStore(url: url)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.add("overwrite"))
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testFrontmatterTrustAndUnknownFields() {
        let raw = "---\ntype: Custom\ntitle: Test\nverified: {by: 'human:ravi', at: '2026-01-01T00:00:00Z'}\nstale_after: '2020-01-01T00:00:00Z'\ncustom: [a, b]\n---\nBody\n"
        let doc = WikiDocument.parse(raw, path: "topics/test.md")
        XCTAssertNil(doc.problem)
        XCTAssertEqual(doc.verification, "Human-reviewed")
        XCTAssertTrue(doc.isStale)
        XCTAssertEqual(doc.body, "Body\n")
        XCTAssertNotNil(doc.metadata["custom"])
        XCTAssertNotNil(WikiDocument.parse("---\ntitle: [broken\n---\ntext", path: "bad.md").problem)
    }

    private func wiki() throws -> WikiRepository {
        try Data("---\nokf_version: \"0.2\"\n---\n\n# Wiki\n".utf8).write(to: folder.appendingPathComponent("index.md"))
        return WikiRepository(root: folder)
    }

    func testExportPreservesOriginalsAndIsIdempotent() throws {
        let repo = try wiki()
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("topics"), withIntermediateDirectories: true)
        let original = "---\ntype: Topic\ntitle: Existing\nverified: [{by: 'human:ravi', at: '2026-01-01T00:00:00Z'}]\ncustom: keep\n---\nKeep exactly.\n"
        let originalURL = folder.appendingPathComponent("topics/existing.md")
        try Data(original.utf8).write(to: originalURL)
        let note = Note(text: "  exact\n# heading\n---\n你好", section: "Inbox")
        let doc = try repo.export(notes: [note], title: "Title: \"quoted\"", description: "A multiline\ndescription", destination: "sources", sourceURL: "https://example.com/page")
        XCTAssertEqual(doc.metadata["title"] as? String, "Title: \"quoted\"")
        XCTAssertEqual(doc.metadata["status"] as? String, "draft")
        XCTAssertNil(doc.metadata["verified"])
        XCTAssertTrue(doc.body.contains(note.text))
        XCTAssertEqual(doc.sources[0]["resource"] as? String, "https://example.com/page")
        XCTAssertEqual(try String(contentsOf: originalURL), original)
        let again = try repo.export(notes: [note], title: "Other title", description: "Other", destination: "topics", sourceURL: "")
        XCTAssertEqual(doc.id, again.id)
        let log = try String(contentsOf: folder.appendingPathComponent("log.md"))
        XCTAssertEqual(log.components(separatedBy: "**Creation**").count, 2)
        let index = try String(contentsOf: folder.appendingPathComponent("index.md"))
        XCTAssertTrue(index.contains("/sources/"))
        XCTAssertTrue(index.contains("/topics/existing.md"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".raw").path))
    }

    func testExportRejectsTraversalAndEscapingSymlinks() throws {
        let repo = try wiki()
        XCTAssertThrowsError(try repo.containedURL("../../outside.md"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("sources"), withDestinationURL: folder.deletingLastPathComponent())
        XCTAssertThrowsError(try repo.export(notes: [Note(text: "note", section: "Inbox")], title: "Title", description: "Description", destination: "sources", sourceURL: ""))
    }

    func testScanSkipsHiddenAndReportsMalformedConcepts() throws {
        let repo = try wiki()
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".raw"), withIntermediateDirectories: true)
        try Data("raw".utf8).write(to: folder.appendingPathComponent(".raw/original.md"))
        try Data("invalid".utf8).write(to: folder.appendingPathComponent("broken.md"))
        let scan = try repo.scan()
        XCTAssertEqual(scan.documents.count, 1)
        XCTAssertEqual(scan.problems.count, 1)
        XCTAssertThrowsError(try repo.export(notes: [Note(text: "text", section: "Inbox")], title: "T", description: "D", destination: "sources", sourceURL: ""))
    }

    func testExportCollisionAndInvalidSource() throws {
        let repo = try wiki()
        let first = try repo.export(notes: [Note(text: "one", section: "Inbox")], title: "Repeated", description: "D", destination: "sources", sourceURL: "")
        let second = try repo.export(notes: [Note(text: "two", section: "Inbox")], title: "Repeated", description: "D", destination: "sources", sourceURL: "")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(second.id, "sources/repeated-2.md")
        XCTAssertThrowsError(try repo.export(notes: [Note(text: "bad", section: "Inbox")], title: "Title", description: "D", destination: "sources", sourceURL: "javascript:alert(1)"))
    }
    func testRetryRepairsAnExportAfterIndexFailure() throws {
        let repo = try wiki()
        let sources = folder.appendingPathComponent("sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let index = sources.appendingPathComponent("index.md")
        try FileManager.default.createSymbolicLink(at: index, withDestinationURL: folder.deletingLastPathComponent().appendingPathComponent("outside.md"))
        let note = Note(text: "preserve this excerpt", section: "Inbox")
        XCTAssertThrowsError(try repo.export(notes: [note], title: "Recovery", description: "D", destination: "sources", sourceURL: ""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sources.appendingPathComponent("recovery.md").path))
        try FileManager.default.removeItem(at: index)
        let repaired = try repo.export(notes: [note], title: "Recovery", description: "D", destination: "sources", sourceURL: "")
        XCTAssertEqual(repaired.id, "sources/recovery.md")
        XCTAssertTrue(try String(contentsOf: index).contains("recovery.md"))
        XCTAssertEqual(try repo.scan().documents.count, 1)
    }

}
