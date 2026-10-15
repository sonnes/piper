import XCTest
@testable import Piper
import Agents
import Captures

@MainActor
final class SessionCardTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("session-card-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    func testCardFitsNarrowPanesAndLeavesTabsBelow() {
        let layout = DetailPaneLayout()
        for width: CGFloat in [384, 500, 640] {
            layout.width = width
            XCTAssertLessThanOrEqual(layout.cardWidth + 2 * AppDefaults.SessionCard.margin, width)
            XCTAssertGreaterThanOrEqual(layout.cardBottomInset, AppDefaults.TabIsland.clearance)
            XCTAssertEqual(layout.tabsTrailingInset, 0)
        }
        layout.width = 900
        XCTAssertEqual(layout.cardWidth, AppDefaults.SessionCard.width)
        XCTAssertEqual(layout.cardBottomInset, 0)
        XCTAssertGreaterThanOrEqual(layout.width - layout.tabsTrailingInset, AppDefaults.SessionCard.tabsMinimumWidth)
    }

    func testTheCardFollowsTheOpenNote() {
        let model = AppModel(store: CaptureStore(url: folder.appendingPathComponent("notes.sqlite")), wikiPath: folder.path)
        let runner = model.agents.runner
        let first = UUID(), second = UUID()
        let older = runner.newSession(in: folder.path, noteID: first)
        let margin = runner.newSession(in: folder.path, noteID: first, purpose: .margin)
        let newer = runner.newSession(in: folder.path, noteID: first)
        XCTAssertNotNil(margin)

        model.actionTarget = .text("https://a.dev", noteID: first)
        XCTAssertEqual(SessionTarget(model: model).session?.id, newer.id)
        XCTAssertEqual(Set(SessionTarget(model: model).noteSessions.map(\.id)), [older.id, newer.id])

        model.selectedSession = older.id
        XCTAssertEqual(SessionTarget(model: model).session?.id, older.id)

        // Another note without a session shows an empty card, even with a
        // session of the first note still selected.
        model.actionTarget = .text("A note", noteID: second)
        XCTAssertNil(SessionTarget(model: model).session)

        // New Session clears the card of a note that has sessions.
        model.actionTarget = .text("https://a.dev", noteID: first)
        model.selectedSession = nil
        model.newSessionNote = first
        XCTAssertNil(SessionTarget(model: model).session)
    }
}
