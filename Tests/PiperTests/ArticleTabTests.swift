import Captures
import XCTest
@testable import Piper

final class ArticleTabTests: XCTestCase {
    @MainActor func testLinkCaptureOpensInWebTabUnlessAHighlightOfItWaits() throws {
        let (model, cleanup) = try makeModel()
        defer { cleanup() }
        let article = link("https://example.com/a")
        let other = link("https://example.com/b")

        XCTAssertEqual(model.articleTab, .web)
        XCTAssertEqual(model.openingTab(for: article), .web)

        model.readerScroll = ReaderScroll(block: 4, in: article.id)
        XCTAssertEqual(model.openingTab(for: article), .web)

        let highlight = UUID()
        model.showHighlight(highlight, in: article.id)
        XCTAssertEqual(model.articleTab, .reader)
        XCTAssertEqual(model.readerScroll?.note, highlight)
        XCTAssertEqual(model.openingTab(for: article), .reader)
        XCTAssertEqual(model.openingTab(for: other), .web)
    }

    @MainActor func testEachSiteOpensInTheTabLastChosenForIt() throws {
        let (model, cleanup) = try makeModel()
        defer { cleanup() }
        let blog = URL(string: "https://WWW.Blog.example/post")!

        model.chooseArticleTab(.reader, for: blog)
        XCTAssertEqual(model.articleTab, .reader)
        XCTAssertEqual(model.openingTab(for: link("https://blog.example/other")), .reader)
        XCTAssertEqual(model.openingTab(for: link("https://news.example/story")), .web)

        model.chooseArticleTab(.notes, for: blog)
        XCTAssertEqual(model.articleTab, .notes)
        XCTAssertEqual(model.openingTab(for: link("https://blog.example/other")), .reader)

        let restored = AppModel(store: model.store, wikiPath: model.wikiPath, preferences: preferences)
        XCTAssertEqual(restored.openingTab(for: link("https://blog.example/third")), .reader)

        restored.chooseArticleTab(.web, for: blog)
        XCTAssertEqual(restored.openingTab(for: link("https://blog.example/third")), .web)
    }

    private var preferences: UserDefaults!

    private func link(_ text: String) -> Note { Note(text: text, section: "Inbox") }

    @MainActor private func makeModel() throws -> (AppModel, () -> Void) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "ArticleTabTests." + UUID().uuidString
        preferences = UserDefaults(suiteName: suite)
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent("captures.sqlite")),
                             wikiPath: root.path, preferences: preferences)
        return (model, {
            UserDefaults().removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        })
    }
}
