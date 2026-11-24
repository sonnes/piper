import AppKit
import XCTest
@testable import Piper
import PiperCore
import Captures
import CapturesDatabase
import Vault

final class WikiEditingTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("piper-edit-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    // MARK: Saving

    @MainActor private func makeModel(_ files: [(String, String)]) throws -> AppModel {
        for (path, raw) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(raw.utf8).write(to: url)
        }
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent("captures.sqlite")), wikiPath: root.path, preferences: temporaryDefaults())
        model.library.files = files.map { makeFile($0.1, path: $0.0) }
        return model
    }

    private func disk(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func write(_ text: String, to path: String) throws {
        try Data(text.utf8).write(to: root.appendingPathComponent(path))
    }

    @MainActor private func settle(_ model: AppModel) async throws {
        try await waitFor("The scan finishes.") { !model.library.loading }
    }

    func testDiskChangeClassification() {
        XCTAssertEqual(DiskChange.classify(baseline: "a", editor: "b", disk: "a"), .unchanged)
        XCTAssertEqual(DiskChange.classify(baseline: "a", editor: "b", disk: "b"), .match)
        XCTAssertEqual(DiskChange.classify(baseline: "a", editor: "a", disk: "c"), .clean)
        XCTAssertEqual(DiskChange.classify(baseline: "a", editor: "b", disk: "c"), .conflict)
        XCTAssertEqual(DiskChange.classify(baseline: "a", editor: "a", disk: nil), .clean)
        XCTAssertEqual(DiskChange.classify(baseline: "a", editor: "b", disk: nil), .conflict)
    }

    @MainActor func testSamePageAnchorKeepsTheSession() throws {
        let model = try makeModel([("Note.md", "# Note\n\n## Details\nOriginal.\n")])
        model.files.openDocument("Note.md")
        let session = model.files.editor
        XCTAssertNotNil(session)
        model.files.openDocument("Note.md", anchor: "details")
        XCTAssertTrue(model.files.editor === session)
        XCTAssertEqual(model.files.requestedAnchor, "details")
    }

    @MainActor func testAnEditSavesTheWholeTextAndLeavesOtherFilesAlone() throws {
        let raw = "---\r\n# Keep this comment\r\ntitle: 'Tea 🍵'\r\n---\r\n\r\n# Tea\r\n\r\nOriginal.\r\n"
        let model = try makeModel([("Tea.md", raw), ("Other.md", "untouched")])
        model.files.openDocument("Tea.md")
        let edited = raw.replacingOccurrences(of: "Original.", with: "Updated **text** and [[Other|other note]].")
        model.files.editorChanged(path: "Tea.md", text: edited)
        XCTAssertEqual(try disk("Tea.md"), edited)
        XCTAssertEqual(try disk("Other.md"), "untouched")
        XCTAssertEqual(model.files.editor?.status, .saved)
        XCTAssertFalse(try XCTUnwrap(model.files.editor).hasChanges)
        XCTAssertEqual(model.library.files.first { $0.id == "Tea.md" }?.raw, edited)
    }

    @MainActor func testAChangeOnDiskStopsSavesUntilTheReaderChooses() throws {
        let model = try makeModel([("Note.md", "# Original\n")])
        model.files.openDocument("Note.md")
        try write("# External edit\n", to: "Note.md")
        model.files.editorChanged(path: "Note.md", text: "# My edit\n")
        XCTAssertEqual(model.files.editor?.status, .conflict)
        XCTAssertEqual(try disk("Note.md"), "# External edit\n")
        model.files.editorChanged(path: "Note.md", text: "# My newer edit\n")
        XCTAssertEqual(try disk("Note.md"), "# External edit\n", "A conflict blocks each save")

        model.files.keepEditorText()
        XCTAssertEqual(try disk("Note.md"), "# My newer edit\n")
        XCTAssertEqual(model.files.editor?.status, .saved)
    }

    @MainActor func testReloadDropsTheEditsAndLoadsTheDisk() throws {
        let model = try makeModel([("Note.md", "# Original\n")])
        model.files.openDocument("Note.md")
        let session = try XCTUnwrap(model.files.editor)
        try write("# External edit\n", to: "Note.md")
        model.files.editorChanged(path: "Note.md", text: "# My edit\n")
        let revision = session.revision
        model.files.reloadEditorFromDisk()
        XCTAssertEqual(session.text, "# External edit\n")
        XCTAssertEqual(session.revision, revision + 1, "The page loads the disk text")
        XCTAssertEqual(session.status, .opened)
        XCTAssertEqual(try disk("Note.md"), "# External edit\n")
    }

    @MainActor func testADeletedFileWithEditsIsAConflict() throws {
        let model = try makeModel([("Note.md", "# Original\n")])
        model.files.openDocument("Note.md")
        try FileManager.default.removeItem(at: root.appendingPathComponent("Note.md"))
        model.files.editorChanged(path: "Note.md", text: "# My edit\n")
        XCTAssertEqual(model.files.editor?.status, .conflict)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Note.md").path))
        model.files.keepEditorText()
        XCTAssertEqual(try disk("Note.md"), "# My edit\n")
    }

    /// The page saves the last edit of a file after it opens the next file.
    @MainActor func testTheLastEditOfAClosedFileStillSaves() throws {
        let model = try makeModel([("First.md", "# First\n"), ("Second.md", "# Second\n")])
        model.files.openDocument("First.md")
        model.files.editors["First.md"]?.text = "# First, edited\n"
        model.files.openDocument("Second.md")
        XCTAssertNotNil(model.files.editors["First.md"], "A session with edits stays until it saves")
        model.files.editorChanged(path: "First.md", text: "# First, edited\n")
        XCTAssertEqual(try disk("First.md"), "# First, edited\n")
        XCTAssertNil(model.files.editors["First.md"], "A saved session of a closed file goes away")
        XCTAssertEqual(model.files.selectedDocument, "Second.md")
    }

    @MainActor func testRefreshLoadsADiskChangeIntoACleanEditor() async throws {
        let model = try makeModel([("Note.md", "# Note\n")])
        model.files.openDocument("Note.md")
        let session = try XCTUnwrap(model.files.editor)
        model.library.reload()
        try await settle(model)
        XCTAssertTrue(model.files.editor === session)
        XCTAssertEqual(session.revision, 0)
        try write("# External update\n", to: "Note.md")
        model.library.reload()
        try await settle(model)
        XCTAssertEqual(session.text, "# External update\n")
        XCTAssertEqual(session.revision, 1)
        XCTAssertEqual(session.status, .opened)
    }

    @MainActor func testRefreshAfterAnOwnSaveIsNotAConflict() async throws {
        let model = try makeModel([("Note.md", "# Note\n")])
        model.files.openDocument("Note.md")
        model.files.editorChanged(path: "Note.md", text: "# Note\nMore.\n")
        model.library.reload()
        try await settle(model)
        XCTAssertEqual(model.files.editor?.status, .saved)
        XCTAssertEqual(model.files.editor?.revision, 0)
    }

    @MainActor func testRefreshMarksAConflictWhenTheEditorHasEdits() async throws {
        let model = try makeModel([("Note.md", "# Note\n")])
        model.files.openDocument("Note.md")
        model.files.editors["Note.md"]?.text = "# Note\nUnsent edit.\n"
        try write("# Agent edit\n", to: "Note.md")
        model.library.reload()
        try await settle(model)
        XCTAssertEqual(model.files.editor?.status, .conflict)
        XCTAssertEqual(model.files.editor?.text, "# Note\nUnsent edit.\n")
    }

    @MainActor func testSettlingSavesEditsAndStopsOnAConflict() throws {
        let model = try makeModel([("First.md", "# First\n"), ("Second.md", "# Second\n")])
        model.files.openDocument("First.md")
        model.files.editors["First.md"]?.text = "# First, edited\n"
        XCTAssertTrue(model.files.settleEditors())
        XCTAssertEqual(try disk("First.md"), "# First, edited\n")

        model.files.openDocument("Second.md")
        model.files.openDocument("First.md")
        model.files.editors["First.md"]?.text = "# Mine\n"
        model.files.openDocument("Second.md")
        try write("# Theirs\n", to: "First.md")
        XCTAssertFalse(model.files.settleEditors())
        XCTAssertEqual(model.files.selectedDocument, "First.md", "Piper shows the file that needs a choice")
        XCTAssertEqual(try disk("First.md"), "# Theirs\n")
        XCTAssertEqual(model.messages.last?.isError, true)
    }

    @MainActor func testAPastedImageGoesNextToTheNote() throws {
        let model = try makeModel([("notes/Tea time.md", "# Tea\n")])
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        let path = try model.files.saveEditorImage(for: "notes/Tea time.md", type: "image/png", base64: png.base64EncodedString())
        XCTAssertTrue(path.hasPrefix("Tea%20time.assets/"), path)
        XCTAssertTrue(path.hasSuffix(".png"))
        let file = root.appendingPathComponent("notes").appendingPathComponent(path.removingPercentEncoding ?? path)
        XCTAssertEqual(try Data(contentsOf: file), png)
        XCTAssertEqual(try model.files.saveEditorImage(for: "notes/Tea time.md", type: "image/png", base64: png.base64EncodedString()), path,
                       "The same image gets the same name")
        XCTAssertThrowsError(try model.files.saveEditorImage(for: "notes/Tea time.md", type: "image/png", base64: ""))
    }

    func testTheAssetSchemeServesOnlyFilesOfTheFolder() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("img"), withIntermediateDirectories: true)
        try Data("png".utf8).write(to: root.appendingPathComponent("img/a b.png"))
        try Data("<p>app</p>".utf8).write(to: root.appendingPathComponent("app.html"))
        let vault = Vault(path: root.path)
        let (data, type) = try AssetSchemeHandler.load(URL(string: "piper-asset://folder/img/a%20b.png")!, from: vault)
        XCTAssertEqual(data, Data("png".utf8))
        XCTAssertEqual(type, "image/png")
        XCTAssertEqual(try AssetSchemeHandler.load(URL(string: "piper-asset://folder/app.html")!, from: vault).1, "text/html")
        XCTAssertThrowsError(try AssetSchemeHandler.load(URL(string: "piper-asset://folder/../secret.txt")!, from: vault))
        XCTAssertThrowsError(try AssetSchemeHandler.load(URL(string: "piper-asset://folder/")!, from: vault))
    }
}
