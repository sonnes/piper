import AppKit
import CSQLite
import XCTest
@testable import Piper
import PiperCore
import Captures
import CapturesDatabase
import Vault

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
        let store = CaptureStore(url: databaseURL)
        let model = AppModel(store: store, wikiPath: folder.appendingPathComponent("Wiki").path, preferences: temporaryDefaults())
        XCTAssertEqual(store.sections, ["Inbox"])
        XCTAssertEqual(store.activeSection, "Inbox")
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertTrue(model.library.files.isEmpty)
        XCTAssertTrue(model.clipboard.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.library.wikiPath))
    }

    func testExplicitClipboardCapturePreservesTextAndPasteboard() {
        let pasteboard = NSPasteboard(name: .init("com.piper.release-test." + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let store = CaptureStore(url: databaseURL)
        let model = AppModel(store: store, wikiPath: folder.path, preferences: temporaryDefaults())
        let text = "# Literal heading\n  你好 👋🏽\n\tlet x = 1\n"
        pasteboard.setString(text, forType: .string)
        let version = pasteboard.changeCount
        XCTAssertNotNil(model.captureClipboard(from: pasteboard))
        XCTAssertEqual(store.notes.first?.text, text)
        XCTAssertEqual(store.notes.first?.sources, ["Clipboard"])
        XCTAssertEqual(store.sections, ["Inbox"])
        XCTAssertEqual(pasteboard.changeCount, version)
        XCTAssertEqual(pasteboard.string(forType: .string), text)
        pasteboard.clearContents()
        XCTAssertNil(model.captureClipboard(from: pasteboard))
        XCTAssertEqual(model.messages.last?.text, "The clipboard has no text")
        XCTAssertEqual(store.notes.count, 1)
    }

    func testClipboardCaptureSavesWithoutAnAppDelegate() {
        let pasteboard = NSPasteboard(name: .init("com.piper.model-test." + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let store = CaptureStore(url: databaseURL)
        let model = AppModel(store: store, wikiPath: folder.path, preferences: temporaryDefaults())
        pasteboard.setString("A fictional field note", forType: .string)
        let version = pasteboard.changeCount

        XCTAssertNotNil(model.captureClipboard(from: pasteboard))
        XCTAssertEqual(model.messages.last?.text, "Saved to Inbox")
        XCTAssertEqual(store.notes.first?.text, "A fictional field note")
        XCTAssertEqual(store.notes.first?.section, "Inbox")
        XCTAssertEqual(pasteboard.changeCount, version)
        pasteboard.clearContents()
        XCTAssertNil(model.captureClipboard(from: pasteboard))
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

    func testCaptureRecordsOnlyWebSourceURLs() throws {
        let store = CaptureStore(url: databaseURL)
        XCTAssertNoThrow(try store.add("selected text", section: store.activeSection, source: "Safari", sourceURL: "https://example.com/article"))
        XCTAssertEqual(store.notes.last?.sourceURLs, ["https://example.com/article"])
        XCTAssertNoThrow(try store.add("https://example.com/article", section: store.activeSection, sourceURL: "https://example.com/article"))
        XCTAssertEqual(store.notes.last?.sourceURLs, ["https://example.com/article"])
        XCTAssertNoThrow(try store.add("local text", section: store.activeSection, sourceURL: "file:///private/document.txt"))
        XCTAssertEqual(store.notes.last?.sourceURLs, [])
    }

    func testSectionsRejectInvalidNamesAndOrphanCaptures() throws {
        let store = CaptureStore(url: databaseURL)
        XCTAssertThrowsError(try store.chooseSection(" \n "))
        XCTAssertThrowsError(try store.chooseSection("First\nSecond"))
        XCTAssertThrowsError(try store.chooseSection(String(repeating: "a", count: 81)))
        XCTAssertNoThrow(try store.chooseSection(" Research "))
        XCTAssertNoThrow(try store.chooseSection("research"))
        XCTAssertEqual(store.sections, ["Inbox", "Research"])
        XCTAssertThrowsError(try store.add("orphan", section: "Missing"))
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertNoThrow(try store.add("saved", section: store.activeSection))
        XCTAssertThrowsError(try store.move([store.notes[0].id], to: "Missing"))
        XCTAssertEqual(store.notes[0].section, "Research")
    }

    func testSectionNavigationAndUnchangedEditPreserveUndo() throws {
        let store = CaptureStore(url: databaseURL)
        XCTAssertNoThrow(try store.chooseSection("Research"))
        XCTAssertNoThrow(try store.add("keep", section: store.activeSection))
        XCTAssertNoThrow(try store.update(store.notes[0].id, text: "keep"))
        XCTAssertNoThrow(try store.chooseSection("Inbox"))
        store.undoManager.undo()
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertEqual(store.sections, ["Inbox", "Research"])
        XCTAssertEqual(store.activeSection, "Inbox")
    }

    func testConcurrentFirstSaveCannotReplaceAnotherInstance() throws {
        let first = CaptureStore(url: databaseURL)
        let second = CaptureStore(url: databaseURL)
        XCTAssertNoThrow(try first.add("first writer", section: first.activeSection))
        XCTAssertThrowsError(try second.add("stale writer", section: second.activeSection))
        XCTAssertTrue(second.notes.isEmpty)
        XCTAssertEqual(CaptureStore(url: databaseURL).notes.map(\.text), ["first writer"])
    }

    func testStaleUpdateAndUndoLeaveSavedNotesIntact() {
        let first = CaptureStore(url: databaseURL)
        XCTAssertNoThrow(try first.add("baseline", section: first.activeSection))
        let second = CaptureStore(url: databaseURL)
        XCTAssertNoThrow(try second.add("newer note", section: second.activeSection))
        XCTAssertThrowsError(try first.update(first.notes[0].id, text: "stale edit"))
        var undoError: Error?
        first.reportUndoError = { undoError = $0 }
        first.undoManager.undo()
        XCTAssertNotNil(undoError)
        XCTAssertEqual(first.notes.map(\.text), ["baseline"])
        XCTAssertEqual(CaptureStore(url: databaseURL).notes.map(\.text), ["baseline", "newer note"])
    }

    func testLockedDatabaseRetainsNotesAndUndoUntilRetry() throws {
        let store = CaptureStore(url: databaseURL)
        XCTAssertNoThrow(try store.add("saved", section: store.activeSection))
        var lock: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &lock), SQLITE_OK)
        defer { sqlite3_close(lock) }
        XCTAssertEqual(sqlite3_exec(lock, "BEGIN IMMEDIATE", nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try store.add("retry me", section: store.activeSection))
        XCTAssertEqual(store.notes.map(\.text), ["saved"])
        XCTAssertEqual(sqlite3_exec(lock, "ROLLBACK", nil, nil, nil), SQLITE_OK)
        store.undoManager.undo()
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertNoThrow(try store.add("retry me", section: store.activeSection))
        XCTAssertEqual(CaptureStore(url: databaseURL).notes.map(\.text), ["retry me"])
        store.undoManager.undo()
        XCTAssertTrue(store.notes.isEmpty)
    }

    func testInvalidStoredSectionsBlockWrites() throws {
        let database = try Database(url: databaseURL)
        _ = try database.load()
        // `Database` stores an opaque blob, so the test encodes the invalid
        // state the way `CaptureStore` does.
        try database.save(JSONEncoder().encode(SavedState(notes: [Note(text: "preserve", section: "Missing")])))
        let before = try Data(contentsOf: databaseURL)
        let store = CaptureStore(url: databaseURL)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.add("overwrite", section: store.activeSection))
        XCTAssertEqual(try Data(contentsOf: databaseURL), before)
    }

    func testCaptureEditorConflictPreservesDraft() throws {
        let store = CaptureStore(url: databaseURL)
        XCTAssertNoThrow(try store.add("original", section: store.activeSection))
        let model = AppModel(store: store, wikiPath: folder.path, preferences: temporaryDefaults())
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
        try store.delete([store.notes[0].id])
        XCTAssertFalse(model.saveCaptureEdit(second))
        XCTAssertEqual(model.messages.last?.text, "This note was removed. Copy your changes into a new note.")
        XCTAssertTrue(model.captureEdits[second.id] === second)
    }
}
