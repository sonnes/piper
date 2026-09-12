import AppKit
import XCTest
@testable import Piper

@MainActor
final class ClipboardInboxTests: XCTestCase {
    private var folder: URL!
    private var pasteboard: NSPasteboard!
    private var store: AppStore!
    private var inbox: ClipboardInbox!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("piper-clipboard-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.piper.test." + UUID().uuidString))
        store = AppStore(url: folder.appendingPathComponent("notes.sqlite"))
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
        XCTAssertTrue(AppStore(url: folder.appendingPathComponent("notes.sqlite")).notes.isEmpty)
        let id = inbox.entries[0].id
        XCTAssertTrue(inbox.save(id))
        XCTAssertTrue(inbox.entries.isEmpty)
        XCTAssertEqual(store.notes.first?.text, text)
        XCTAssertEqual(store.notes.first?.section, "Inbox")
        XCTAssertEqual(store.notes.first?.sources, ["Clipboard"])
        XCTAssertEqual(AppStore(url: folder.appendingPathComponent("notes.sqlite")).notes.first?.text, text)
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
        for index in 0..<12 { copy("item \(index)") }
        XCTAssertEqual(inbox.entries.count, 10)
        XCTAssertEqual(inbox.entries.first?.text, "item 11")
        XCTAssertEqual(inbox.entries.last?.text, "item 2")
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

    func testSavingUsesChosenSectionAndDoesNotInterpretAHeading() {
        copy("# Keep this heading")
        store.add("# Research")
        XCTAssertTrue(inbox.save(inbox.entries[0].id))
        XCTAssertEqual(store.notes.first?.section, "Research")
        XCTAssertEqual(store.notes.first?.text, "# Keep this heading")
        XCTAssertEqual(store.sections, ["Inbox", "Research"])
    }

    func testFailedSaveKeepsTheGhostAvailable() {
        let failed = AppStore(url: folder)
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
