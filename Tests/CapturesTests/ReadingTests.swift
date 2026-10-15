import XCTest
import Captures

@MainActor
final class ReadingTests: XCTestCase {

    // MARK: - Properties

    private var folder: URL!
    private let page = URL(string: "https://www.example.dev/notes/sqlite-wal/?utm_source=feed#intro")!

    // MARK: - Setup

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("reading-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    private func store() -> CaptureStore { CaptureStore(url: folder.appendingPathComponent("notes.sqlite")) }

    // MARK: - Links

    func testCanonicalLinksIgnoreTrackingFragmentsAndWWW() {
        let plain = CaptureLinks.canonical(URL(string: "https://example.dev/notes/sqlite-wal")!)
        XCTAssertEqual(CaptureLinks.canonical(page), plain)
        XCTAssertEqual(CaptureLinks.canonical(URL(string: "http://EXAMPLE.dev/notes/sqlite-wal?fbclid=1")!), plain)
        XCTAssertNotEqual(CaptureLinks.canonical(URL(string: "https://example.dev/notes/sqlite-wal?page=2")!), plain)
        XCTAssertEqual(CaptureLinks.canonical(URL(string: "https://example.dev/")!), "https://example.dev")
    }

    // MARK: - Saving

    func testHighlightsFromOnePageGoUnderOneArticle() throws {
        let store = store()
        let first = try XCTUnwrap(store.saveHighlight("A reader that starts\n before a commit", in: page, title: "WAL",
                                                      source: "Safari", tags: ["highlight", "yellow"]))
        let second = try XCTUnwrap(store.saveHighlight("one long read", in: URL(string: "https://example.dev/notes/sqlite-wal")!,
                                                       source: "Safari", tags: ["highlight", "yellow"]))
        XCTAssertEqual(first.article.id, second.article.id)
        XCTAssertEqual(store.notes.filter { $0.parent == nil }.count, 1)
        XCTAssertEqual(first.article.text, page.absoluteString)
        XCTAssertEqual(first.article.reading?.title, "WAL")
        XCTAssertEqual(first.article.sources, ["Safari"])
        XCTAssertEqual(first.highlight.text, "A reader that starts before a commit")
        XCTAssertEqual(first.highlight.anchor, NoteAnchor(quote: "A reader that starts before a commit", block: -1, offset: 0))
        XCTAssertEqual(first.highlight.sources, ["Safari"])
        XCTAssertEqual(store.children(of: first.article.id).count, 2)
    }

    func testAPlainNoteFromAPageIsNotItsArticle() throws {
        let store = store()
        XCTAssertTrue(store.add("A quote from the page", source: "Safari", sourceURL: page.absoluteString))
        let saved = try XCTUnwrap(store.saveHighlight("one long read", in: page, tags: ["highlight"]))
        XCTAssertNotEqual(saved.article.id, store.notes[0].id)
        XCTAssertFalse(store.notes[0].isArticle)
        XCTAssertTrue(saved.article.isArticle)
        XCTAssertTrue(Note(text: " https://example.dev/a\n", section: "Inbox").isArticle)
    }

    func testSavingAnArticleAgainReopensItAndKeepsTheFirstTitle() throws {
        let store = store()
        let article = try XCTUnwrap(store.saveArticle(page, title: "First", source: "Safari"))
        store.toggleDone(article.id)
        let again = try XCTUnwrap(store.saveArticle(page, title: "Second"))
        XCTAssertEqual(again.id, article.id)
        XCTAssertFalse(again.isDone)
        XCTAssertEqual(again.reading?.title, "First")
        XCTAssertNil(store.saveArticle(URL(string: "file:///tmp/a.html")!))
    }

    func testACommentFollowsTheQuote() throws {
        let store = store()
        let saved = try XCTUnwrap(store.saveHighlight("one long read", in: page, tags: ["highlight", "yellow"]))
        XCTAssertTrue(store.comment("  This is the bug.  ", on: saved.highlight.id))
        let highlight = try XCTUnwrap(store.notes.first { $0.id == saved.highlight.id })
        XCTAssertEqual(highlight.text, "one long read\n\nThis is the bug.")
        XCTAssertEqual(HighlightText.comment(of: highlight.text, quote: highlight.anchor?.quote), "This is the bug.")
        XCTAssertEqual(HighlightText.comment(of: "a\n\nb", quote: "a\n\nb"), "")
    }

    func testReadingStateSurvivesARestartWithoutAnUndoStep() throws {
        let store = store()
        let article = try XCTUnwrap(store.saveArticle(page))
        let date = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(store.updateReading(article.id) { $0.block = 4; $0.progress = 0.5; $0.minutes = 8; $0.openedAt = date })
        let reopened = self.store()
        let reading = try XCTUnwrap(reopened.notes.first?.reading)
        XCTAssertEqual(reading.block, 4)
        XCTAssertEqual(reading.minutesLeft, 4)
        XCTAssertEqual(reading.openedAt, date)
    }

    func testPageTextIsKeptByCanonicalLink() {
        let store = store()
        XCTAssertNil(store.pageText(for: page))
        store.savePageText("Full text of the page", for: page)
        XCTAssertEqual(store.pageText(for: URL(string: "https://example.dev/notes/sqlite-wal")!), "Full text of the page")
    }

    // MARK: - Groups

    func testReadingGroupsStartedNewAndFinishedArticles() throws {
        let store = store()
        let now = Date()
        let fresh = try XCTUnwrap(store.saveArticle(URL(string: "https://a.dev/new")!))
        let started = try XCTUnwrap(store.saveHighlight("text", in: URL(string: "https://a.dev/started")!, tags: ["highlight"])).article
        let opened = try XCTUnwrap(store.saveArticle(URL(string: "https://a.dev/opened")!))
        store.updateReading(opened.id) { $0.openedAt = now }
        let done = try XCTUnwrap(store.saveArticle(URL(string: "https://a.dev/done")!))
        store.updateReading(done.id) { $0.finishedAt = now.addingTimeInterval(-3_600) }
        let old = try XCTUnwrap(store.saveArticle(URL(string: "https://a.dev/old")!))
        store.updateReading(old.id) { $0.finishedAt = now.addingTimeInterval(-10 * 86_400) }
        XCTAssertTrue(store.add("A plain note with a link https://a.dev/x inside"))

        let list = ReadingList(notes: store.notes, now: now)
        XCTAssertEqual(Set(list.inProgress.map(\.id)), [started.id, opened.id])
        XCTAssertEqual(list.upNext.map(\.id), [fresh.id])
        XCTAssertEqual(list.finished.map(\.id), [done.id])
        XCTAssertEqual(list.count, 4)

        store.archiveFinishedReading(before: now.addingTimeInterval(-7 * 86_400))
        XCTAssertEqual(store.notes.first { $0.id == old.id }?.isDone, true)
        XCTAssertEqual(store.notes.first { $0.id == done.id }?.isDone, false)
    }

    func testCountsNameHighlightsNotesAndQuestions() {
        let parent = UUID()
        let children = [
            Note(text: "q\n\nmine", section: "Inbox", parent: parent, tags: ["highlight"], anchor: NoteAnchor(quote: "q", block: 0, offset: 0)),
            Note(text: "r", section: "Inbox", parent: parent, tags: ["highlight"]),
            Note(text: "Explain: r", section: "Inbox", parent: parent, tags: ["question"])
        ]
        XCTAssertEqual(ReadingList.counts(of: children), "2 highlights · 1 note · 1 question")
        XCTAssertEqual(ReadingList.counts(of: []), "")
    }

    // MARK: - Markdown

    func testTheFileHoldsTheSourceSummaryAndHighlights() {
        let parent = UUID()
        let saved = Date(timeIntervalSince1970: 2_000_000_000)
        let children = [
            Note(text: "My summary.", section: "Inbox", parent: parent, tags: ["summary"]),
            Note(text: "one long read\n\nThe bug.", section: "Inbox", modifiedAt: saved.addingTimeInterval(-60), parent: parent,
                 tags: ["highlight", "yellow"], anchor: NoteAnchor(quote: "one long read", block: 2, offset: 0)),
            Note(text: "Explain: wal-index\n\nA table.", section: "Inbox", parent: parent, tags: ["question"])
        ]
        let url = URL(string: "https://example.dev/wal")!
        let text = ArticleMarkdown.file(title: "The \"WAL\"", url: url, children: children, parts: .init(), date: saved)
        XCTAssertTrue(text.hasPrefix("---\nsource: https://example.dev/wal\ntitle: \"The \\\"WAL\\\"\"\nread: "))
        XCTAssertTrue(text.contains("# The \"WAL\"\n\nMy summary.\n"))
        XCTAssertTrue(text.contains("## Highlights\n\n> one long read\n\nThe bug.\n"))
        XCTAssertFalse(text.contains("## Questions"))
        let answers = ArticleMarkdown.file(title: "T", url: url, children: children, parts: .init(answers: true), date: saved)
        XCTAssertTrue(answers.contains("### Explain: wal-index\n\nA table.\n"))

        XCTAssertNil(ArticleMarkdown.update(children: children, after: saved, date: saved))
        var changed = children
        changed[1].modifiedAt = saved.addingTimeInterval(60)
        XCTAssertEqual(ArticleMarkdown.update(children: changed, after: saved, date: saved)?.contains("> one long read"), true)
        XCTAssertEqual(ArticleMarkdown.fileName(for: "How the Write-Ahead Log keeps SQLite fast!"), "how-the-write-ahead-log-keeps-sqlite-fast.md")
        XCTAssertEqual(ArticleMarkdown.fileName(for: "???"), "article.md")
    }

    func testArchiveMarksOnlyArticlesFinishedBeforeTheDate() throws {
        let store = store()
        let now = Date()
        let old = try XCTUnwrap(store.saveArticle(URL(string: "https://a.dev/old")!))
        store.updateReading(old.id) { $0.finishedAt = now.addingTimeInterval(-8 * 86_400) }
        let recent = try XCTUnwrap(store.saveArticle(URL(string: "https://a.dev/recent")!))
        store.updateReading(recent.id) { $0.finishedAt = now.addingTimeInterval(-86_400) }
        let unread = try XCTUnwrap(store.saveArticle(URL(string: "https://a.dev/unread")!))
        store.updateReading(unread.id) { $0.openedAt = now.addingTimeInterval(-30 * 86_400) }

        store.archiveFinishedReading(before: now.addingTimeInterval(-7 * 86_400))
        let reopened = self.store()
        XCTAssertEqual(reopened.notes.first { $0.id == old.id }?.isDone, true)
        XCTAssertEqual(reopened.notes.first { $0.id == recent.id }?.isDone, false)
        XCTAssertEqual(reopened.notes.first { $0.id == unread.id }?.isDone, false)
    }

    func testTheFileTitleStaysOnOneLine() {
        let url = URL(string: "https://example.dev/wal")!
        let text = ArticleMarkdown.file(title: "C:\\logs \"WAL\"\nPart 2", url: url, children: [], parts: .init(), date: Date())
        XCTAssertTrue(text.contains("\ntitle: \"C:\\\\logs \\\"WAL\\\" Part 2\"\n"), text)
        XCTAssertTrue(text.contains("\n# C:\\\\logs \"WAL\" Part 2\n"), text)
    }

    func testAnUpdateAddsOnlyTheChangedHighlightsUnderTheDate() throws {
        let parent = UUID()
        let saved = Date(timeIntervalSince1970: 2_000_000_000)
        let children = [
            Note(text: "old quote", section: "Inbox", modifiedAt: saved.addingTimeInterval(-60), parent: parent, tags: ["highlight"],
                 anchor: NoteAnchor(quote: "old quote", block: 0, offset: 0)),
            Note(text: "new quote\n\nMy note.", section: "Inbox", modifiedAt: saved.addingTimeInterval(60), parent: parent,
                 tags: ["highlight"], anchor: NoteAnchor(quote: "new quote", block: 1, offset: 0)),
            Note(text: "Explain: x\n\nAn answer.", section: "Inbox", modifiedAt: saved.addingTimeInterval(60), parent: parent, tags: ["question"])
        ]
        let update = try XCTUnwrap(ArticleMarkdown.update(children: children, after: saved, date: saved))
        XCTAssertTrue(update.hasPrefix("\n## Added "))
        XCTAssertTrue(update.hasSuffix("\n\n> new quote\n\nMy note.\n"), update)
        XCTAssertFalse(update.contains("old quote"))
        XCTAssertFalse(update.contains("An answer."))
    }

    func testAFileNameHasAtMostEightWords() {
        XCTAssertEqual(ArticleMarkdown.fileName(for: "one two three four five six seven eight nine ten"),
                       "one-two-three-four-five-six-seven-eight.md")
        XCTAssertEqual(ArticleMarkdown.fileName(for: "  SQLite: WAL & Café  "), "sqlite-wal-café.md")
        XCTAssertEqual(ArticleMarkdown.fileName(for: ""), "article.md")
    }
}
