import Captures
import XCTest
@testable import Piper

final class ArticleTabTests: XCTestCase {
    @MainActor func testLinkCaptureOpensInWebTabUnlessAHighlightOfItWaits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent("captures.sqlite")), wikiPath: root.path)
        let article = UUID()
        let other = UUID()

        XCTAssertEqual(model.articleTab, .web)
        XCTAssertEqual(model.openingTab(for: article), .web)

        model.readerScroll = ReaderScroll(block: 4, in: article)
        XCTAssertEqual(model.openingTab(for: article), .web)

        let highlight = UUID()
        model.showHighlight(highlight, in: article)
        XCTAssertEqual(model.articleTab, .reader)
        XCTAssertEqual(model.readerScroll?.note, highlight)
        XCTAssertEqual(model.openingTab(for: article), .reader)
        XCTAssertEqual(model.openingTab(for: other), .web)
    }
}
