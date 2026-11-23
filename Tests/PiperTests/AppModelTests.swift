import Captures
import XCTest
@testable import Piper

@MainActor
final class AppModelTests: XCTestCase {
    func testPreferencesGoToTheInjectedDefaults() throws {
        let suite = "AppModelTests." + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let keys = [AppDefaults.Key.composerDraft, AppDefaults.Key.showsFileSource,
                    AppDefaults.Key.sessionPresentation, AppDefaults.Key.captureShortcut]
        let before = keys.map { UserDefaults.standard.object(forKey: $0) as? NSObject }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("piper-model-tests-" + UUID().uuidString)
        let model = AppModel(store: CaptureStore(url: folder.appendingPathComponent(".captures.sqlite")),
                             wikiPath: folder.path, preferences: preferences)

        model.composerDraft = "Draft " + suite
        model.files.showsFileSource.toggle()
        model.sessionPresentation = model.sessionPresentation == .card ? .pill : .card
        model.captureShortcut = model.captureShortcut == "Shift, Shift" ? "Control-Option-Space" : "Shift, Shift"

        XCTAssertEqual(keys.map { UserDefaults.standard.object(forKey: $0) as? NSObject }, before)
        XCTAssertEqual(preferences.string(forKey: AppDefaults.Key.composerDraft), "Draft " + suite)
        XCTAssertEqual(preferences.bool(forKey: AppDefaults.Key.showsFileSource), model.files.showsFileSource)
        XCTAssertEqual(preferences.string(forKey: AppDefaults.Key.sessionPresentation), model.sessionPresentation.rawValue)
        XCTAssertEqual(preferences.string(forKey: AppDefaults.Key.captureShortcut), model.captureShortcut)
    }
}
