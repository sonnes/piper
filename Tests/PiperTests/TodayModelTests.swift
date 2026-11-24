import AppKit
import Captures
@testable import Feeds
import Stream
import Vault
import XCTest
@testable import Piper

/// The verbs of Today: Keep, Done with Undo, File, Send, and the selection of several rows.
@MainActor
final class TodayModelTests: XCTestCase {

    private var root: URL!
    private var model: AppModel!
    private var today: TodayModel!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("piper-today-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Talks"), withIntermediateDirectories: true)
        try "# Harbor talk\n".write(to: root.appendingPathComponent("Talks/harbor-talk.md"), atomically: true, encoding: .utf8)
        let feedsURL = root.appendingPathComponent(".feeds/Feeds.sqlite")
        let database = try FeedDatabase(url: feedsURL)
        try database.save(Feed(id: "https://f.example/feed", title: "Fieldstone Weekly", nextFetch: .distantFuture))
        try database.insert(["one", "two"].map {
            Article(id: $0, feedID: "https://f.example/feed", url: "https://f.example/\($0)", title: "Post \($0)",
                    summary: "", published: Date(), arrived: Date())
        })
        model = AppModel(databaseURL: root.appendingPathComponent(".captures.sqlite"), wikiPath: root.path, preferences: temporaryDefaults(),
                         feeds: FeedStore(url: feedsURL) { XCTFail("\($0)") })
        model.library.reload()
        today = TodayModel(model: model)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func note(_ text: String) throws -> StreamItem {
        .capture(try model.store.add(text, section: "Inbox"), children: [])
    }

    private func article(_ id: String) throws -> StreamItem {
        let article = try XCTUnwrap(model.feeds.article(id))
        return .article(article, feed: model.feeds.feed(article.feedID), score: 0)
    }

    private func clip(_ text: String) throws -> StreamItem {
        model.clipboard.receive([text])
        return .clip(try XCTUnwrap(model.clipboard.entries.first { $0.text == text }))
    }

    private func stored(_ item: StreamItem) -> Note? {
        model.store.notes.first { $0.id == item.note?.id }
    }

    // MARK: - Keep

    func testKeepMarksANoteAndASecondKeepTakesTheMarkAway() throws {
        let item = try note("Ask Mira about the lift order")
        today.keep([item])
        XCTAssertEqual(stored(item)?.isKept, true)
        today.keep([.capture(try XCTUnwrap(stored(item)), children: [])])
        XCTAssertEqual(stored(item)?.isKept, false)
    }

    func testKeepTurnsAnArticleIntoAKeptLinkCaptureAndAClipIntoAKeptNote() throws {
        today.keep([try article("one"), try clip("ssh harbor-staging-2")])
        let link = try XCTUnwrap(model.store.notes.first { $0.text == "https://f.example/one" })
        XCTAssertTrue(link.isKept)
        XCTAssertEqual(link.sources, ["Fieldstone Weekly"])
        XCTAssertEqual(model.feeds.article("one")?.read, true)
        XCTAssertTrue(model.store.notes.contains { $0.text == "ssh harbor-staging-2" && $0.isKept })
        XCTAssertTrue(model.clipboard.entries.isEmpty)
    }

    func testKOnAnArticleKeepsItAndBIsTheOtherArticleKey() throws {
        let article = try XCTUnwrap(model.feeds.article("two"))
        let keys = PaperKey.articleKeys(actions: model.articleActions) { article }
        XCTAssertEqual(keys.map(\.key), [CommandKey("k", []), CommandKey("b", [])])
        XCTAssertEqual(model.feeds.article("two")?.read, false)
        keys[0].run()
        XCTAssertTrue(model.articleActions.isKept(article))
        XCTAssertEqual(model.feeds.article("two")?.read, true)
        XCTAssertFalse(PaperKey.articleKeys(actions: model.articleActions) { nil }.contains { $0.isOn() })
    }

    func testOpenInBrowserOpensTheLinkAndMarksTheArticleRead() throws {
        var opened: [URL] = []
        model.articleActions.openURL = { opened.append($0) }
        let article = try XCTUnwrap(model.feeds.article("one"))
        XCTAssertFalse(article.read)
        model.articleActions.openInBrowser(article)
        XCTAssertEqual(opened, [URL(string: "https://f.example/one")!])
        XCTAssertEqual(model.feeds.article("one")?.read, true)
    }

    // MARK: - Done

    func testDoneOffersUndoForEachKind() throws {
        let item = try note("Crane 3 is down until the 28th")
        let entry = try clip("tail -f cranes.log")
        today.done([item, try article("one"), entry])
        XCTAssertEqual(stored(item)?.isDone, true)
        XCTAssertEqual(model.feeds.article("one")?.read, true)
        XCTAssertTrue(model.clipboard.entries.isEmpty)
        XCTAssertEqual(today.undo?.message, "Done · 3 items")

        today.runUndo()
        XCTAssertNil(today.undo)
        XCTAssertEqual(stored(item)?.isDone, false)
        XCTAssertEqual(model.feeds.article("one")?.read, false)
        XCTAssertEqual(model.clipboard.entries.map(\.text), ["tail -f cranes.log"])
    }

    func testDoneOnADigestMarksEachArticleAsRead() throws {
        let feed = try XCTUnwrap(model.feeds.feed("https://f.example/feed"))
        let digest = StreamItem.digest(model.feeds.articles(.allUnread), feed: feed, day: Date())
        today.done([digest])
        XCTAssertTrue(model.feeds.articles(.allUnread).isEmpty)
        today.runUndo()
        XCTAssertEqual(model.feeds.articles(.allUnread).count, 2)
    }

    /// An article has no Delete in its menu, so the Delete key does nothing on it.
    func testDeleteDoesNothingOnAnArticle() throws {
        let item = try article("one")
        XCTAssertFalse(TodayModel.canDelete(item.id))
        today.delete([item])
        XCTAssertEqual(model.feeds.article("one")?.read, false)
        XCTAssertNil(today.undo)
    }

    func testDeleteRemovesACaptureWithUndo() throws {
        let item = try note("Delete me")
        today.delete([item])
        XCTAssertNil(stored(item))
        today.runUndo()
        XCTAssertNotNil(stored(item))
    }

    func testEditUndoAndRedoGoThroughTheSameStackAsTheUndoButton() throws {
        let item = try note("Crane 3 is down")
        let entry = try clip("tail -f cranes.log")
        today.done([item, try article("one"), entry])
        model.undoManager.undo()
        XCTAssertEqual(stored(item)?.isDone, false)
        XCTAssertEqual(model.feeds.article("one")?.read, false)
        XCTAssertEqual(model.clipboard.entries.map(\.text), ["tail -f cranes.log"])
        model.undoManager.redo()
        XCTAssertEqual(stored(item)?.isDone, true)
        XCTAssertEqual(model.feeds.article("one")?.read, true)
        XCTAssertTrue(model.clipboard.entries.isEmpty)
    }

    // MARK: - File

    func testFileIntoASectionMovesCapturesAndKeepsArticlesThere() throws {
        try model.store.chooseSection("Harbor")
        let item = try note("Lift order: north dock first")
        XCTAssertTrue(today.file([item, try article("two")], to: .section("Harbor")))
        XCTAssertEqual(stored(item)?.section, "Harbor")
        let link = try XCTUnwrap(model.store.notes.first { $0.text == "https://f.example/two" })
        XCTAssertEqual(link.section, "Harbor")
        XCTAssertEqual(model.feeds.article("two")?.read, true)
    }

    func testFileADigestIntoASectionKeepsEachArticleThere() throws {
        try model.store.chooseSection("Harbor")
        try model.store.chooseSection("Inbox")
        let feed = try XCTUnwrap(model.feeds.feed("https://f.example/feed"))
        let digest = StreamItem.digest(model.feeds.articles(.allUnread), feed: feed, day: Date())
        XCTAssertTrue(today.file([digest], to: .section("Harbor")))
        let links = model.store.notes.filter { $0.text.hasPrefix("https://f.example/") }
        XCTAssertEqual(links.map(\.section), ["Harbor", "Harbor"])
        XCTAssertTrue(links.allSatisfy(\.isKept))
        XCTAssertTrue(model.feeds.articles(.allUnread).isEmpty)
    }

    func testFileIntoAFolderSavesANewFileAndMarksTheNoteDone() throws {
        let item = try note("Tide tables list heights, not currents.")
        XCTAssertTrue(today.file([item], to: .folder(root: root.path, folder: "Talks")))
        let text = try String(contentsOf: root.appendingPathComponent("Talks/tide-tables-list-heights-not-currents.md"), encoding: .utf8)
        XCTAssertEqual(text, "Tide tables list heights, not currents.\n")
        XCTAssertEqual(stored(item)?.isDone, true)
        // A second file with the same name gets a number.
        XCTAssertTrue(today.file([try note("Tide tables list heights, not currents.")], to: .folder(root: root.path, folder: "Talks")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Talks/tide-tables-list-heights-not-currents-2.md").path))
    }

    func testFileIntoAFileAddsToItsEnd() throws {
        XCTAssertTrue(today.file([try note("Use this in the Thursday talk."), try article("one")], to: .file("Talks/harbor-talk.md")))
        let text = try String(contentsOf: root.appendingPathComponent("Talks/harbor-talk.md"), encoding: .utf8)
        XCTAssertEqual(text, "# Harbor talk\n\nUse this in the Thursday talk.\n\n- [Post one](https://f.example/one)\n")
    }

    /// A file that Piper cannot read stays as it is. Before the fix, Piper
    /// read such a file as empty and replaced it with the new text.
    func testFileIntoAFileThatCannotBeReadLeavesItAndReportsAnError() throws {
        let unreadable = root.appendingPathComponent("Talks/harbor-talk.md")
        try FileManager.default.setAttributes([.posixPermissions: 0o200], ofItemAtPath: unreadable.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path) }
        let latin = root.appendingPathComponent("Talks/latin.md")
        let bytes = Data([0x43, 0x61, 0x66, 0xE9, 0x0A])
        try bytes.write(to: latin)
        let item = try note("Use this in the Thursday talk.")

        XCTAssertFalse(today.file([item], to: .file("Talks/harbor-talk.md")))
        XCTAssertEqual(model.messages.last?.isError, true)
        XCTAssertFalse(today.file([item], to: .file("Talks/latin.md")))
        XCTAssertEqual(model.messages.last?.isError, true)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path)
        XCTAssertEqual(try String(contentsOf: unreadable, encoding: .utf8), "# Harbor talk\n")
        XCTAssertEqual(try Data(contentsOf: latin), bytes)
        XCTAssertEqual(stored(item)?.isDone, false)
    }

    func testFileIntoAMissingFileCreatesIt() throws {
        XCTAssertTrue(today.file([try note("Gate 4 closes at six.")], to: .file("Talks/gates.md")))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Talks/gates.md"), encoding: .utf8), "Gate 4 closes at six.\n")
    }

    func testFileTargetsListSectionsThenFoldersThenFiles() {
        let files = ["Harbor/talk.md", "image.png", "Harbor/plan.markdown"]
            .map { VaultFile(relativePath: $0, size: 0, modifiedAt: Date(), text: "") }
        let targets = FileTarget.targets(sections: ["Inbox", "Harbor"], roots: ["/n/Field Notes", "/n/Talks"], active: "/n/Talks",
                                         folders: ["Harbor"], files: files, query: "")
        XCTAssertEqual(targets, [.section("Inbox"), .section("Harbor"), .folder(root: "/n/Field Notes", folder: ""),
                                 .folder(root: "/n/Talks", folder: ""), .folder(root: "/n/Talks", folder: "Harbor"),
                                 .file("Harbor/plan.markdown"), .file("Harbor/talk.md")])
        XCTAssertEqual(targets[4].title, "Talks / Harbor")
        let search = FileTarget.targets(sections: ["Inbox", "Harbor"], roots: ["/n/Talks"], active: "/n/Talks",
                                        folders: ["Harbor"], files: files, query: "harb")
        XCTAssertEqual(search, [.section("Harbor"), .folder(root: "/n/Talks", folder: "Harbor"),
                                .file("Harbor/plan.markdown"), .file("Harbor/talk.md")])
    }

    // MARK: - Stream

    func testTheListIsBuiltAgainOnlyWhenAnInputChanges() throws {
        let first = today.list(lens: .all, scope: .today(section: nil))
        let builds = today.builds
        today.select(first.order[0])
        today.move(1, extending: true, in: today.list(lens: .all, scope: .today(section: nil)).order)
        _ = today.list(lens: .all, scope: .today(section: nil))
        XCTAssertEqual(today.builds, builds)
        _ = try note("Crane 3 is down")
        XCTAssertEqual(today.list(lens: .all, scope: .today(section: nil)).groups.flatMap(\.items).count, 3)
        XCTAssertEqual(today.builds, builds + 1)
        _ = today.list(lens: .notes, scope: .today(section: nil))
        today.query = "crane"
        _ = today.list(lens: .notes, scope: .today(section: nil))
        XCTAssertEqual(today.builds, builds + 3)
    }

    func testTheCountsGiveTheDoneCaptures() throws {
        _ = try note("Crane 3 is down")
        let done = try note("Gate 4 closes at six")
        today.done([done])
        let counts = today.counts()
        XCTAssertEqual(counts.done, 1)
        XCTAssertEqual(counts.open, 1)
        XCTAssertEqual(counts.sections["Inbox"], 1)
        XCTAssertEqual(today.list(lens: .all, scope: .done).order, [done.id])
    }

    func testAnOpenedArticleStaysUntilTheListShowsAgain() throws {
        today.open(article: "one")
        model.articleActions.setRead(true, ids: ["one"], undoable: false)
        XCTAssertTrue(today.list(lens: .all, scope: .today(section: nil)).order.contains(.article("one")))
        today.resetKeeping()
        XCTAssertFalse(today.list(lens: .all, scope: .today(section: nil)).order.contains(.article("one")))
    }

    // MARK: - Verbs

    func testTheKeysTheBarAndTheMenuListTheSameVerbs() throws {
        let item = try note("Crane 3 is down")
        let context = TodayVerb.Context(today: today, items: [item], first: item, open: { _ in }, edit: { _ in }, editInWindow: { _ in })
        let keys = TodayVerb.keys(context: { context }, run: { _, _ in })
        let table = keys.plain + keys.command
        let keyed = Set(table.map(\.title))
        let menu = Array(TodayVerb.menu.joined())
        for verb in TodayVerb.bar {
            XCTAssertTrue(keyed.contains(verb.id), "The bar shows \(verb.name) with no key.")
            XCTAssertTrue(menu.contains(verb), "The bar shows \(verb.name), and the menu does not.")
        }
        for verb in TodayVerb.row {
            XCTAssertTrue(TodayVerb.bar.contains(verb), "A row shows \(verb.name), and the bar does not.")
        }
        for verb in menu where !verb.keys.isEmpty {
            XCTAssertTrue(keyed.contains(verb.id), "The menu shows \(verb.name), and the keys do not run it.")
        }
        XCTAssertEqual(Set(table.map(\.key.glyph)).count, table.count, "Two verbs share a key.")
        XCTAssertEqual(TodayVerb.rowHint, "Click to select. Return opens it. K keeps, E marks as done, F files, and S sends it.")
    }

    // MARK: - Selection

    func testCommandClickShiftClickAndShiftArrowSelectSeveralRows() {
        let order: [StreamItem.Ref] = [.note(UUID()), .article("a"), .digest("f", Date(timeIntervalSince1970: 0)), .clip(UUID())]
        today.select(order[0])
        XCTAssertFalse(today.multiple)
        today.extend(to: order[2], range: true, in: order)
        XCTAssertEqual(today.selection, Set(order[0...2]))
        XCTAssertTrue(today.multiple)
        today.extend(to: order[1], range: false, in: order)
        XCTAssertEqual(today.selection, [order[0], order[2]])
        today.clearSelection()
        today.move(1, extending: false, in: order)
        XCTAssertEqual(today.selection, [order[0]])
        today.move(1, extending: true, in: order)
        XCTAssertEqual(today.selection, [order[0], order[1]])
        XCTAssertTrue(today.multiple)
        today.keepSelection(in: [order[1]])
        XCTAssertEqual(today.selection, [order[1]])
    }

    func testTheBarMergesAndCopiesTheSelection() throws {
        let first = try note("Lift order: north dock first on Tuesdays")
        let second = try note("Crane 3 is down until the 28th")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.piper.test." + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        today.copy([first, second], asList: true, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string),
                       "1. Lift order: north dock first on Tuesdays\n\n2. Crane 3 is down until the 28th")
        today.merge([first, second])
        XCTAssertEqual(model.store.notes.filter { $0.parent == nil }.count, 1)
        XCTAssertEqual(model.store.notes.first?.text, "Lift order: north dock first on Tuesdays\n\nCrane 3 is down until the 28th")
        XCTAssertEqual(today.selection, [.note(try XCTUnwrap(first.note?.id))])
    }

    func testACopyFromTodayStaysOutOfTheClipboardTray() throws {
        let item = try note("Gate 4 closes at six")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.piper.test." + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let tray = ClipboardInbox(store: model.store, database: nil, pasteboard: pasteboard) { XCTFail("\($0)") }
        tray.poll()
        XCTAssertNoThrow(try model.store.delete([try XCTUnwrap(item.note?.id)]))
        today.copy([item], to: pasteboard)
        tray.poll()
        XCTAssertEqual(pasteboard.string(forType: .string), "Gate 4 closes at six")
        XCTAssertTrue(tray.entries.isEmpty)
        XCTAssertEqual(model.messages.last?.text, "Copied")
    }

    // MARK: - Messages

    func testAFailedWriteReachesTheMessages() throws {
        let item = try note("Crane 3 is down")
        // A second instance writes first, so the notes of the model are stale.
        try CaptureStore(url: root.appendingPathComponent(".captures.sqlite")).add("from another instance", section: "Inbox")
        today.keep([item])
        let message = try XCTUnwrap(model.messages.last)
        XCTAssertTrue(message.isError)
        XCTAssertEqual(message.text, "Notes changed in another Piper instance. Restart Piper before saving. Your existing notes remain unchanged.")
        XCTAssertFalse(try XCTUnwrap(stored(item)).isKept)
    }

    // MARK: - Capture Field

    func testTheCaptureFieldTellsNotesLinksAndSourcesApart() {
        XCTAssertEqual(CaptureDraft("Ask Mira about the lift order"), .note)
        XCTAssertEqual(CaptureDraft(" https://tides.example/guide \n"), .link(URL(string: "https://tides.example/guide")!))
        XCTAssertEqual(CaptureDraft("https://tides.example"), .source(URL(string: "https://tides.example")!))
        XCTAssertEqual(CaptureDraft("https://tides.example/feed.xml"), .source(URL(string: "https://tides.example/feed.xml")!))
        XCTAssertEqual(CaptureDraft("https://tides.example/blog/feed"), .source(URL(string: "https://tides.example/blog/feed")!))
        XCTAssertEqual(CaptureDraft("https://tides.example/?p=4"), .link(URL(string: "https://tides.example/?p=4")!))
        XCTAssertEqual(CaptureDraft("see https://tides.example/guide"), .note)
    }

    func testAHashLineAloneNamesASection() {
        XCTAssertEqual(CaptureDraft("# Research"), .section("Research"))
        XCTAssertEqual(CaptureDraft("#  Field notes  "), .section("Field notes"))
        XCTAssertEqual(CaptureDraft("# "), .section(""))
        XCTAssertEqual(CaptureDraft("# literal\nheading"), .note)
        XCTAssertEqual(CaptureDraft("#hashtag"), .note)
    }
}
