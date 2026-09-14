import AppKit
import CSQLite
import XCTest
import Captures

@MainActor
final class CaptureStoreTests: XCTestCase {

    // MARK: - Properties

    private var folder: URL!

    // MARK: - Setup

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("captures-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    private func url(_ name: String = "notes.sqlite") -> URL { folder.appendingPathComponent(name) }

    // MARK: - Tests

    func testPersistenceMergeUndoAndExactText() throws {
        let url = url()
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

    func testUnsupportedDatabaseDoesNotOverwrite() throws {
        let url = url("future.sqlite")
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

    func testInvalidRecordsStopEveryChange() throws {
        let url = url("invalid.sqlite")
        let broken = Data(#"{"notes":[],"sections":["Inbox","Inbox"],"activeSection":"Inbox"}"#.utf8)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        sqlite3_exec(db, "CREATE TABLE state(id INTEGER PRIMARY KEY, version INTEGER, data BLOB)", nil, nil, nil)
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "INSERT INTO state VALUES(1,1,?)", -1, &statement, nil), SQLITE_OK)
        broken.withUnsafeBytes { bytes in
            _ = sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
        sqlite3_finalize(statement)
        sqlite3_close(db)
        let store = CaptureStore(url: url)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.add("overwrite", interpretSection: false))
        XCTAssertTrue(store.notes.isEmpty)
    }

    func testUndoRestoresDeletedNotesAndDropsGoneSelection() {
        let store = CaptureStore(url: url())
        XCTAssertTrue(store.add("first", interpretSection: false))
        XCTAssertTrue(store.add("second", interpretSection: false))
        store.selection = Set(store.notes.map(\.id))
        store.deleteSelection()
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertTrue(store.selection.isEmpty)
        XCTAssertTrue(store.canUndo)
        store.undo()
        XCTAssertEqual(store.notes.map(\.text), ["first", "second"])
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(store.status, "Last note change undone")
        XCTAssertEqual(CaptureStore(url: url()).notes.count, 2)

        XCTAssertTrue(store.add("third", interpretSection: false))
        store.selection = [store.notes[2].id]
        store.undo()
        XCTAssertEqual(store.notes.count, 2)
        XCTAssertTrue(store.selection.isEmpty)
    }

    func testOnlyOneUndoStepIsKept() {
        let store = CaptureStore(url: url())
        XCTAssertTrue(store.add("first", interpretSection: false))
        XCTAssertTrue(store.add("second", interpretSection: false))
        store.undo()
        XCTAssertEqual(store.notes.map(\.text), ["first"])
        XCTAssertFalse(store.canUndo)
        store.undo()
        XCTAssertEqual(store.notes.map(\.text), ["first"])
    }

    func testChangingTheActiveSectionSavesWithoutAnUndoStep() {
        let store = CaptureStore(url: url())
        XCTAssertTrue(store.chooseSection("Research"))
        XCTAssertEqual(store.sections, ["Inbox", "Research"])
        XCTAssertEqual(store.activeSection, "Research")
        store.undo()
        XCTAssertEqual(store.sections, ["Inbox"])
        XCTAssertEqual(store.activeSection, "Inbox")
        XCTAssertFalse(store.canUndo)

        XCTAssertTrue(store.chooseSection("Research"))
        store.undo()
        XCTAssertFalse(store.canUndo)
        XCTAssertTrue(store.chooseSection("inbox"))
        XCTAssertEqual(store.activeSection, "Inbox")
        XCTAssertFalse(store.canUndo)
    }

    func testTheActiveSectionSurvivesAnUndo() {
        let store = CaptureStore(url: url())
        XCTAssertTrue(store.chooseSection("Research"))
        XCTAssertTrue(store.add("a note", interpretSection: false))
        store.selection = Set(store.notes.map(\.id))
        store.deleteSelection()
        store.activeSection = "Inbox"
        XCTAssertTrue(store.canUndo)
        store.undo()
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.activeSection, "Inbox")
        XCTAssertEqual(CaptureStore(url: url()).activeSection, "Inbox")
    }

    func testASecondInstanceCannotOverwriteTheFirst() {
        let url = url("shared.sqlite")
        let first = CaptureStore(url: url)
        let second = CaptureStore(url: url)
        XCTAssertNil(first.errorMessage)
        XCTAssertNil(second.errorMessage)
        XCTAssertTrue(first.add("from the first instance", interpretSection: false))
        XCTAssertFalse(second.add("from the second instance", interpretSection: false))
        XCTAssertTrue(second.notes.isEmpty)
        XCTAssertEqual(second.errorMessage, "Notes changed in another Piper instance. Restart Piper before saving. Your existing notes remain unchanged.")
        XCTAssertEqual(CaptureStore(url: url).notes.map(\.text), ["from the first instance"])

        let third = CaptureStore(url: url)
        let fourth = CaptureStore(url: url)
        XCTAssertTrue(third.add("third", interpretSection: false))
        XCTAssertFalse(fourth.add("fourth", interpretSection: false))
        XCTAssertNotNil(fourth.errorMessage)
        XCTAssertEqual(CaptureStore(url: url).notes.map(\.text), ["from the first instance", "third"])
    }

    func testAnUnavailableDatabaseRejectsEveryChange() {
        let store = CaptureStore(url: folder)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.add("a note", interpretSection: false))
        XCTAssertFalse(store.chooseSection("Research"))
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertFalse(store.canUndo)
        store.undo()
        XCTAssertTrue(store.notes.isEmpty)
    }

    func testUpdateRejectsAStaleEditAndAMissingNote() {
        let store = CaptureStore(url: url())
        XCTAssertTrue(store.add("original", interpretSection: false))
        let id = store.notes[0].id
        XCTAssertFalse(store.update(id, text: "   ", originalText: "original"))
        XCTAssertFalse(store.update(UUID(), text: "text"))
        XCTAssertEqual(store.errorMessage, "This note was removed. Copy your changes into a new note.")
        XCTAssertFalse(store.update(id, text: "changed", originalText: "something else"))
        XCTAssertEqual(store.errorMessage, "This note changed in another editor. Copy your changes before reopening the note.")
        XCTAssertEqual(store.notes[0].text, "original")
        XCTAssertTrue(store.update(id, text: "original"))
        XCTAssertTrue(store.update(id, text: "changed", originalText: "original"))
        XCTAssertEqual(store.notes[0].text, "changed")
        XCTAssertTrue(store.update(id, text: "changed", sourceURL: ""))
        XCTAssertTrue(store.notes[0].sourceURLs.isEmpty)
    }

    func testAddKeepsOnlyWebSourceURLs() {
        let store = CaptureStore(url: url())
        XCTAssertTrue(store.add("https://example.com/page", interpretSection: false))
        XCTAssertEqual(store.notes[0].sourceURLs, ["https://example.com/page"])
        XCTAssertTrue(store.add("plain text", sourceURL: "javascript:alert(1)", interpretSection: false))
        XCTAssertTrue(store.notes[1].sourceURLs.isEmpty)
        XCTAssertFalse(store.add("   \n\t"))
        XCTAssertFalse(store.add("# "))
        XCTAssertFalse(store.add("a note", to: "Missing", interpretSection: false))
        XCTAssertEqual(store.errorMessage, "This section no longer exists. Choose another section.")
    }

    func testSectionNamesAreLimitedToOneShortLine() {
        let store = CaptureStore(url: url())
        XCTAssertFalse(store.chooseSection("  "))
        XCTAssertFalse(store.chooseSection("two\nlines"))
        XCTAssertFalse(store.chooseSection(String(repeating: "x", count: 81)))
        XCTAssertEqual(store.errorMessage, "Use a section name with 1 to 80 characters on one line.")
        XCTAssertEqual(store.sections, ["Inbox"])
        XCTAssertTrue(store.chooseSection(String(repeating: "x", count: 80)))
        XCTAssertEqual(store.sections.count, 2)
    }

    func testSelectionMovesCompletesAndSearches() {
        let store = CaptureStore(url: url())
        XCTAssertTrue(store.chooseSection("Research"))
        XCTAssertTrue(store.add("alpha", to: "Inbox", interpretSection: false))
        XCTAssertTrue(store.add("beta", to: "Inbox", interpretSection: false))
        let ids = store.notes.map(\.id)
        store.toggleSelection(ids[0])
        store.toggleSelection(ids[1])
        XCTAssertEqual(store.selectedNotes.map(\.text), ["alpha", "beta"])
        store.toggleSelection(ids[1])
        XCTAssertEqual(store.selectedNotes.map(\.text), ["alpha"])
        store.toggleSelection(ids[1])

        store.completeSelection()
        XCTAssertTrue(store.notes.allSatisfy(\.isDone))
        store.completeSelection()
        XCTAssertFalse(store.notes.contains(where: \.isDone))
        store.toggleDone(ids[0])
        XCTAssertTrue(store.notes[0].isDone)

        store.move(to: "Research")
        XCTAssertEqual(Set(store.notes.map(\.section)), ["Research"])
        store.move(to: "Missing")
        XCTAssertEqual(Set(store.notes.map(\.section)), ["Research"])

        store.query = "alp"
        XCTAssertEqual(store.visibleNotes(in: "Research").map(\.text), ["alpha"])
        store.query = ""
        XCTAssertEqual(store.visibleNotes(in: "Research").count, 2)
        XCTAssertEqual(store.copyText(asList: false), "alpha\n\nbeta")
    }

    func testMergeNeedsMoreThanOneNote() {
        let store = CaptureStore(url: url())
        XCTAssertTrue(store.add("only", source: "Mail", interpretSection: false))
        store.selection = Set(store.notes.map(\.id))
        store.merge()
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.status, "Saved to Inbox")
        XCTAssertTrue(store.add("second", source: "Safari", interpretSection: false))
        store.selection = Set(store.notes.map(\.id))
        store.merge()
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.notes[0].sources, ["Mail", "Safari"])
        XCTAssertEqual(store.status, "Notes merged · Undo available")
    }

    func testCaptureClipboardSavesTheTextAsIs() {
        let store = CaptureStore(url: url())
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.piper.test." + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        XCTAssertFalse(store.captureClipboard(from: pasteboard))
        XCTAssertEqual(store.status, "The clipboard has no text")
        pasteboard.clearContents()
        pasteboard.setString("# Not a section", forType: .string)
        XCTAssertTrue(store.captureClipboard(from: pasteboard))
        XCTAssertEqual(store.notes[0].text, "# Not a section")
        XCTAssertEqual(store.notes[0].sources, ["Clipboard"])
        XCTAssertEqual(store.sections, ["Inbox"])
    }
}
