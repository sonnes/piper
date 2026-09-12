import AppKit
import CSQLite
import XCTest
@testable import Piper

@MainActor
final class ReleaseTests: XCTestCase {
    private var folder: URL!
    private var databaseURL: URL { folder.appendingPathComponent("notes.sqlite") }

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("piper-release-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try FileManager.default.removeItem(at: folder) }

    func testFreshAppHasOnlyInboxAndNoSeededContent() {
        let store = AppStore(url: databaseURL)
        let model = AppModel(store: store, wikiPath: folder.appendingPathComponent("Wiki").path)
        XCTAssertEqual(store.sections, ["Inbox"])
        XCTAssertEqual(store.activeSection, "Inbox")
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertTrue(model.documents.isEmpty)
        XCTAssertTrue(model.clipboard.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.wikiPath))
    }

    func testExplicitClipboardCapturePreservesTextAndPasteboard() {
        let pasteboard = NSPasteboard(name: .init("com.piper.release-test." + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let store = AppStore(url: databaseURL)
        let text = "# Literal heading\n  你好 👋🏽\n\tlet x = 1\n"
        pasteboard.setString(text, forType: .string)
        let version = pasteboard.changeCount
        XCTAssertTrue(store.captureClipboard(from: pasteboard))
        XCTAssertEqual(store.notes.first?.text, text)
        XCTAssertEqual(store.notes.first?.sources, ["Clipboard"])
        XCTAssertEqual(store.sections, ["Inbox"])
        XCTAssertEqual(pasteboard.changeCount, version)
        XCTAssertEqual(pasteboard.string(forType: .string), text)
        pasteboard.clearContents()
        XCTAssertFalse(store.captureClipboard(from: pasteboard))
        XCTAssertEqual(store.notes.count, 1)
    }

    func testSelectionRangeUsesUTF16AndRejectsInvalidBounds() {
        let text = "a👋🏽你好\nend"
        XCTAssertEqual(CapturedSelection.substring(text, range: CFRange(location: 1, length: 6)), "👋🏽你好")
        XCTAssertEqual(CapturedSelection.substring(text, range: CFRange(location: 7, length: 4)), "\nend")
        for range in [CFRange(location: -1, length: 1), CFRange(location: 0, length: 0), CFRange(location: 0, length: -1), CFRange(location: 11, length: 1), CFRange(location: 1, length: Int.max), CFRange(location: Int.max, length: 1)] {
            XCTAssertNil(CapturedSelection.substring(text, range: range))
        }
    }

    func testCaptureRecordsOnlyWebSourceURLs() {
        let store = AppStore(url: databaseURL)
        XCTAssertTrue(store.add("selected text", source: "Safari", sourceURL: "https://example.com/article", interpretSection: false))
        XCTAssertEqual(store.notes.last?.sourceURLs, ["https://example.com/article"])
        XCTAssertTrue(store.add("https://example.com/article", sourceURL: "https://example.com/article", interpretSection: false))
        XCTAssertEqual(store.notes.last?.sourceURLs, ["https://example.com/article"])
        XCTAssertTrue(store.add("local text", sourceURL: "file:///private/document.txt", interpretSection: false))
        XCTAssertEqual(store.notes.last?.sourceURLs, [])
    }

    func testSectionsRejectInvalidNamesAndOrphanCaptures() {
        let store = AppStore(url: databaseURL)
        XCTAssertFalse(store.chooseSection(" \n "))
        XCTAssertFalse(store.chooseSection("First\nSecond"))
        XCTAssertFalse(store.chooseSection(String(repeating: "a", count: 81)))
        XCTAssertTrue(store.chooseSection(" Research "))
        XCTAssertTrue(store.chooseSection("research"))
        XCTAssertEqual(store.sections, ["Inbox", "Research"])
        XCTAssertFalse(store.add("orphan", to: "Missing"))
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertTrue(store.add("saved"))
        store.selection = [store.notes[0].id]
        store.move(to: "Missing")
        XCTAssertEqual(store.notes[0].section, "Research")
        store.activeSection = "Missing"
        XCTAssertEqual(store.activeSection, "Research")
    }

    func testSectionNavigationAndUnchangedEditPreserveUndo() {
        let store = AppStore(url: databaseURL)
        XCTAssertTrue(store.chooseSection("Research"))
        XCTAssertTrue(store.add("keep"))
        XCTAssertTrue(store.update(store.notes[0].id, text: "keep"))
        XCTAssertTrue(store.chooseSection("Inbox"))
        store.undo()
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertEqual(store.sections, ["Inbox", "Research"])
        XCTAssertEqual(store.activeSection, "Inbox")
    }

    func testConcurrentFirstSaveCannotReplaceAnotherInstance() {
        let first = AppStore(url: databaseURL)
        let second = AppStore(url: databaseURL)
        XCTAssertTrue(first.add("first writer"))
        XCTAssertFalse(second.add("stale writer"))
        XCTAssertTrue(second.notes.isEmpty)
        XCTAssertFalse(second.canUndo)
        XCTAssertNotNil(second.errorMessage)
        XCTAssertEqual(AppStore(url: databaseURL).notes.map(\.text), ["first writer"])
    }

    func testStaleUpdateAndUndoLeaveSavedNotesIntact() {
        let first = AppStore(url: databaseURL)
        XCTAssertTrue(first.add("baseline"))
        let second = AppStore(url: databaseURL)
        XCTAssertTrue(second.add("newer note"))
        XCTAssertFalse(first.update(first.notes[0].id, text: "stale edit"))
        first.undo()
        XCTAssertEqual(first.notes.map(\.text), ["baseline"])
        XCTAssertEqual(AppStore(url: databaseURL).notes.map(\.text), ["baseline", "newer note"])
    }

    func testLockedDatabaseRetainsNotesAndUndoUntilRetry() throws {
        let store = AppStore(url: databaseURL)
        XCTAssertTrue(store.add("saved"))
        var lock: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &lock), SQLITE_OK)
        defer { sqlite3_close(lock) }
        XCTAssertEqual(sqlite3_exec(lock, "BEGIN IMMEDIATE", nil, nil, nil), SQLITE_OK)
        XCTAssertFalse(store.add("retry me"))
        XCTAssertEqual(store.notes.map(\.text), ["saved"])
        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(sqlite3_exec(lock, "ROLLBACK", nil, nil, nil), SQLITE_OK)
        XCTAssertTrue(store.add("retry me"))
        XCTAssertEqual(AppStore(url: databaseURL).notes.map(\.text), ["saved", "retry me"])
        store.undo()
        XCTAssertEqual(store.notes.map(\.text), ["saved"])
    }

    func testInvalidStoredSectionsBlockWrites() throws {
        let database = try Database(url: databaseURL)
        _ = try database.load()
        try database.save(SavedState(notes: [Note(text: "preserve", section: "Missing")]))
        let before = try Data(contentsOf: databaseURL)
        let store = AppStore(url: databaseURL)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.add("overwrite"))
        XCTAssertEqual(try Data(contentsOf: databaseURL), before)
    }

    func testCaptureEditorConflictPreservesDraft() {
        let store = AppStore(url: databaseURL)
        XCTAssertTrue(store.add("original"))
        let model = AppModel(store: store, wikiPath: folder.path)
        let first = model.editCapture(store.notes[0])
        let second = model.editCapture(store.notes[0])
        first.text = "saved edit"
        XCTAssertTrue(model.saveCaptureEdit(first))
        XCTAssertFalse(first.hasChanges)
        second.text = "unsaved edit"
        XCTAssertFalse(model.saveCaptureEdit(second))
        XCTAssertEqual(second.text, "unsaved edit")
        XCTAssertTrue(second.hasChanges)
        XCTAssertEqual(store.notes[0].text, "saved edit")
        store.selection = [store.notes[0].id]
        store.deleteSelection()
        XCTAssertFalse(model.saveCaptureEdit(second))
        XCTAssertTrue(model.captureEdits[second.id] === second)
    }

    func testCreateWikiStartsEmptyAndSupportsRealExport() throws {
        let root = folder.appendingPathComponent("Wiki")
        let repository = WikiRepository(root: root)
        try repository.create()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["index.md"])
        XCTAssertTrue(try repository.scan().documents.isEmpty)
        XCTAssertThrowsError(try repository.create())
        let note = Note(text: "A captured thought", section: "Inbox")
        let document = try repository.export(notes: [note], title: "First capture", description: "An exported note", destination: "sources", sourceURL: "")
        XCTAssertTrue(document.body.contains(note.text))
        XCTAssertEqual(document.metadata["status"] as? String, "draft")
        XCTAssertNil(document.metadata["verified"])
        XCTAssertTrue(try repository.scan().documents.contains { $0.id == document.id })
    }

    func testCreateWikiRefusesAnExistingFolderWithUserFiles() throws {
        let existing = folder.appendingPathComponent("personal.md")
        try Data("keep exactly\n".utf8).write(to: existing)
        XCTAssertThrowsError(try WikiRepository(root: folder).create())
        XCTAssertEqual(try String(contentsOf: existing), "keep exactly\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.md").path))
    }
}
