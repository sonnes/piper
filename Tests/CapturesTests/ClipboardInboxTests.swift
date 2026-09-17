import AppKit
import XCTest
import Captures
import CSQLite

@MainActor
final class ClipboardInboxTests: XCTestCase {
    private var folder: URL!
    private var pasteboard: NSPasteboard!
    private var store: CaptureStore!
    private var inbox: ClipboardInbox!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("piper-clipboard-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.piper.test." + UUID().uuidString))
        store = CaptureStore(url: folder.appendingPathComponent("notes.sqlite"))
        inbox = ClipboardInbox(store: store, pasteboard: pasteboard)
    }

    override func tearDown() async throws {
        inbox.stop()
        pasteboard.releaseGlobally()
        inbox = nil
        store = nil
        try FileManager.default.removeItem(at: folder)
    }

    private func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        inbox.poll()
    }

    func testClipboardStaysTemporaryUntilClickedAndSavesExactText() {
        let text = "  # A literal heading\n\t`code`\n"
        copy(text)
        XCTAssertEqual(inbox.entries.map(\.text), [text])
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertTrue(CaptureStore(url: folder.appendingPathComponent("notes.sqlite")).notes.isEmpty)
        let id = inbox.entries[0].id
        XCTAssertTrue(inbox.save(id))
        XCTAssertTrue(inbox.entries.isEmpty)
        XCTAssertEqual(store.notes.first?.text, text)
        XCTAssertEqual(store.notes.first?.section, "Inbox")
        XCTAssertEqual(store.notes.first?.sources, ["Clipboard"])
        XCTAssertEqual(CaptureStore(url: folder.appendingPathComponent("notes.sqlite")).notes.first?.text, text)
        XCTAssertFalse(inbox.save(id))
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), text)
    }

    func testRepeatedCopiesMoveToFrontWithoutDuplicatingAndHistoryIsBounded() {
        copy("first")
        let id = inbox.entries[0].id
        inbox.poll()
        XCTAssertEqual(inbox.entries.count, 1)
        copy("second")
        copy("first")
        XCTAssertEqual(inbox.entries.map(\.text), ["first", "second"])
        XCTAssertEqual(inbox.entries[0].id, id)
        let limit = ClipboardInbox.historyLimit
        for index in 0..<(limit + 2) { copy("item \(index)") }
        XCTAssertEqual(inbox.entries.count, limit)
        XCTAssertEqual(inbox.entries.first?.text, "item \(limit + 1)")
        XCTAssertEqual(inbox.entries.last?.text, "item 2")
    }

    func testACopyRecordsItsTimeAndSourceAndARepeatMovesTheTimeForward() {
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)
        inbox.receive(["first"], source: "Safari", at: early)
        inbox.receive(["second"], source: "Terminal", at: early)
        let id = inbox.entries[1].id
        XCTAssertEqual(inbox.entries[1].source, "Safari")
        XCTAssertEqual(inbox.entries[1].copiedAt, early)
        inbox.receive(["first"], source: "Notes", at: late)
        XCTAssertEqual(inbox.entries.map(\.text), ["first", "second"])
        XCTAssertEqual(inbox.entries[0].id, id)
        XCTAssertEqual(inbox.entries[0].copiedAt, late)
        XCTAssertEqual(inbox.entries[0].source, "Notes")
    }

    func testClearForgetsTheHistoryAndSavesNothing() {
        copy("one")
        copy("two")
        inbox.clear()
        XCTAssertTrue(inbox.entries.isEmpty)
        XCTAssertTrue(store.notes.isEmpty)
        copy("three")
        XCTAssertEqual(inbox.entries.map(\.text), ["three"])
    }

    func testUndoRestoresAnUnsavedGhostAfterAnotherCopy() {
        copy("first thought")
        let id = inbox.entries[0].id
        XCTAssertTrue(inbox.save(id))
        copy("next thought")
        XCTAssertEqual(inbox.entries.map(\.text), ["next thought"])
        store.undo()
        XCTAssertEqual(inbox.entries.map(\.text), ["next thought", "first thought"])
        XCTAssertEqual(inbox.entries.last?.id, id)
        XCTAssertTrue(store.notes.isEmpty)
    }

    func testSavedNotesAndNonTextItemsDoNotBecomeGhosts() {
        store.add("already saved")
        copy("already saved")
        copy(" \n\t")
        pasteboard.clearContents()
        pasteboard.setData(Data([1, 2, 3]), forType: .png)
        inbox.poll()
        XCTAssertTrue(inbox.entries.isEmpty)
        copy("save another way")
        store.add("save another way")
        XCTAssertTrue(inbox.entries.isEmpty)
    }

    func testMarkedClipboardContentIsIgnored() {
        for type in [ClipboardInbox.copiedNoteType, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"), NSPasteboard.PasteboardType("org.nspasteboard.TransientType")] {
            pasteboard.clearContents()
            pasteboard.setString("excluded", forType: .string)
            pasteboard.setData(Data(), forType: type)
            inbox.poll()
            XCTAssertTrue(inbox.entries.isEmpty)
        }
        copy("ordinary text")
        XCTAssertEqual(inbox.entries.map(\.text), ["ordinary text"])
    }

    func testSavingAlwaysUsesInboxAndDoesNotInterpretAHeading() {
        copy("# Keep this heading")
        store.add("# Research")
        XCTAssertTrue(inbox.save(inbox.entries[0].id))
        XCTAssertEqual(store.notes.first?.section, "Inbox")
        XCTAssertEqual(store.activeSection, "Research")
        XCTAssertEqual(store.notes.first?.text, "# Keep this heading")
        XCTAssertEqual(store.sections, ["Inbox", "Research"])
    }

    func testFailedSaveKeepsTheGhostAvailable() {
        let failed = CaptureStore(url: folder)
        let previews = ClipboardInbox(store: failed, pasteboard: pasteboard)
        previews.receive(["keep until saved"])
        let id = previews.entries[0].id
        XCTAssertFalse(previews.save(id))
        XCTAssertEqual(previews.entries[0].id, id)
        XCTAssertTrue(failed.notes.isEmpty)
        XCTAssertNotNil(failed.errorMessage)
    }

    func testMultiplePasteboardItemsKeepTheirOrderAndRejectOversizedText() {
        let first = NSPasteboardItem()
        first.setString("one", forType: .string)
        let second = NSPasteboardItem()
        second.setString("two", forType: .string)
        pasteboard.clearContents()
        pasteboard.writeObjects([first, second])
        inbox.poll()
        XCTAssertEqual(inbox.entries.map(\.text), ["one", "two"])
        copy(String(repeating: "x", count: 500_001))
        XCTAssertEqual(inbox.entries.map(\.text), ["one", "two"])
    }

    // MARK: - Stored History

    private func reopen(now: Date = Date()) -> ClipboardInbox {
        let reopened = CaptureStore(url: folder.appendingPathComponent("notes.sqlite"))
        return ClipboardInbox(store: reopened, pasteboard: pasteboard, now: now)
    }

    func testHistorySurvivesARestartWithItsIdentityTimeAndSource() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        inbox.receive(["first"], source: "Safari", at: date)
        inbox.receive(["emoji 🐦\u{0}after a null", "no source"], at: date.addingTimeInterval(60))
        let reopened = reopen(now: date.addingTimeInterval(120))
        XCTAssertEqual(reopened.entries, inbox.entries)
        XCTAssertEqual(reopened.entries.last?.source, "Safari")
        XCTAssertNil(reopened.entries.first?.source)
    }

    func testTextsOlderThanTheRetentionPeriodLeaveOnOpenAndWhileRunning() {
        let day: TimeInterval = 24 * 60 * 60
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        inbox.receive(["old"], at: start)
        inbox.receive(["new"], at: start.addingTimeInterval(3 * day))
        XCTAssertEqual(reopen(now: start.addingTimeInterval(7 * day + 1)).entries.map(\.text), ["new"])
        XCTAssertEqual(inbox.entries.map(\.text), ["new", "old"])
        inbox.removeExpired(at: start.addingTimeInterval(10 * day + 1))
        XCTAssertTrue(inbox.entries.isEmpty)
        XCTAssertTrue(reopen(now: start).entries.isEmpty)
    }

    func testClearAndTheHistoryLimitAlsoChangeTheStoredHistory() {
        for index in 0..<(ClipboardInbox.historyLimit + 2) { copy("item \(index)") }
        let reopened = reopen()
        XCTAssertEqual(reopened.entries.count, ClipboardInbox.historyLimit)
        XCTAssertEqual(reopened.entries.last?.text, "item 2")
        inbox.clear()
        XCTAssertTrue(reopen().entries.isEmpty)
    }

    func testADatabaseFromBeforeTheClipboardTableGainsTheTable() throws {
        let url = folder.appendingPathComponent("old.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        let state = #"{"notes":[],"sections":["Inbox"],"activeSection":"Inbox"}"#
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE state (id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL, data BLOB NOT NULL); INSERT INTO state VALUES(1,1,CAST('\(state)' AS BLOB));", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let oldStore = CaptureStore(url: url)
        XCTAssertNil(oldStore.errorMessage)
        ClipboardInbox(store: oldStore, pasteboard: pasteboard).receive(["after upgrade"])
        XCTAssertNil(oldStore.errorMessage)
        XCTAssertEqual(ClipboardInbox(store: CaptureStore(url: url), pasteboard: pasteboard).entries.map(\.text), ["after upgrade"])
    }

    func testSavingANoteKeepsTheStoredText() {
        copy("keep me")
        XCTAssertTrue(inbox.save(inbox.entries[0].id))
        store.undo()
        XCTAssertEqual(reopen().entries.map(\.text), ["keep me"])
    }
}
