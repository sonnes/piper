import AppKit
import XCTest
@testable import Piper
import PiperCore
import Captures
import CapturesDatabase

/// The quit path, which is the third way an unsaved edit reaches the disk.
///
/// Navigation and window closure already have tests. `applicationShouldTerminate`
/// composes three separate guards, and the refactor splits the code that holds
/// them. These tests fix the order and the result of that composition, so that a
/// later change that drops one guard fails here instead of losing a reader's work.
@MainActor
final class QuitSafetyTests: XCTestCase {

    private var folder: URL!
    private var databaseURL: URL { folder.appendingPathComponent("notes.sqlite") }
    private var wikiPath: String { folder.appendingPathComponent("Wiki").path }

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("piper-quit-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try FileManager.default.removeItem(at: folder) }

    // MARK: Helpers

    /// Repeats the decision that `applicationShouldTerminate` makes.
    ///
    /// The real method also shows a window. The decision itself is what must not
    /// change, so the test drives the same three guards in the same order.
    private func shouldTerminate(_ model: AppModel, resolveCapture: (CaptureEditSession) -> Bool) -> Bool {
        guard !model.agent.isRunning else { return false }
        model.route = "wiki"
        guard !model.exporting else { return false }
        for session in Array(model.captureEdits.values) where !resolveCapture(session) { return false }
        return model.finishWikiEdit()
    }

    /// Waits for the scan that `reload()` starts.
    private func settle(_ model: AppModel) async throws {
        for _ in 0..<100 where model.loading { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.loading)
    }

    private func makeWiki() throws -> AppModel {
        let store = CaptureStore(url: databaseURL)
        let model = AppModel(store: store, wikiPath: wikiPath)
        let root = URL(fileURLWithPath: wikiPath)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("---\ntitle: A note\n---\n\nOriginal body.\n".utf8)
            .write(to: root.appendingPathComponent("note.md"))
        return model
    }

    // MARK: An export in flight

    func testAnExportInFlightBlocksQuit() throws {
        let model = try makeWiki()
        model.exporting = true
        XCTAssertFalse(shouldTerminate(model) { _ in true })
        model.exporting = false
        XCTAssertTrue(shouldTerminate(model) { _ in true })
    }

    // MARK: Capture edits

    func testAnUnresolvedCaptureEditBlocksQuit() {
        let store = CaptureStore(url: databaseURL)
        XCTAssertTrue(store.add("original"))
        let model = AppModel(store: store, wikiPath: wikiPath)
        let session = model.editCapture(store.notes[0])
        session.text = "an unsaved change"

        XCTAssertFalse(shouldTerminate(model) { _ in false })
        XCTAssertEqual(store.notes[0].text, "original", "A cancelled quit must not write the draft")
        XCTAssertTrue(session.hasChanges)
    }

    func testEveryCaptureEditIsOfferedBeforeQuit() {
        let store = CaptureStore(url: databaseURL)
        XCTAssertTrue(store.add("first"))
        XCTAssertTrue(store.add("second"))
        let model = AppModel(store: store, wikiPath: wikiPath)
        for note in store.notes {
            model.editCapture(note).text = note.text + " edited"
        }

        var offered: Set<UUID> = []
        let result = shouldTerminate(model) { session in
            offered.insert(session.id)
            return model.saveCaptureEdit(session)
        }

        XCTAssertTrue(result)
        XCTAssertEqual(offered.count, 2, "Quit must offer every open capture edit, not the first one only")
        XCTAssertEqual(Set(store.notes.map(\.text)), ["first edited", "second edited"])
    }

    // MARK: The open wiki file

    func testCancellingTheWikiPromptBlocksQuitAndKeepsTheDraft() async throws {
        let model = try makeWiki()
        model.reload()
        try await settle(model)
        model.openDocument("note.md")
        guard let edit = model.wikiEdit else { return XCTFail("Opening a file must start an edit session") }
        edit.text = "An unsaved body."

        model.confirmWikiChanges = { _ in .alertThirdButtonReturn }
        XCTAssertFalse(shouldTerminate(model) { _ in true })
        XCTAssertTrue(model.wikiEdit?.hasChanges == true, "Cancel keeps the draft in memory")

        let onDisk = try String(contentsOf: URL(fileURLWithPath: wikiPath).appendingPathComponent("note.md"), encoding: .utf8)
        XCTAssertTrue(onDisk.contains("Original body."), "Cancel must not write the draft")
    }

    func testDiscardingTheWikiPromptAllowsQuitAndLeavesTheFileAlone() async throws {
        let model = try makeWiki()
        model.reload()
        try await settle(model)
        model.openDocument("note.md")
        guard let edit = model.wikiEdit else { return XCTFail("Opening a file must start an edit session") }
        edit.text = "An unsaved body."

        model.confirmWikiChanges = { _ in .alertSecondButtonReturn }
        XCTAssertTrue(shouldTerminate(model) { _ in true })

        let onDisk = try String(contentsOf: URL(fileURLWithPath: wikiPath).appendingPathComponent("note.md"), encoding: .utf8)
        XCTAssertTrue(onDisk.contains("Original body."), "Discard must not write the draft")
    }

    func testAnOpenSheetIsClosedSoTheAlertCanAppear() throws {
        let model = try makeWiki()
        model.route = "commands"
        XCTAssertTrue(shouldTerminate(model) { _ in true })
        XCTAssertEqual(model.route, "wiki", "Quit must close a sheet, or the alert below it never appears")
    }

    func testTheExportGuardRunsBeforeTheEditPrompts() throws {
        let model = try makeWiki()
        model.exporting = true
        var prompted = false
        model.confirmWikiChanges = { _ in prompted = true; return .alertFirstButtonReturn }

        XCTAssertFalse(shouldTerminate(model) { _ in true })
        XCTAssertFalse(prompted, "An export in flight must stop the quit before any prompt appears")
    }
}
