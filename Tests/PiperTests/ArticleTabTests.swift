import Captures
import XCTest
@testable import Piper

final class ArticleTabTests: XCTestCase {
    @MainActor func testLinkCaptureOpensInWebTabUnlessAHighlightOfItWaits() throws {
        let (model, cleanup) = try makeModel()
        defer { cleanup() }
        let article = link("https://example.com/a")
        let other = link("https://example.com/b")

        XCTAssertEqual(model.articleTabs.tab(for: article), .web)
        XCTAssertEqual(model.articleTabs.openingTab(for: article), .web)

        model.articleTabs.scrollToBlock(4, in: article.id)
        XCTAssertEqual(model.articleTabs.openingTab(for: article), .web)

        let highlight = UUID()
        model.articleTabs.showHighlight(highlight, in: article.id)
        XCTAssertEqual(model.articleTabs.tab(for: article), .reader)
        XCTAssertEqual(model.articleTabs.scroll?.note, highlight)
        XCTAssertEqual(model.articleTabs.openingTab(for: article), .reader)
        XCTAssertEqual(model.articleTabs.openingTab(for: other), .web)
    }

    @MainActor func testEachSiteOpensInTheTabLastChosenForIt() throws {
        let (model, cleanup) = try makeModel()
        defer { cleanup() }
        let blog = URL(string: "https://WWW.Blog.example/post")!

        let post = Note(text: blog.absoluteString, section: "Inbox")
        model.articleTabs.choose(.reader, for: post)
        XCTAssertEqual(model.articleTabs.tab(for: post), .reader)
        XCTAssertEqual(model.articleTabs.openingTab(for: link("https://blog.example/other")), .reader)
        XCTAssertEqual(model.articleTabs.openingTab(for: link("https://news.example/story")), .web)

        model.articleTabs.choose(.notes, for: post)
        XCTAssertEqual(model.articleTabs.tab(for: post), .notes)
        XCTAssertEqual(model.articleTabs.openingTab(for: link("https://blog.example/other")), .reader)

        let restored = AppModel(databaseURL: URL(fileURLWithPath: model.library.wikiPath).appendingPathComponent("captures.sqlite"),
                                wikiPath: model.library.wikiPath, preferences: preferences)
        XCTAssertEqual(restored.articleTabs.openingTab(for: link("https://blog.example/third")), .reader)

        restored.articleTabs.choose(.web, for: post)
        XCTAssertEqual(restored.articleTabs.openingTab(for: link("https://blog.example/third")), .web)
    }

    @MainActor func testEachLinkCaptureKeepsItsOwnTab() throws {
        let (model, cleanup) = try makeModel()
        defer { cleanup() }
        let first = link("https://one.example/a")
        let second = link("https://two.example/b")
        model.articleTabs.keep(for: first)
        model.articleTabs.keep(for: second)

        model.articleTabs.choose(.notes, for: first)

        XCTAssertEqual(model.articleTabs.tab(for: first), .notes)
        XCTAssertEqual(model.articleTabs.tab(for: second), .web)

        model.articleTabs.choose(.reader, for: second)
        XCTAssertEqual(model.articleTabs.tab(for: first), .notes)
        XCTAssertEqual(model.articleTabs.tab(for: second), .reader)
    }

    private var preferences: UserDefaults!

    private func link(_ text: String) -> Note { Note(text: text, section: "Inbox") }

    @MainActor private func makeModel() throws -> (AppModel, () -> Void) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "ArticleTabTests." + UUID().uuidString
        preferences = UserDefaults(suiteName: suite)
        let model = AppModel(databaseURL: root.appendingPathComponent("captures.sqlite"),
                             wikiPath: root.path, preferences: preferences)
        return (model, {
            UserDefaults().removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        })
    }
}
