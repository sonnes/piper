import AppKit
import Captures
import XCTest
@testable import Piper

@MainActor
final class WikiRefreshTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("piper-refresh-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try FileManager.default.removeItem(at: root) }

    private func makeModel() -> AppModel {
        AppModel(store: CaptureStore(url: root.appendingPathComponent(".captures.sqlite")), wikiPath: root.path)
    }

    private func waitFor(_ description: String, file: StaticString = #filePath, line: UInt = #line,
                         until condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail(description, file: file, line: line)
    }

    func testChangesInNestedFoldersRefreshWithoutManualReload() async throws {
        let model = makeModel()
        model.reload()
        try await waitFor("The initial scan finishes.") { !model.loading }

        let folder = root.appendingPathComponent("notes/nested")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await waitFor("The empty folder appears.") { model.folders.contains("notes/nested") }

        let url = folder.appendingPathComponent("note.md")
        try Data("# Original\n".utf8).write(to: url)
        try await waitFor("The new file appears.") { model.files.contains { $0.id == "notes/nested/note.md" } }
        model.openDocument("notes/nested/note.md")
        XCTAssertFalse(model.isUnread(try XCTUnwrap(model.currentDocument)))

        try Data("# Updated\n".utf8).write(to: url, options: .atomic)
        try await waitFor("The open document updates.") { model.wikiEdit?.markdown == "# Updated\n" }
        XCTAssertTrue(model.isUnread(try XCTUnwrap(model.currentDocument)))

        let renamed = root.appendingPathComponent("renamed")
        try FileManager.default.moveItem(at: root.appendingPathComponent("notes"), to: renamed)
        try await waitFor("The folder move updates its descendants.") {
            model.folders.contains("renamed/nested") && !model.folders.contains("notes") &&
                model.files.map(\.id) == ["renamed/nested/note.md"]
        }
        try FileManager.default.removeItem(at: renamed)
        try await waitFor("The removed folder and its file disappear.") { model.files.isEmpty && model.folders.isEmpty }
        XCTAssertNil(model.currentDocument)
    }

    func testVisibilityChangesRefreshTheSidebarFolders() async throws {
        var folder = root.appendingPathComponent("raw")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isHidden = true
        try folder.setResourceValues(values)
        let model = makeModel()
        model.reload()
        try await waitFor("The initial scan finishes.") { !model.loading }
        XCTAssertFalse(model.folders.contains("raw"))

        values.isHidden = false
        try folder.setResourceValues(values)
        try await waitFor("The unhidden folder appears.") { model.folders.contains("raw") }
        values.isHidden = true
        try folder.setResourceValues(values)
        try await waitFor("The hidden folder disappears.") { !model.folders.contains("raw") }
    }

    func testRefreshPreservesDraftWhenTheFileChangesOrDisappears() async throws {
        let url = root.appendingPathComponent("note.md")
        try Data("# Original\n".utf8).write(to: url)
        let model = makeModel()
        model.reload()
        try await waitFor("The editor opens.") { model.wikiEdit != nil && !model.loading }
        let edit = try XCTUnwrap(model.wikiEdit)
        edit.text = "# Unsaved draft\n"
        var prompts = 0
        model.confirmWikiChanges = { _ in prompts += 1; return .alertSecondButtonReturn }

        try Data("# External change\n".utf8).write(to: url, options: .atomic)
        try Data("New file\n".utf8).write(to: root.appendingPathComponent("other.txt"))
        try await waitFor("Other changes appear while the draft stays open.") {
            model.files.count == 2 && model.files.first { $0.id == "note.md" }?.raw == "# External change\n"
        }
        XCTAssertTrue(model.wikiEdit === edit)
        XCTAssertEqual(edit.markdown, "# Unsaved draft\n")
        XCTAssertFalse(model.saveWikiEdit())
        XCTAssertEqual(try String(contentsOf: url), "# External change\n")

        try FileManager.default.removeItem(at: url)
        try await waitFor("The removed file leaves the list.") { !model.files.contains { $0.id == "note.md" } }
        XCTAssertEqual(model.currentDocument?.id, "note.md")
        XCTAssertTrue(model.wikiEdit === edit)
        XCTAssertEqual(edit.markdown, "# Unsaved draft\n")
        XCTAssertEqual(prompts, 0)
        model.openDocument("other.txt")
        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(model.currentDocument?.id, "other.txt")
    }

    func testRefreshRequestedDuringExportRunsAfterExport() async throws {
        let model = makeModel()
        model.reload()
        try await waitFor("The initial scan finishes.") { !model.loading }
        model.exporting = true
        try Data("{}".utf8).write(to: root.appendingPathComponent("export.json"))
        model.reload()
        XCTAssertFalse(model.loading)
        XCTAssertTrue(model.files.isEmpty)
        model.exporting = false
        try await waitFor("The deferred scan finds the exported file.") { model.files.map(\.id) == ["export.json"] }
    }

    func testChangingRootsDuringAScanStartsWatchingTheNewRoot() async throws {
        let previous = UserDefaults.standard.object(forKey: "wikiPath")
        defer { UserDefaults.standard.set(previous, forKey: "wikiPath") }
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        for folder in [first, second] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(folder.lastPathComponent.utf8).write(to: folder.appendingPathComponent("value.txt"))
        }
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent(".captures.sqlite")), wikiPath: first.path)
        model.reload()
        XCTAssertTrue(model.loading)
        model.wikiPath = second.path
        try await waitFor("The scan uses the new root.") { !model.loading && model.files.first?.text == "second" }
        try Data("New root update".utf8).write(to: second.appendingPathComponent("value.txt"), options: .atomic)
        try await waitFor("The watcher follows the new root.") { model.files.first?.text == "New root update" }
        XCTAssertEqual(model.files.map(\.id), ["value.txt"])
    }

    func testExportOpensANewFileAfterAnInFlightScan() async throws {
        try Data("# Existing\n".utf8).write(to: root.appendingPathComponent("existing.md"))
        let model = makeModel()
        model.reload()
        try await waitFor("The initial scan finishes.") { !model.loading }
        model.wikiQuery = "Existing"
        model.exportNotes = [Note(text: "QA export", section: "Inbox")]
        model.reload()
        let destination = root.appendingPathComponent("export.md")
        let error = await model.export(title: "Export", sourceURL: "", destination: destination)
        XCTAssertNil(error)
        try await waitFor("The export scan finishes.") { !model.loading }
        XCTAssertEqual(model.selectedDocument, "export.md")
        XCTAssertEqual(model.wikiEdit?.document.id, "export.md")
        XCTAssertEqual(model.exportedDocument, "export.md")
        XCTAssertEqual(model.wikiQuery, "")
        XCTAssertFalse(model.isUnread(try XCTUnwrap(model.currentDocument)))
    }

    func testExportThroughARootAliasOpensTheFile() async throws {
        let alias = root.appendingPathComponent("alias")
        let folder = root.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: folder)
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent(".captures.sqlite")), wikiPath: alias.path)
        model.exportNotes = [Note(text: "QA export", section: "Inbox")]
        let error = await model.export(title: "Export", sourceURL: "", destination: alias.appendingPathComponent("export.md"))
        XCTAssertNil(error)
        try await waitFor("The export scan finishes.") { !model.loading }
        XCTAssertEqual(model.selectedDocument, "export.md")
        XCTAssertFalse(model.isUnread(try XCTUnwrap(model.currentDocument)))
    }

    func testChangingWikiResetsTheOldDocumentAndSearch() async throws {
        let previous = UserDefaults.standard.object(forKey: "wikiPath")
        defer { UserDefaults.standard.set(previous, forKey: "wikiPath") }
        try Data("# Old\n".utf8).write(to: root.appendingPathComponent("old.md"))
        let folder = root.appendingPathComponent("next")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("# New\n".utf8).write(to: folder.appendingPathComponent("new.md"))
        let model = makeModel()
        model.reload()
        try await waitFor("The initial scan finishes.") { !model.loading }
        model.openDocument("old.md")
        model.initialDocument = "old.md"
        model.wikiQuery = "Old"
        let changed = expectation(forNotification: .vaultPathDidChange, object: model)
        model.changeWiki(to: folder)
        await fulfillment(of: [changed], timeout: 1)
        try await waitFor("The new folder scan finishes.") { !model.loading }
        XCTAssertEqual(model.selectedDocument, "new.md")
        XCTAssertEqual(model.files.map(\.id), ["new.md"])
        XCTAssertEqual(model.wikiQuery, "")
        XCTAssertNil(model.initialDocument)
    }

    func testChangingWikiCanCancelAnUnsavedEdit() async throws {
        try Data("# Old\n".utf8).write(to: root.appendingPathComponent("old.md"))
        let model = makeModel()
        model.reload()
        try await waitFor("The initial scan finishes.") { !model.loading }
        model.wikiEdit?.text += "QA draft"
        let session = model.wikiEdit
        model.confirmWikiChanges = { _ in .alertThirdButtonReturn }
        model.changeWiki(to: root.appendingPathComponent("next"))
        XCTAssertEqual(model.wikiPath, root.path)
        XCTAssertTrue(model.wikiEdit === session)
        XCTAssertTrue(try XCTUnwrap(session).hasChanges)
    }

    func testNewVaultResetsFolderStateAndKeepsPaneWidths() {
        var state = MainWindowState()
        state.selection = .folder("sources/prompts")
        state.selectedFile = "sources/prompts/old.md"
        state.expandedFolders = ["sources", "sources/prompts"]
        state.sidebarWidth = 250
        state.listWidth = 300
        state.resetForVault()
        XCTAssertEqual(state.selection, .folder(""))
        XCTAssertNil(state.selectedFile)
        XCTAssertNil(state.expandedFolders)
        XCTAssertEqual(state.sidebarWidth, 250)
        XCTAssertEqual(state.listWidth, 300)
    }

    func testExportOutsideTheVaultKeepsSelectionAndSearch() async throws {
        let folder = root.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("# Existing\n".utf8).write(to: folder.appendingPathComponent("existing.md"))
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent(".captures.sqlite")), wikiPath: folder.path)
        model.reload()
        try await waitFor("The initial scan finishes.") { !model.loading }
        model.wikiQuery = "Existing"
        model.exportNotes = [Note(text: "QA export", section: "Inbox")]
        let destination = root.appendingPathComponent("outside.md")
        let error = await model.export(title: "Export", sourceURL: "", destination: destination)
        XCTAssertNil(error)
        try await waitFor("The export scan finishes.") { !model.loading }
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(model.selectedDocument, "existing.md")
        XCTAssertEqual(model.wikiQuery, "Existing")
    }

    func testExportNavigationCanCancelAnUnsavedEdit() async throws {
        let original = root.appendingPathComponent("existing.md")
        try Data("# Existing\n".utf8).write(to: original)
        let model = makeModel()
        model.reload()
        try await waitFor("The initial scan finishes.") { !model.loading }
        let edit = try XCTUnwrap(model.wikiEdit)
        edit.text += "QA draft"
        model.confirmWikiChanges = { _ in .alertThirdButtonReturn }
        model.exportNotes = [Note(text: "QA export", section: "Inbox")]
        let destination = root.appendingPathComponent("export.md")
        let error = await model.export(title: "Export", sourceURL: "", destination: destination)
        XCTAssertNil(error)
        try await waitFor("The export scan finishes.") { !model.loading }
        XCTAssertEqual(model.selectedDocument, "existing.md")
        XCTAssertTrue(model.wikiEdit === edit)
        XCTAssertTrue(edit.hasChanges)
        XCTAssertNil(model.exportedDocument)
        XCTAssertEqual(try String(contentsOf: original), "# Existing\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }
}
