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

    func testVerbsChangeSeveralCapturesWithOneUndoStep() throws {
        let store = CaptureStore(url: url())
        try store.add("one", section: store.activeSection)
        try store.add("two", section: store.activeSection)
        try store.chooseSection("Harbor")
        try store.chooseSection("Inbox")
        let ids = Set(store.notes.map(\.id))

        XCTAssertNoThrow(try store.setKept(true, ids))
        XCTAssertTrue(store.notes.allSatisfy(\.isKept))
        store.undoManager.undo()
        XCTAssertFalse(store.notes.contains(where: \.isKept))

        XCTAssertNoThrow(try store.setDone(true, ids))
        XCTAssertTrue(store.notes.allSatisfy(\.isDone))
        store.undoManager.undo()
        XCTAssertFalse(store.notes.contains(where: \.isDone))

        XCTAssertNoThrow(try store.move(ids, to: "Harbor"))
        XCTAssertEqual(Set(store.notes.map(\.section)), ["Harbor"])
        store.undoManager.undo()
        XCTAssertEqual(Set(store.notes.map(\.section)), ["Inbox"])
        XCTAssertThrowsError(try store.move(ids, to: "Missing"))
    }

    func testKeepLinksAddsKeptCapturesAndTagsKnownLinks() throws {
        let store = CaptureStore(url: url())
        try store.add("https://a.example/known", section: store.activeSection)
        let kept = try store.keep(links: [
            KeptLink(url: URL(string: "https://www.a.example/known/")!),
            KeptLink(url: URL(string: "https://a.example/new")!, title: "New", source: "A Feed"),
            KeptLink(url: URL(string: "https://a.example/new#top")!)
        ])
        XCTAssertEqual(kept.map(\.text), ["https://a.example/known", "https://a.example/new", "https://a.example/new"])
        XCTAssertEqual(store.notes.count, 2)
        XCTAssertTrue(store.notes.allSatisfy(\.isKept))
        XCTAssertEqual(store.notes.last?.reading?.title, "New")
        store.undoManager.undo()
        XCTAssertEqual(store.notes.map(\.text), ["https://a.example/known"])
        XCTAssertFalse(store.notes[0].isKept)
    }

    func testPageNoteIsAddedOnceAndIsNotAnArticle() throws {
        let store = CaptureStore(url: url())
        let first = try store.pageNote(for: "piper-file://reading/journal.md", title: "Reading journal", source: "Reader")
        let second = try store.pageNote(for: "piper-file://reading/journal.md", title: "Reading journal", source: "Reader")
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertFalse(first.isArticle)
    }

    func testSeveralNotesDeleteTogether() throws {
        let store = CaptureStore(url: url())
        for text in ["first", "second", "third"] { XCTAssertNoThrow(try store.add(text, section: store.activeSection)) }
        let ids = store.notes.map(\.id)
        try store.delete([ids[0], ids[2]])
        XCTAssertEqual(store.notes.map(\.text), ["second"])
        store.undoManager.undo()
        XCTAssertEqual(store.notes.map(\.text), ["first", "second", "third"])
    }

    func testPersistenceMergeUndoAndExactText() throws {
        let url = url()
        let store = CaptureStore(url: url)
        let text = "  αβ\n\t`code`\n"
        XCTAssertNoThrow(try store.add(text, section: store.activeSection))
        XCTAssertNoThrow(try store.add("second", section: store.activeSection, source: "TextEdit"))
        let merged = try store.merge(store.notes.map(\.id))
        XCTAssertEqual(store.notes, [merged])
        XCTAssertEqual(store.notes[0].text, text + "\n\nsecond")
        store.undoManager.undo()
        XCTAssertEqual(store.notes.count, 2)
        XCTAssertEqual(CaptureStore(url: url).notes[0].text, text)
        XCTAssertNoThrow(try store.add("# literal heading", section: "Inbox"))
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
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.add("overwrite", section: store.activeSection))
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
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.add("overwrite", section: store.activeSection))
        XCTAssertTrue(store.notes.isEmpty)
    }

    func testUndoRestoresDeletedNotes() throws {
        let store = CaptureStore(url: url())
        XCTAssertNoThrow(try store.add("first", section: store.activeSection))
        XCTAssertNoThrow(try store.add("second", section: store.activeSection))
        try store.delete(store.notes.map(\.id))
        XCTAssertTrue(store.notes.isEmpty)
        store.undoManager.undo()
        XCTAssertEqual(store.notes.map(\.text), ["first", "second"])
        XCTAssertEqual(CaptureStore(url: url()).notes.count, 2)

        XCTAssertNoThrow(try store.add("third", section: store.activeSection))
        store.undoManager.undo()
        XCTAssertEqual(store.notes.map(\.text), ["first", "second"])
    }

    func testUndoHasSeveralLevelsAndRedo() throws {
        let store = CaptureStore(url: url())
        XCTAssertNoThrow(try store.add("first", section: store.activeSection))
        XCTAssertNoThrow(try store.add("second", section: store.activeSection))
        try store.delete([store.notes[0].id])
        store.undoManager.undo()
        XCTAssertEqual(store.notes.map(\.text), ["first", "second"])
        store.undoManager.undo()
        XCTAssertEqual(store.notes.map(\.text), ["first"])
        store.undoManager.redo()
        XCTAssertEqual(store.notes.map(\.text), ["first", "second"])
        store.undoManager.redo()
        XCTAssertEqual(store.notes.map(\.text), ["second"])
        XCTAssertEqual(CaptureStore(url: url()).notes.map(\.text), ["second"])
    }

    func testUndoOfADeleteKeepsLaterReadingProgress() throws {
        let store = CaptureStore(url: url())
        let gone = try store.saveArticle(URL(string: "https://example.dev/gone")!)
        let read = try store.saveArticle(URL(string: "https://example.dev/read")!)
        try store.delete([gone.id])
        try store.updateReading(read.id) { $0.progress = 0.5 }
        store.undoManager.undo()
        XCTAssertEqual(store.notes.map(\.id), [gone.id, read.id])
        XCTAssertEqual(store.notes[1].reading?.progress, 0.5)
        XCTAssertEqual(CaptureStore(url: url()).notes[1].reading?.progress, 0.5)
    }

    func testUndoOfAnEditKeepsTheFieldsThatALaterChangeSet() throws {
        let store = CaptureStore(url: url())
        let article = try store.saveArticle(URL(string: "https://example.dev/wal")!)
        try store.toggleDone(article.id)
        try store.updateReading(article.id) { $0.progress = 0.8 }
        try store.append("An answer.", to: article.id)
        store.undoManager.undo()
        XCTAssertFalse(store.notes[0].isDone)
        XCTAssertEqual(store.notes[0].reading?.progress, 0.8)
        XCTAssertTrue(store.notes[0].text.hasSuffix("An answer."))
    }

    func testChangingTheActiveSectionSavesWithoutAnUndoStep() throws {
        let store = CaptureStore(url: url())
        XCTAssertNoThrow(try store.chooseSection("Research"))
        XCTAssertEqual(store.sections, ["Inbox", "Research"])
        XCTAssertEqual(store.activeSection, "Research")
        store.undoManager.undo()
        XCTAssertEqual(store.sections, ["Inbox"])
        XCTAssertEqual(store.activeSection, "Inbox")

        XCTAssertNoThrow(try store.chooseSection("Research"))
        store.undoManager.undo()
        XCTAssertNoThrow(try store.chooseSection("Research"))
        XCTAssertNoThrow(try store.chooseSection("inbox"))
        XCTAssertEqual(store.activeSection, "Inbox")
        store.undoManager.undo()
        XCTAssertEqual(store.sections, ["Inbox"])
        XCTAssertEqual(store.activeSection, "Inbox")
    }

    func testTheActiveSectionSurvivesAnUndo() throws {
        let store = CaptureStore(url: url())
        XCTAssertNoThrow(try store.chooseSection("Research"))
        XCTAssertNoThrow(try store.add("a note", section: store.activeSection))
        try store.delete(store.notes.map(\.id))
        try store.chooseSection("Inbox")
        store.undoManager.undo()
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.activeSection, "Inbox")
        XCTAssertEqual(CaptureStore(url: url()).activeSection, "Inbox")
    }

    func testASecondInstanceCannotOverwriteTheFirst() throws {
        let url = url("shared.sqlite")
        let first = CaptureStore(url: url)
        let second = CaptureStore(url: url)
        XCTAssertNil(first.loadError)
        XCTAssertNil(second.loadError)
        XCTAssertNoThrow(try first.add("from the first instance", section: first.activeSection))
        XCTAssertThrowsError(try second.add("from the second instance", section: second.activeSection)) { error in
            XCTAssertEqual(error.localizedDescription,
                           "Notes changed in another Piper instance. Restart Piper before saving. Your existing notes remain unchanged.")
        }
        XCTAssertTrue(second.notes.isEmpty)
        XCTAssertEqual(CaptureStore(url: url).notes.map(\.text), ["from the first instance"])

        let third = CaptureStore(url: url)
        let fourth = CaptureStore(url: url)
        XCTAssertNoThrow(try third.add("third", section: third.activeSection))
        XCTAssertThrowsError(try fourth.add("fourth", section: fourth.activeSection))
        XCTAssertEqual(CaptureStore(url: url).notes.map(\.text), ["from the first instance", "third"])
    }

    func testAnUnavailableDatabaseRejectsEveryChange() throws {
        let store = CaptureStore(url: folder)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.add("a note", section: store.activeSection))
        XCTAssertThrowsError(try store.chooseSection("Research"))
        XCTAssertTrue(store.notes.isEmpty)
        store.undoManager.undo()
        XCTAssertTrue(store.notes.isEmpty)
    }

    func testUpdateRejectsAStaleEditAndAMissingNote() throws {
        let store = CaptureStore(url: url())
        XCTAssertNoThrow(try store.add("original", section: store.activeSection))
        let id = store.notes[0].id
        XCTAssertThrowsError(try store.update(id, text: "   ", originalText: "original"))
        XCTAssertThrowsError(try store.update(UUID(), text: "text")) { error in
            XCTAssertEqual(error.localizedDescription, "This note was removed. Copy your changes into a new note.")
        }
        XCTAssertThrowsError(try store.update(id, text: "changed", originalText: "something else")) { error in
            XCTAssertEqual(error.localizedDescription, "This note changed in another editor. Copy your changes before reopening the note.")
        }
        XCTAssertEqual(store.notes[0].text, "original")
        XCTAssertNoThrow(try store.update(id, text: "original"))
        XCTAssertNoThrow(try store.update(id, text: "changed", originalText: "original"))
        XCTAssertEqual(store.notes[0].text, "changed")
        XCTAssertNoThrow(try store.update(id, text: "changed", sourceURL: ""))
        XCTAssertTrue(store.notes[0].sourceURLs.isEmpty)
    }

    func testAddKeepsOnlyWebSourceURLs() throws {
        let store = CaptureStore(url: url())
        XCTAssertNoThrow(try store.add("https://example.com/page", section: store.activeSection))
        XCTAssertEqual(store.notes[0].sourceURLs, ["https://example.com/page"])
        XCTAssertNoThrow(try store.add("plain text", section: store.activeSection, sourceURL: "javascript:alert(1)"))
        XCTAssertTrue(store.notes[1].sourceURLs.isEmpty)
        XCTAssertThrowsError(try store.add("   \n\t", section: store.activeSection))
        XCTAssertThrowsError(try store.add("a note", section: "Missing")) { error in
            XCTAssertEqual(error.localizedDescription, "This section no longer exists. Choose another section.")
        }
    }

    func testEmbeddedLinksDoNotBecomeWholeTextSourceURLs() throws {
        let store = CaptureStore(url: url())
        let text = "https://example.com/article This is a note"
        XCTAssertNoThrow(try store.add(text, section: store.activeSection))
        XCTAssertEqual(store.notes[0].text, text)
        XCTAssertTrue(store.notes[0].sourceURLs.isEmpty)
        XCTAssertNoThrow(try store.add(text, section: store.activeSection, sourceURL: "https://source.example/page"))
        XCTAssertEqual(store.notes[1].sourceURLs, ["https://source.example/page"])
        XCTAssertNoThrow(try store.update(store.notes[0].id, text: "https://swift.org"))
        XCTAssertEqual(CaptureLinks(store.notes[0].text).standaloneURL?.absoluteString, "https://swift.org")
    }

    func testSectionNamesAreLimitedToOneShortLine() throws {
        let store = CaptureStore(url: url())
        XCTAssertThrowsError(try store.chooseSection("  "))
        XCTAssertThrowsError(try store.chooseSection("two\nlines"))
        XCTAssertThrowsError(try store.chooseSection(String(repeating: "x", count: 81))) { error in
            XCTAssertEqual(error.localizedDescription, "Use a section name with 1 to 80 characters on one line.")
        }
        XCTAssertEqual(store.sections, ["Inbox"])
        XCTAssertNoThrow(try store.chooseSection(String(repeating: "x", count: 80)))
        XCTAssertEqual(store.sections.count, 2)
    }

    func testRenameSectionPreservesNotesAndPersistsOneUndoStep() throws {
        let store = CaptureStore(url: url())
        XCTAssertNoThrow(try store.chooseSection("Research"))
        XCTAssertNoThrow(try store.add("a note", section: store.activeSection, source: "Safari"))
        let original = store.state
        let note = store.notes[0]

        XCTAssertNoThrow(try store.renameSection("Research", to: "  Reading  "))
        XCTAssertEqual(store.sections, ["Inbox", "Reading"])
        XCTAssertEqual(store.activeSection, "Reading")
        var renamed = note
        renamed.section = "Reading"
        XCTAssertEqual(store.notes, [renamed])
        XCTAssertEqual(CaptureStore(url: url()).state, store.state)

        store.undoManager.undo()
        XCTAssertEqual(store.state, original)
        XCTAssertEqual(CaptureStore(url: url()).state, original)
    }

    func testRenameSectionRejectsInvalidNamesAndAllowsCaseChanges() throws {
        let store = CaptureStore(url: url())
        XCTAssertNoThrow(try store.chooseSection("Research"))
        let original = store.state
        for name in ["", "  ", "two\nlines", String(repeating: "x", count: 81), "INBOX"] {
            XCTAssertThrowsError(try store.renameSection("Research", to: name))
            XCTAssertEqual(store.state, original)
        }
        try store.renameSection("Inbox", to: "Archive")
        try store.renameSection("Missing", to: "Archive")
        XCTAssertEqual(store.state, original)
        try store.chooseSection("Inbox")
        XCTAssertNoThrow(try store.renameSection("Research", to: "research"))
        XCTAssertEqual(store.sections, ["Inbox", "research"])
        XCTAssertEqual(store.activeSection, "Inbox")
    }

    func testDeleteSectionMovesNotesToInboxAndUndoRestoresThem() throws {
        let store = CaptureStore(url: url())
        XCTAssertNoThrow(try store.add("existing inbox note", section: store.activeSection))
        XCTAssertNoThrow(try store.chooseSection("Research"))
        XCTAssertNoThrow(try store.add("research note", section: store.activeSection, source: "Safari", sourceURL: "https://example.com"))
        let id = store.notes[1].id
        try store.toggleDone(id)
        let original = store.state

        XCTAssertNoThrow(try store.deleteSection("Research"))
        XCTAssertEqual(store.sections, ["Inbox"])
        XCTAssertEqual(store.activeSection, "Inbox")
        XCTAssertEqual(store.notes.map(\.section), ["Inbox", "Inbox"])
        XCTAssertEqual(store.notes.map(\.id), original.notes.map(\.id))
        XCTAssertEqual(store.notes.map(\.text), original.notes.map(\.text))
        XCTAssertEqual(store.notes[1].sources, ["Safari"])
        XCTAssertEqual(store.notes[1].sourceURLs, ["https://example.com"])
        XCTAssertTrue(store.notes[1].isDone)
        XCTAssertEqual(CaptureStore(url: url()).state, store.state)

        store.undoManager.undo()
        XCTAssertEqual(store.notes, original.notes)
        XCTAssertEqual(store.sections, original.sections)
        XCTAssertEqual(store.activeSection, "Inbox")
        XCTAssertEqual(CaptureStore(url: url()).state, store.state)
    }

    func testDeletingAnEmptySectionKeepsTheActiveSectionAndProtectsInbox() throws {
        let store = CaptureStore(url: url())
        XCTAssertNoThrow(try store.chooseSection("Research"))
        XCTAssertNoThrow(try store.chooseSection("Work"))
        XCTAssertNoThrow(try store.deleteSection("Research"))
        XCTAssertEqual(store.sections, ["Inbox", "Work"])
        XCTAssertEqual(store.activeSection, "Work")
        let original = store.state
        try store.deleteSection("Inbox")
        try store.deleteSection("Missing")
        XCTAssertEqual(store.state, original)
    }

    func testSectionChangesLeaveMemoryUntouchedWhenPersistenceFails() throws {
        let first = CaptureStore(url: url())
        XCTAssertNoThrow(try first.chooseSection("Research"))
        XCTAssertNoThrow(try first.add("original note", section: first.activeSection))
        let stale = CaptureStore(url: url())
        let original = stale.state
        XCTAssertNoThrow(try first.add("another note", section: first.activeSection))

        XCTAssertThrowsError(try stale.renameSection("Research", to: "Reading"))
        XCTAssertEqual(stale.state, original)
        XCTAssertThrowsError(try stale.deleteSection("Research"))
        XCTAssertEqual(stale.state, original)
        stale.undoManager.undo()
        XCTAssertEqual(stale.state, original)
        XCTAssertEqual(CaptureStore(url: url()).state, first.state)
    }

    func testMergeFollowsTheSectionsAndMovesNeedASection() throws {
        let store = CaptureStore(url: url())
        XCTAssertNoThrow(try store.chooseSection("Research"))
        XCTAssertNoThrow(try store.add("alpha", section: "Inbox"))
        XCTAssertNoThrow(try store.add("beta", section: "Inbox"))
        let ids = store.notes.map(\.id)
        XCTAssertEqual(try store.merge([ids[1], ids[0]]).text, "alpha\n\nbeta")
        store.undoManager.undo()

        XCTAssertNoThrow(try store.move(Set(ids), to: "Research"))
        XCTAssertEqual(Set(store.notes.map(\.section)), ["Research"])
        XCTAssertThrowsError(try store.move(Set(ids), to: "Missing"))
        XCTAssertEqual(Set(store.notes.map(\.section)), ["Research"])
    }

    func testMergeNeedsMoreThanOneNote() throws {
        let store = CaptureStore(url: url())
        XCTAssertNoThrow(try store.add("only", section: store.activeSection, source: "Mail"))
        XCTAssertThrowsError(try store.merge(store.notes.map(\.id)))
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertNoThrow(try store.add("second", section: store.activeSection, source: "Safari"))
        try store.merge(store.notes.map(\.id))
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.notes[0].sources, ["Mail", "Safari"])
    }

    // MARK: - Child Notes

    func testANoteSavedBeforeParentsDecodesWithoutThem() throws {
        let json = #"{"notes":[{"id":"9B2D1A57-8C55-4C1B-9E1F-0B7E7F1F0A11","text":"old","section":"Inbox","sources":[],"sourceURLs":[],"isDone":false,"createdAt":0,"modifiedAt":0}],"sections":["Inbox"],"activeSection":"Inbox"}"#
        let state = try JSONDecoder().decode(SavedState.self, from: Data(json.utf8))
        XCTAssertNil(state.notes[0].parent)
        XCTAssertEqual(state.notes[0].tags, [])
        XCTAssertNil(state.notes[0].anchor)
    }

    func testChildNotesShowUnderTheirParentAndPersist() throws {
        let url = url()
        let store = CaptureStore(url: url)
        XCTAssertNoThrow(try store.add("https://example.dev/wal", section: store.activeSection))
        let parent = store.notes[0].id
        let anchor = NoteAnchor(quote: "old pages", block: 1, offset: 40)
        try store.addChild("old pages", to: parent, tags: ["highlight", "yellow"], anchor: anchor)
        XCTAssertEqual(store.children(of: parent).map(\.text), ["old pages"])

        let reopened = CaptureStore(url: url)
        XCTAssertEqual(reopened.children(of: parent).first?.parent, parent)
        XCTAssertEqual(reopened.children(of: parent).first?.tags, ["highlight", "yellow"])
        XCTAssertEqual(reopened.children(of: parent).first?.anchor, anchor)
        XCTAssertEqual(reopened.children(of: parent).first?.sourceURLs, ["https://example.dev/wal"])
    }

    func testDeletingAParentDeletesItsChildren() throws {
        let store = CaptureStore(url: url())
        XCTAssertNoThrow(try store.add("https://example.dev/wal", section: store.activeSection))
        XCTAssertNoThrow(try store.add("other", section: store.activeSection))
        let parent = store.notes[0].id
        XCTAssertNoThrow(try store.addChild("quote", to: parent, tags: ["highlight"]))
        try store.delete([parent])
        XCTAssertEqual(store.notes.map(\.text), ["other"])
    }

    func testMovingAParentMovesItsChildren() throws {
        let store = CaptureStore(url: url())
        XCTAssertNoThrow(try store.add("https://example.dev/wal", section: store.activeSection))
        XCTAssertNoThrow(try store.chooseSection("Reading"))
        let parent = store.notes[0].id
        XCTAssertNoThrow(try store.addChild("quote", to: parent, tags: ["highlight"]))
        XCTAssertNoThrow(try store.move([parent], to: "Reading"))
        XCTAssertEqual(store.notes.map(\.section), ["Reading", "Reading"])
    }

    func testAChildNeedsAParentThatExists() throws {
        let store = CaptureStore(url: url())
        XCTAssertThrowsError(try store.addChild("quote", to: UUID(), tags: []))
        XCTAssertTrue(store.notes.isEmpty)
    }

    func testAppendAddsAParagraph() throws {
        let store = CaptureStore(url: url())
        XCTAssertNoThrow(try store.add("Explain: wal-index", section: store.activeSection))
        let id = store.notes[0].id
        XCTAssertNoThrow(try store.append("  A lookup table.  ", to: id))
        XCTAssertEqual(store.notes[0].text, "Explain: wal-index\n\nA lookup table.")
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

    func testAVersionOneDatabaseLoadsAndTakesNewChanges() throws {
        let url = url("v1.sqlite")
        let v1 = Data(#"{"notes":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"from 0.3","section":"Inbox","sources":[],"sourceURLs":[],"isDone":false,"createdAt":0,"modifiedAt":0}],"sections":["Inbox"],"activeSection":"Inbox"}"#.utf8)
        writeState(version: 1, v1, to: url)
        let store = CaptureStore(url: url)
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.notes.map(\.text), ["from 0.3"])
        XCTAssertNoThrow(try store.addChild("a quote", to: store.notes[0].id, tags: ["highlight"]))
        XCTAssertNoThrow(try store.add("second", section: store.activeSection))
        XCTAssertEqual(CaptureStore(url: url).children(of: store.notes[0].id).map(\.tags), [["highlight"]])
    }

    func testAVersionThreeDatabaseIsRefused() throws {
        let url = url("v3.sqlite")
        writeState(version: 3, Data(#"{"notes":[],"sections":["Inbox"],"activeSection":"Inbox"}"#.utf8), to: url)
        let before = try Data(contentsOf: url)
        let store = CaptureStore(url: url)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.add("overwrite", section: store.activeSection))
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    // MARK: - Deleting

    func testDeletingOneNoteTakesItsChildren() throws {
        let store = CaptureStore(url: url())
        XCTAssertNoThrow(try store.add("https://example.dev/wal", section: store.activeSection))
        XCTAssertNoThrow(try store.add("another", section: store.activeSection))
        let parent = store.notes[0].id
        let other = store.notes[1].id
        let child = try store.addChild("quote", to: parent, tags: ["highlight"])
        XCTAssertNoThrow(try store.addChild("Explain: quote", to: child.id, tags: ["question"]))

        XCTAssertNoThrow(try store.delete([child.id]))
        XCTAssertEqual(store.notes.map(\.text), ["https://example.dev/wal", "another"])
        XCTAssertTrue(store.children(of: parent).isEmpty)
        XCTAssertTrue(store.notes.contains { $0.id == other })
        store.undoManager.undo()
        XCTAssertEqual(store.children(of: parent).map(\.id), [child.id])
        XCTAssertEqual(store.children(of: child.id).count, 1)

        XCTAssertNoThrow(try store.delete([parent]))
        XCTAssertEqual(store.notes.map(\.text), ["another"])
    }

    func testPageTextOfADeletedArticleGoesAtTheNextLaunch() throws {
        let url = url()
        let store = CaptureStore(url: url)
        let kept = URL(string: "https://example.dev/kept")!
        let gone = URL(string: "https://www.example.dev/gone?utm_source=feed")!
        let orphan = URL(string: "https://example.dev/orphan")!
        try store.saveArticle(kept)
        let goneArticle = try store.saveArticle(gone)
        try store.savePageText("kept text", for: kept)
        try store.savePageText("gone text", for: gone)
        try store.savePageText("orphan text", for: orphan)

        XCTAssertNoThrow(try store.delete([goneArticle.id]))
        XCTAssertEqual(try store.pageText(for: gone), "gone text")

        let reopened = CaptureStore(url: url)
        XCTAssertEqual(try reopened.pageText(for: kept), "kept text")
        XCTAssertNil(try reopened.pageText(for: gone))
        XCTAssertNil(try reopened.pageText(for: orphan))
    }

    // MARK: - Merging

    func testMergeMovesChildrenToTheMergedNote() throws {
        let store = CaptureStore(url: url())
        XCTAssertNoThrow(try store.add("first", section: store.activeSection))
        XCTAssertNoThrow(try store.add("second", section: store.activeSection))
        let first = store.notes[0].id
        let second = store.notes[1].id
        let child = try store.addChild("quote", to: second, tags: ["highlight"])
        try store.merge([first, second])
        XCTAssertEqual(store.notes.filter { $0.parent == nil }.map(\.id), [first])
        XCTAssertEqual(store.children(of: first).map(\.id), [child.id])
        XCTAssertTrue(store.children(of: second).isEmpty)
        XCTAssertEqual(CaptureStore(url: url()).notes.first { $0.id == child.id }?.parent, first)
    }
}
