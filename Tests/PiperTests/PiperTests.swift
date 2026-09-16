import XCTest
import Yams
import CSQLite
@testable import Piper
import PiperCore
import Captures
import CapturesDatabase
import Vault

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
        let store = CaptureStore(url: url)
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
        XCTAssertEqual(CaptureStore(url: url).notes[0].text, text)
        XCTAssertTrue(store.add("# Research"))
        XCTAssertEqual(CaptureStore(url: url).activeSection, "Research")
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
        let store = CaptureStore(url: url)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.add("overwrite"))
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    // MARK: Frontmatter is optional

    func testFrontmatterIsReadWhenPresentAndAbsenceIsNotAProblem() {
        let raw = "---\ntype: Custom\ntitle: Test\ncustom: [a, b]\n---\nBody\n"
        let doc = makeFile(raw, path: "topics/test.md")
        XCTAssertNil(doc.problem)
        XCTAssertEqual(doc.title, "Test")
        XCTAssertEqual(doc.body, "Body\n")
        XCTAssertNotNil(doc.metadata["custom"])

        // The headline change: a plain file is a file, not a problem.
        let plain = makeFile("Just text, no block.\n", path: "notes.md")
        XCTAssertNil(plain.problem)
        XCTAssertTrue(plain.metadata.isEmpty)
        XCTAssertEqual(plain.body, "Just text, no block.\n")
        XCTAssertEqual(plain.title, "notes")

        XCTAssertNotNil(makeFile("---\ntitle: [broken\n---\ntext", path: "bad.md").problem)
    }

    func testAPathThatLeavesTheVaultThrows() throws {
        let vault = Vault(root: folder)
        XCTAssertThrowsError(try vault.containedURL("../../outside.md"))
    }

    // MARK: Saving a body

    func testSavingKeepsFrontmatterAndRefusesAnExternalChange() throws {
        let vault = Vault(root: folder)
        let url = folder.appendingPathComponent("note.md")
        let raw = "---\ntitle: A note\ncustom: keep\n---\n\nOriginal body.\n"
        try Data(raw.utf8).write(to: url)
        let file = try vault.read("note.md")

        let saved = try WikiSave.body("\nA new body.\n", of: file, in: vault)
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(onDisk.hasPrefix("---\ntitle: A note\ncustom: keep\n---\n"), "Frontmatter survives byte for byte")
        XCTAssertTrue(onDisk.contains("A new body."))
        XCTAssertEqual(saved.body, "\nA new body.\n")

        // Another editor writes, so the stale session must refuse.
        try Data("---\ntitle: A note\n---\n\nSomeone else wrote.\n".utf8).write(to: url)
        XCTAssertThrowsError(try WikiSave.body("\nMy edit.\n", of: file, in: vault))
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("Someone else wrote."))
    }
}
