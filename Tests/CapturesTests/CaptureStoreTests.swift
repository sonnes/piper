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

    func testArchivedNotesStayOutOfSectionsAndSearch() {
        let store = CaptureStore(url: url())
        XCTAssertTrue(store.add("active note"))
        XCTAssertTrue(store.add("archived note"))
        let archivedID = store.notes[1].id
        store.toggleDone(archivedID)

        XCTAssertEqual(store.visibleNotes(in: "Inbox").map(\.text), ["active note"])
        XCTAssertEqual(store.visibleNotes(in: "Inbox", archived: true).map(\.id), [archivedID])
        store.query = "archived"
        XCTAssertTrue(store.visibleNotes(in: "Inbox").isEmpty)
        XCTAssertEqual(store.visibleNotes(in: "Inbox", archived: true).map(\.id), [archivedID])
        store.query = "missing"
        XCTAssertTrue(store.visibleNotes(in: "Inbox", archived: true).isEmpty)
        store.query = ""
        store.toggleDone(archivedID)
        XCTAssertEqual(store.visibleNotes(in: "Inbox").count, 2)
        XCTAssertTrue(store.visibleNotes(in: "Inbox", archived: true).isEmpty)
    }

    func testMultipleSelectionsCopyAndDeleteTogether() {
        let store = CaptureStore(url: url())
        for text in ["first", "second", "third"] { XCTAssertTrue(store.add(text)) }
        let ids = store.notes.map(\.id)
        store.toggleSelection(ids[0])
        store.toggleSelection(ids[1])
        store.toggleSelection(ids[2])
        store.toggleSelection(ids[1])
        XCTAssertEqual(store.selection, [ids[0], ids[2]])
        XCTAssertEqual(store.copyText(asList: false), "first\n\nthird")
        store.deleteSelection()
        XCTAssertEqual(store.notes.map(\.text), ["second"])
        XCTAssertTrue(store.selection.isEmpty)
        store.undo()
        XCTAssertEqual(store.notes.map(\.text), ["first", "second", "third"])
    }

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

    func testEmbeddedLinksDoNotBecomeWholeTextSourceURLs() {
        let store = CaptureStore(url: url())
        let text = "https://example.com/article This is a note"
        XCTAssertTrue(store.add(text, interpretSection: false))
        XCTAssertEqual(store.notes[0].text, text)
        XCTAssertTrue(store.notes[0].sourceURLs.isEmpty)
        XCTAssertTrue(store.add(text, sourceURL: "https://source.example/page", interpretSection: false))
        XCTAssertEqual(store.notes[1].sourceURLs, ["https://source.example/page"])
        XCTAssertTrue(store.update(store.notes[0].id, text: "https://swift.org"))
        XCTAssertEqual(CaptureLinks(store.notes[0].text).standaloneURL?.absoluteString, "https://swift.org")
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

    func testRenameSectionPreservesNotesAndPersistsOneUndoStep() {
        let store = CaptureStore(url: url())
        XCTAssertTrue(store.chooseSection("Research"))
        XCTAssertTrue(store.add("a note", source: "Safari", interpretSection: false))
        let original = store.state
        let note = store.notes[0]
        store.selection = [note.id]

        XCTAssertTrue(store.renameSection("Research", to: "  Reading  "))
        XCTAssertEqual(store.sections, ["Inbox", "Reading"])
        XCTAssertEqual(store.activeSection, "Reading")
        var renamed = note
        renamed.section = "Reading"
        XCTAssertEqual(store.notes, [renamed])
        XCTAssertEqual(store.selection, [note.id])
        XCTAssertEqual(CaptureStore(url: url()).state, store.state)

        store.undo()
        XCTAssertEqual(store.state, original)
        XCTAssertEqual(CaptureStore(url: url()).state, original)
    }

    func testRenameSectionRejectsInvalidNamesAndAllowsCaseChanges() {
        let store = CaptureStore(url: url())
        XCTAssertTrue(store.chooseSection("Research"))
        let original = store.state
        for name in ["", "  ", "two\nlines", String(repeating: "x", count: 81), "INBOX"] {
            XCTAssertFalse(store.renameSection("Research", to: name))
            XCTAssertEqual(store.state, original)
        }
        XCTAssertFalse(store.renameSection("Inbox", to: "Archive"))
        XCTAssertFalse(store.renameSection("Missing", to: "Archive"))
        XCTAssertEqual(store.state, original)
        store.activeSection = "Inbox"
        XCTAssertTrue(store.renameSection("Research", to: "research"))
        XCTAssertEqual(store.sections, ["Inbox", "research"])
        XCTAssertEqual(store.activeSection, "Inbox")
    }

    func testDeleteSectionMovesNotesToInboxAndUndoRestoresThem() {
        let store = CaptureStore(url: url())
        XCTAssertTrue(store.add("existing inbox note", interpretSection: false))
        XCTAssertTrue(store.chooseSection("Research"))
        XCTAssertTrue(store.add("research note", source: "Safari", sourceURL: "https://example.com", interpretSection: false))
        let id = store.notes[1].id
        store.toggleDone(id)
        store.selection = [id]
        let original = store.state

        XCTAssertTrue(store.deleteSection("Research"))
        XCTAssertEqual(store.sections, ["Inbox"])
        XCTAssertEqual(store.activeSection, "Inbox")
        XCTAssertEqual(store.notes.map(\.section), ["Inbox", "Inbox"])
        XCTAssertEqual(store.notes.map(\.id), original.notes.map(\.id))
        XCTAssertEqual(store.notes.map(\.text), original.notes.map(\.text))
        XCTAssertEqual(store.notes[1].sources, ["Safari"])
        XCTAssertEqual(store.notes[1].sourceURLs, ["https://example.com"])
        XCTAssertTrue(store.notes[1].isDone)
        XCTAssertEqual(store.selection, [id])
        XCTAssertEqual(CaptureStore(url: url()).state, store.state)

        store.undo()
        XCTAssertEqual(store.notes, original.notes)
        XCTAssertEqual(store.sections, original.sections)
        XCTAssertEqual(store.activeSection, "Inbox")
        XCTAssertEqual(CaptureStore(url: url()).state, store.state)
    }

    func testDeletingAnEmptySectionKeepsTheActiveSectionAndProtectsInbox() {
        let store = CaptureStore(url: url())
        XCTAssertTrue(store.chooseSection("Research"))
        XCTAssertTrue(store.chooseSection("Work"))
        XCTAssertTrue(store.deleteSection("Research"))
        XCTAssertEqual(store.sections, ["Inbox", "Work"])
        XCTAssertEqual(store.activeSection, "Work")
        let original = store.state
        XCTAssertFalse(store.deleteSection("Inbox"))
        XCTAssertFalse(store.deleteSection("Missing"))
        XCTAssertEqual(store.state, original)
    }

    func testSectionChangesLeaveMemoryUntouchedWhenPersistenceFails() {
        let first = CaptureStore(url: url())
        XCTAssertTrue(first.chooseSection("Research"))
        XCTAssertTrue(first.add("original note", interpretSection: false))
        let stale = CaptureStore(url: url())
        let original = stale.state
        XCTAssertTrue(first.add("another note", interpretSection: false))

        XCTAssertFalse(stale.renameSection("Research", to: "Reading"))
        XCTAssertEqual(stale.state, original)
        XCTAssertFalse(stale.deleteSection("Research"))
        XCTAssertEqual(stale.state, original)
        XCTAssertFalse(stale.canUndo)
        XCTAssertEqual(CaptureStore(url: url()).state, first.state)
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
        XCTAssertTrue(store.visibleNotes(in: "Research").isEmpty)
        XCTAssertEqual(store.visibleNotes(in: "Research", archived: true).map(\.text), ["alpha"])
        store.query = ""
        XCTAssertEqual(store.visibleNotes(in: "Research").map(\.text), ["beta"])
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

    // MARK: - Child Notes

    func testANoteSavedBeforeParentsDecodesWithoutThem() throws {
        let json = #"{"notes":[{"id":"9B2D1A57-8C55-4C1B-9E1F-0B7E7F1F0A11","text":"old","section":"Inbox","sources":[],"sourceURLs":[],"isDone":false,"createdAt":0,"modifiedAt":0}],"sections":["Inbox"],"activeSection":"Inbox"}"#
        let state = try JSONDecoder().decode(SavedState.self, from: Data(json.utf8))
        XCTAssertNil(state.notes[0].parent)
        XCTAssertEqual(state.notes[0].tags, [])
        XCTAssertNil(state.notes[0].anchor)
    }

    func testChildNotesShowUnderTheirParentAndPersist() {
        let url = url()
        let store = CaptureStore(url: url)
        XCTAssertTrue(store.add("https://example.dev/wal"))
        let parent = store.notes[0].id
        let anchor = NoteAnchor(quote: "old pages", block: 1, offset: 40)
        let child = store.addChild("old pages", to: parent, tags: ["highlight", "yellow"], anchor: anchor)
        XCTAssertNotNil(child)
        XCTAssertEqual(store.visibleNotes(in: "Inbox").map(\.id), [parent])
        XCTAssertEqual(store.children(of: parent).map(\.text), ["old pages"])

        let reopened = CaptureStore(url: url)
        XCTAssertEqual(reopened.children(of: parent).first?.parent, parent)
        XCTAssertEqual(reopened.children(of: parent).first?.tags, ["highlight", "yellow"])
        XCTAssertEqual(reopened.children(of: parent).first?.anchor, anchor)
        XCTAssertEqual(reopened.children(of: parent).first?.sourceURLs, ["https://example.dev/wal"])
    }

    func testASearchThatMatchesAChildFindsTheParent() {
        let store = CaptureStore(url: url())
        XCTAssertTrue(store.add("https://example.dev/wal"))
        XCTAssertTrue(store.add("other"))
        let parent = store.notes[0].id
        XCTAssertNotNil(store.addChild("checkpoint starvation", to: parent, tags: ["highlight"]))
        store.query = "starvation"
        XCTAssertEqual(store.visibleNotes(in: "Inbox").map(\.id), [parent])
    }

    func testDeletingAParentDeletesItsChildren() {
        let store = CaptureStore(url: url())
        XCTAssertTrue(store.add("https://example.dev/wal"))
        XCTAssertTrue(store.add("other"))
        let parent = store.notes[0].id
        XCTAssertNotNil(store.addChild("quote", to: parent, tags: ["highlight"]))
        store.selection = [parent]
        store.deleteSelection()
        XCTAssertEqual(store.notes.map(\.text), ["other"])
    }

    func testMovingAParentMovesItsChildren() {
        let store = CaptureStore(url: url())
        XCTAssertTrue(store.add("https://example.dev/wal"))
        XCTAssertTrue(store.chooseSection("Reading"))
        let parent = store.notes[0].id
        XCTAssertNotNil(store.addChild("quote", to: parent, tags: ["highlight"]))
        store.selection = [parent]
        store.move(to: "Reading")
        XCTAssertEqual(store.notes.map(\.section), ["Reading", "Reading"])
    }

    func testAChildNeedsAParentThatExists() {
        let store = CaptureStore(url: url())
        XCTAssertNil(store.addChild("quote", to: UUID(), tags: []))
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.notes.isEmpty)
    }

    func testAppendAndAddTag() {
        let store = CaptureStore(url: url())
        XCTAssertTrue(store.add("Explain: wal-index"))
        let id = store.notes[0].id
        XCTAssertTrue(store.append("  A lookup table.  ", to: id))
        XCTAssertEqual(store.notes[0].text, "Explain: wal-index\n\nA lookup table.")
        XCTAssertTrue(store.addTag("#SQLite", to: id))
        XCTAssertTrue(store.addTag("sqlite", to: id))
        XCTAssertFalse(store.addTag("two words", to: id))
        XCTAssertEqual(store.notes[0].tags, ["sqlite"])
    }

    // MARK: - Database Version

    /// Writes a state table with one row, as an earlier or a later Piper writes it.
    private func writeState(version: Int32, _ data: Data, to url: URL) {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        sqlite3_exec(db, "CREATE TABLE state (id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL, data BLOB NOT NULL)", nil, nil, nil)
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "INSERT INTO state VALUES(1,?,?)", -1, &statement, nil), SQLITE_OK)
        sqlite3_bind_int(statement, 1, version)
        data.withUnsafeBytes { bytes in
            _ = sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
        sqlite3_finalize(statement)
        sqlite3_close(db)
    }

    private func storedVersion(at url: URL) -> Int32? {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT version FROM state WHERE id=1", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int(statement, 0) : nil
    }

    func testAVersionOneDatabaseLoadsAndSavesAsVersionTwo() throws {
        let url = url("v1.sqlite")
        let v1 = Data(#"{"notes":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"from 0.3","section":"Inbox","sources":[],"sourceURLs":[],"isDone":false,"createdAt":0,"modifiedAt":0}],"sections":["Inbox"],"activeSection":"Inbox"}"#.utf8)
        writeState(version: 1, v1, to: url)
        let store = CaptureStore(url: url)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.notes.map(\.text), ["from 0.3"])
        XCTAssertNotNil(store.addChild("a quote", to: store.notes[0].id, tags: ["highlight"]))
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(storedVersion(at: url), 2)
        // A second save compares against version 2.
        XCTAssertTrue(store.add("second", interpretSection: false))
        XCTAssertEqual(CaptureStore(url: url).children(of: store.notes[0].id).map(\.tags), [["highlight"]])
    }

    func testANewDatabaseIsVersionTwo() {
        let url = url("new.sqlite")
        XCTAssertTrue(CaptureStore(url: url).add("first", interpretSection: false))
        XCTAssertEqual(storedVersion(at: url), 2)
    }

    func testAVersionThreeDatabaseIsRefused() throws {
        let url = url("v3.sqlite")
        writeState(version: 3, Data(#"{"notes":[],"sections":["Inbox"],"activeSection":"Inbox"}"#.utf8), to: url)
        let before = try Data(contentsOf: url)
        let store = CaptureStore(url: url)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.add("overwrite", interpretSection: false))
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(storedVersion(at: url), 3)
    }

    // MARK: - Deleting

    func testDeletingOneNoteTakesItsChildrenAndKeepsTheSelection() throws {
        let store = CaptureStore(url: url())
        XCTAssertTrue(store.add("https://example.dev/wal"))
        XCTAssertTrue(store.add("another", interpretSection: false))
        let parent = store.notes[0].id
        let other = store.notes[1].id
        let child = try XCTUnwrap(store.addChild("quote", to: parent, tags: ["highlight"]))
        XCTAssertNotNil(store.addChild("Explain: quote", to: child.id, tags: ["question"]))
        store.selection = [other, child.id]

        XCTAssertTrue(store.delete(child.id))
        XCTAssertEqual(store.notes.map(\.text), ["https://example.dev/wal", "another"])
        XCTAssertTrue(store.children(of: parent).isEmpty)
        XCTAssertEqual(store.selection, [other])
        XCTAssertTrue(store.canUndo)
        store.undo()
        XCTAssertEqual(store.children(of: parent).map(\.id), [child.id])
        XCTAssertEqual(store.children(of: child.id).count, 1)

        XCTAssertTrue(store.delete(parent))
        XCTAssertEqual(store.notes.map(\.text), ["another"])
    }

    func testDeletingAnArticleRemovesItsPageText() throws {
        let url = url()
        let store = CaptureStore(url: url)
        let kept = URL(string: "https://example.dev/kept")!
        let gone = URL(string: "https://www.example.dev/gone?utm_source=feed")!
        let orphan = URL(string: "https://example.dev/orphan")!
        let keptArticle = try XCTUnwrap(store.saveArticle(kept))
        let goneArticle = try XCTUnwrap(store.saveArticle(gone))
        store.savePageText("kept text", for: kept)
        store.savePageText("gone text", for: gone)
        store.savePageText("orphan text", for: orphan)

        XCTAssertTrue(store.delete(goneArticle.id))
        // Undo can bring the article back, so its page text stays for now.
        XCTAssertEqual(store.pageText(for: gone), "gone text")

        let reopened = CaptureStore(url: url)
        XCTAssertEqual(reopened.pageText(for: kept), "kept text")
        XCTAssertNil(reopened.pageText(for: gone))
        XCTAssertNil(reopened.pageText(for: orphan))
    }

    func testASecondDeleteRemovesThePageTextOfTheFirst() throws {
        let store = CaptureStore(url: url())
        let first = URL(string: "https://example.dev/first")!
        let second = URL(string: "https://example.dev/second")!
        let firstArticle = try XCTUnwrap(store.saveArticle(first))
        let secondArticle = try XCTUnwrap(store.saveArticle(second))
        store.savePageText("first text", for: first)
        store.savePageText("second text", for: second)
        XCTAssertTrue(store.delete(firstArticle.id))
        XCTAssertTrue(store.delete(secondArticle.id))
        XCTAssertNil(store.pageText(for: first))
        XCTAssertEqual(store.pageText(for: second), "second text")
    }

    // MARK: - Merging And Copying

    func testMergeMovesChildrenToTheMergedNote() throws {
        let store = CaptureStore(url: url())
        XCTAssertTrue(store.add("first", interpretSection: false))
        XCTAssertTrue(store.add("second", interpretSection: false))
        let first = store.notes[0].id
        let second = store.notes[1].id
        let child = try XCTUnwrap(store.addChild("quote", to: second, tags: ["highlight"]))
        store.selection = [first, second]
        store.merge()
        XCTAssertEqual(store.notes.filter { $0.parent == nil }.map(\.id), [first])
        XCTAssertEqual(store.children(of: first).map(\.id), [child.id])
        XCTAssertTrue(store.children(of: second).isEmpty)
        XCTAssertEqual(CaptureStore(url: url()).notes.first { $0.id == child.id }?.parent, first)
    }

    func testCopyingOneNoteWritesItsTextWithTheMarker() throws {
        let store = CaptureStore(url: url())
        XCTAssertTrue(store.add("copied text", interpretSection: false))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("piper-tests-" + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        store.copy(store.notes[0].id, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "copied text")
        XCTAssertNotNil(pasteboard.data(forType: ClipboardInbox.copiedNoteType))
        XCTAssertEqual(store.status, "Copied")
    }
}
