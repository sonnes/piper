import AppKit
import Captures
import Vault
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
        AppModel(databaseURL: root.appendingPathComponent(".captures.sqlite"), wikiPath: root.path, preferences: temporaryDefaults())
    }

    func testChangesInNestedFoldersRefreshWithoutManualReload() async throws {
        let model = makeModel()
        model.library.reload()
        try await waitFor("The initial scan finishes.") { !model.library.loading }

        let folder = root.appendingPathComponent("notes/nested")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await waitFor("The empty folder appears.") { model.library.folders.contains("notes/nested") }

        let url = folder.appendingPathComponent("note.md")
        try Data("# Original\n".utf8).write(to: url)
        try await waitFor("The new file appears.") { model.library.files.contains { $0.id == "notes/nested/note.md" } }
        model.files.openDocument("notes/nested/note.md")

        try Data("# Updated\n".utf8).write(to: url, options: .atomic)
        try await waitFor("The open document updates.") { model.files.editor?.text == "# Updated\n" }

        let renamed = root.appendingPathComponent("renamed")
        try FileManager.default.moveItem(at: root.appendingPathComponent("notes"), to: renamed)
        try await waitFor("The folder move updates its descendants.") {
            model.library.folders.contains("renamed/nested") && !model.library.folders.contains("notes") &&
                model.library.files.map(\.id) == ["renamed/nested/note.md"]
        }
        try FileManager.default.removeItem(at: renamed)
        try await waitFor("The removed folder and its file disappear.") { model.library.files.isEmpty && model.library.folders.isEmpty }
        XCTAssertNil(model.files.currentDocument)
    }

    func testVisibilityChangesRefreshTheFolders() async throws {
        var folder = root.appendingPathComponent("raw")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isHidden = true
        try folder.setResourceValues(values)
        let model = makeModel()
        model.library.reload()
        try await waitFor("The initial scan finishes.") { !model.library.loading }
        XCTAssertFalse(model.library.folders.contains("raw"))

        values.isHidden = false
        try folder.setResourceValues(values)
        try await waitFor("The unhidden folder appears.") { model.library.folders.contains("raw") }
        values.isHidden = true
        try folder.setResourceValues(values)
        try await waitFor("The hidden folder disappears.") { !model.library.folders.contains("raw") }
    }

    func testRefreshPreservesDraftWhenTheFileChangesOrDisappears() async throws {
        let url = root.appendingPathComponent("note.md")
        try Data("# Original\n".utf8).write(to: url)
        let model = makeModel()
        model.library.reload()
        try await waitFor("The editor opens.") { model.files.editor != nil && !model.library.loading }
        let edit = try XCTUnwrap(model.files.editor)
        edit.text = "# Unsaved draft\n"

        try Data("# External change\n".utf8).write(to: url, options: .atomic)
        try Data("New file\n".utf8).write(to: root.appendingPathComponent("other.txt"))
        try await waitFor("Other changes appear while the draft stays open.") {
            model.library.files.count == 2 && model.library.files.first { $0.id == "note.md" }?.text == "# External change\n"
        }
        XCTAssertTrue(model.files.editor === edit)
        XCTAssertEqual(edit.text, "# Unsaved draft\n")
        XCTAssertEqual(edit.status, .conflict)
        XCTAssertFalse(model.files.saveEditor(edit))
        XCTAssertEqual(try String(contentsOf: url), "# External change\n")

        try FileManager.default.removeItem(at: url)
        try await waitFor("The removed file leaves the list.") { !model.library.files.contains { $0.id == "note.md" } }
        XCTAssertEqual(model.files.currentDocument?.id, "note.md")
        XCTAssertTrue(model.files.editor === edit)
        XCTAssertEqual(edit.text, "# Unsaved draft\n")
        model.files.openDocument("other.txt")
        XCTAssertEqual(model.files.currentDocument?.id, "other.txt")
        XCTAssertTrue(model.files.editors["note.md"] === edit, "The draft stays until the reader chooses")
    }

    func testChangingRootsDuringAScanStartsWatchingTheNewRoot() async throws {
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        for folder in [first, second] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(folder.lastPathComponent.utf8).write(to: folder.appendingPathComponent("value.txt"))
        }
        let model = AppModel(databaseURL: root.appendingPathComponent(".captures.sqlite"), wikiPath: first.path, preferences: temporaryDefaults())
        model.library.reload()
        XCTAssertTrue(model.library.loading)
        model.library.changeWiki(to: second.path)
        try await waitFor("The scan uses the new root.") { !model.library.loading && model.library.files.first?.text == "second" }
        try Data("New root update".utf8).write(to: second.appendingPathComponent("value.txt"), options: .atomic)
        try await waitFor("The watcher follows the new root.") { model.library.files.first?.text == "New root update" }
        XCTAssertEqual(model.library.files.map(\.id), ["value.txt"])
    }

    func testChangingTheFolderScansItOnce() async throws {
        let next = root.appendingPathComponent("next")
        try FileManager.default.createDirectory(at: next, withIntermediateDirectories: true)
        try Data("# Next\n".utf8).write(to: next.appendingPathComponent("next.md"))
        let library = Library(wikiPath: root.path, preferences: temporaryDefaults(), skills: SkillFolders(preferences: temporaryDefaults()))
        let scans = ScanCounter()
        library.delegate = scans
        library.start()
        try await waitFor("The first scan finishes.") { scans.count > 0 && !library.loading }
        // The watcher can report the files that the test just wrote, after its latency.
        try await Task.sleep(for: .seconds(1))
        try await waitFor("The scans settle.") { !library.loading }
        let before = scans.count

        library.changeWiki(to: next.path)
        try await waitFor("The scan of the new folder finishes.") { scans.count > before && !library.loading }
        XCTAssertEqual(scans.count, before + 1)
        XCTAssertEqual(library.files.map(\.id), ["next.md"])
    }

    func testFailedScanKeepsItsMessageForTheFolderTree() async throws {
        let missing = root.appendingPathComponent("missing")
        let model = AppModel(databaseURL: root.appendingPathComponent(".captures.sqlite"), wikiPath: missing.path, preferences: temporaryDefaults())
        model.library.reload()
        try await waitFor("The scan finishes.") { !model.library.loading }
        XCTAssertEqual(model.library.scanError, "The folder is unavailable. Make sure that it exists, or remove its tab and add the folder again.")
        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)
        model.library.reload()
        try await waitFor("The second scan finishes.") { !model.library.loading && model.library.scanError == nil }
    }

    func testChangingWikiResetsTheOldDocumentAndSearch() async throws {
        try Data("# Old\n".utf8).write(to: root.appendingPathComponent("old.md"))
        let folder = root.appendingPathComponent("next")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("# New\n".utf8).write(to: folder.appendingPathComponent("new.md"))
        let model = makeModel()
        model.library.reload()
        try await waitFor("The initial scan finishes.") { !model.library.loading }
        model.files.openDocument("old.md")
        model.files.initialDocument = "old.md"
        model.library.changeWiki(to: folder.path)
        XCTAssertNil(model.files.selectedDocument, "The old file closes before the scan.")
        try await waitFor("The new folder scan finishes.") { !model.library.loading }
        XCTAssertEqual(model.files.selectedDocument, "new.md")
        XCTAssertEqual(model.library.files.map(\.id), ["new.md"])
        XCTAssertNil(model.files.initialDocument)
    }

    func testChangingWikiSavesAnEditFirst() async throws {
        let url = root.appendingPathComponent("old.md")
        try Data("# Old\n".utf8).write(to: url)
        let model = makeModel()
        model.library.reload()
        try await waitFor("The initial scan finishes.") { !model.library.loading }
        model.files.editor?.text += "QA draft"
        model.library.changeWiki(to: root.appendingPathComponent("next").path)
        XCTAssertEqual(model.library.wikiPath, root.appendingPathComponent("next").path)
        XCTAssertEqual(try String(contentsOf: url), "# Old\nQA draft")
    }

    func testChangingWikiStopsWhenAnEditHasAConflict() async throws {
        let url = root.appendingPathComponent("old.md")
        try Data("# Old\n".utf8).write(to: url)
        let model = makeModel()
        model.library.reload()
        try await waitFor("The initial scan finishes.") { !model.library.loading }
        let session = try XCTUnwrap(model.files.editor)
        session.text += "QA draft"
        try Data("# Agent edit\n".utf8).write(to: url)
        model.library.changeWiki(to: root.appendingPathComponent("next").path)
        XCTAssertEqual(model.library.wikiPath, root.path)
        XCTAssertTrue(model.files.editor === session)
        XCTAssertTrue(session.hasChanges)
        XCTAssertEqual(try String(contentsOf: url), "# Agent edit\n")
    }
}

/// Counts the scans of a library.
@MainActor
private final class ScanCounter: LibraryDelegate {
    private(set) var count = 0

    func librarySettle(_ library: Library) -> Bool { true }
    func libraryDidChangeFolder(_ library: Library) {}
    func library(_ library: Library, didScan previous: [VaultFile]) { count += 1 }
}
