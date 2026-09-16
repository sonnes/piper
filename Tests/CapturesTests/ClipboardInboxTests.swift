import AppKit
import XCTest
import Captures

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
}
