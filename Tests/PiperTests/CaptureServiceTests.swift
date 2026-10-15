import XCTest
@testable import Piper
import Captures

@MainActor
final class CaptureServiceTests: XCTestCase {

    // MARK: - Properties

    private var folder: URL!
    private let page = URL(string: "https://www.example.dev/notes/wal?utm_source=feed")!
    private let otherPage = URL(string: "https://example.dev/notes/other")!

    // MARK: - Setup

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("capture-service-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    /// A store with one highlight on the page, and the toast that shows it.
    private func highlighted() throws -> (store: CaptureStore, shown: (id: UUID, quote: String)) {
        let store = CaptureStore(url: folder.appendingPathComponent("notes.sqlite"))
        let saved = try XCTUnwrap(store.saveHighlight("one long read", in: page, tags: ["highlight", "yellow"]))
        return (store, (saved.highlight.id, "one long read"))
    }

    private func save(_ text: String, on url: URL?, in store: CaptureStore, shown: (id: UUID, quote: String)?) -> CaptureOutcome {
        CaptureService.save(CapturedSelection(text: text, sourceURL: url?.absoluteString), source: "Safari", section: "Inbox",
                            store: store, shown: shown)
    }

    // MARK: - Tests

    func testASecondCaptureOnTheSamePageAsksForANote() throws {
        let (store, shown) = try highlighted()
        let samePage = URL(string: "https://example.dev/notes/wal#intro")!
        XCTAssertEqual(save("", on: samePage, in: store, shown: shown), .comment(shown.id))
        XCTAssertEqual(save("one  long\nread", on: samePage, in: store, shown: shown), .comment(shown.id))
    }

    func testACaptureOnAnotherPageSavesThatPage() throws {
        let (store, shown) = try highlighted()
        guard case .article(let id, isNew: true) = save("", on: otherPage, in: store, shown: shown) else {
            return XCTFail("A capture with no selection on another page saves the page")
        }
        XCTAssertEqual(store.notes.first { $0.id == id }?.articleURL, otherPage)

        guard case .highlight(let article, _) = save("one long read", on: otherPage, in: store, shown: shown) else {
            return XCTFail("The same text on another page is a new highlight")
        }
        XCTAssertEqual(article, id)
    }

    func testACaptureOutsideABrowserIsANote() throws {
        let (store, shown) = try highlighted()
        guard case .note(_, let id) = save("a plain selection", on: nil, in: store, shown: shown) else {
            return XCTFail("A selection without a page is a note")
        }
        XCTAssertNotNil(id)
        guard case .note(_, nil) = save("", on: nil, in: store, shown: shown) else {
            return XCTFail("An empty selection without a page saves nothing")
        }
    }

    func testWithoutAToastANewSelectionIsAHighlight() throws {
        let (store, _) = try highlighted()
        guard case .highlight = save("another passage", on: page, in: store, shown: nil) else {
            return XCTFail("A selection on a web page is a highlight")
        }
        XCTAssertEqual(store.children(of: try XCTUnwrap(store.article(for: page)).id).count, 2)
    }

    // MARK: - Note Places

    func testNotePlacesAreFoundAgainOnlyAfterAChange() throws {
        let article = ReaderArticle(url: page, site: "example.dev", title: "WAL", byline: [], blocks: [
            ReaderArticle.Block(kind: "paragraph", text: "A reader keeps one long read open."),
            ReaderArticle.Block(kind: "paragraph", text: "The end.")
        ])
        let parent = UUID()
        var highlight = Note(text: "one long read", section: "Inbox", parent: parent, tags: ["highlight"],
                             anchor: NoteAnchor(quote: "one long read", block: -1, offset: 0))
        let places = NotePlaces()

        XCTAssertEqual(places.places(in: article, for: [highlight])[highlight.id], NoteAnchor(quote: "one long read", block: 0, offset: 15))
        _ = places.places(in: article, for: [highlight])
        XCTAssertEqual(places.searches, 1)

        highlight.anchor = NoteAnchor(quote: "The end.", block: -1, offset: 0)
        XCTAssertEqual(places.places(in: article, for: [highlight])[highlight.id], NoteAnchor(quote: "The end.", block: 1, offset: 0))
        XCTAssertEqual(places.searches, 2)
    }
}
