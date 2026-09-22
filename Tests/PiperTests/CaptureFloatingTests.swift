import AppKit
import Captures
import XCTest
@testable import Piper

@MainActor
final class CaptureFloatingTests: XCTestCase {
    func testFloatingChangesTheExistingPanelAndPersists() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "CaptureFloatingTests." + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = CaptureStore(url: folder.appendingPathComponent("notes.sqlite"))
        let model = AppModel(store: store, wikiPath: folder.path, preferences: preferences)
        let controller = CapturePanelController(model: model)
        let panel = try XCTUnwrap(controller.window as? CapturePanel)
        defer { panel.close() }

        XCTAssertTrue(model.captureFloating)
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertEqual(panel.level, .floating)

        model.captureFloating = false
        XCTAssertFalse(panel.isFloatingPanel)
        XCTAssertEqual(panel.level, .normal)
        XCTAssertEqual(preferences.object(forKey: AppDefaults.Key.captureFloating) as? Bool, false)

        let restored = AppModel(store: store, wikiPath: folder.path, preferences: preferences)
        let restoredController = CapturePanelController(model: restored)
        let restoredPanel = try XCTUnwrap(restoredController.window as? CapturePanel)
        defer { restoredPanel.close() }
        XCTAssertFalse(restored.captureFloating)
        XCTAssertFalse(restoredPanel.isFloatingPanel)
        XCTAssertEqual(restoredPanel.level, .normal)

        model.captureFloating = true
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(preferences.bool(forKey: AppDefaults.Key.captureFloating))
    }
}
