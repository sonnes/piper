import AppKit
import Captures
import XCTest
@testable import Piper

@MainActor
final class WikiFoldersTests: XCTestCase {
    private var root: URL!
    private var preferences: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "WikiFoldersTests." + UUID().uuidString
        preferences = UserDefaults(suiteName: suite)!
    }

    override func tearDown() async throws {
        preferences.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: root)
    }

    private func makeModel() -> AppModel {
        AppModel(store: CaptureStore(url: root.appendingPathComponent(".captures.sqlite")), preferences: preferences)
    }

    private func waitForScan(_ model: AppModel) async throws {
        for _ in 0..<400 {
            if !model.library.loading { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("The folder scan did not finish.")
    }

    func testAddsFoldersAndRestoresTheListAndActiveFolder() async throws {
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        let third = root.appendingPathComponent("third")
        for folder in [first, second, third] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(folder.lastPathComponent.utf8).write(to: folder.appendingPathComponent("same.md"))
        }
        preferences.set(first.path, forKey: AppDefaults.Key.vaultPath)
        let model = makeModel()
        XCTAssertEqual(model.library.wikiPaths, [first.path])
        model.library.addWikiFolders([second.path, third.path, second.path])
        try await waitForScan(model)
        XCTAssertEqual(model.library.wikiPaths, [first.path, second.path, third.path])
        XCTAssertEqual(model.files.currentDocument?.raw, "second")
        model.library.changeWiki(to: first.path)
        try await waitForScan(model)
        XCTAssertEqual(model.files.currentDocument?.raw, "first")
        let restored = makeModel()
        XCTAssertEqual(restored.library.wikiPaths, model.library.wikiPaths)
        XCTAssertEqual(restored.library.wikiPath, first.path)
    }

    func testRemovingAFolderKeepsItOnDiskAndMovesOffTheActiveFolder() async throws {
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        for folder in [first, second] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(folder.lastPathComponent.utf8).write(to: folder.appendingPathComponent("same.md"))
        }
        preferences.set(first.path, forKey: AppDefaults.Key.vaultPath)
        let model = makeModel()
        model.library.addWikiFolders([second.path])
        try await waitForScan(model)
        XCTAssertEqual(model.library.wikiPath, second.path)

        model.library.removeWikiFolder(second.path)
        try await waitForScan(model)
        XCTAssertEqual(model.library.wikiPaths, [first.path])
        XCTAssertEqual(model.library.wikiPath, first.path)
        XCTAssertEqual(model.files.currentDocument?.raw, "first")
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.appendingPathComponent("same.md").path))

        model.library.removeWikiFolder(first.path)
        XCTAssertEqual(model.library.wikiPaths, [first.path], "The last folder stays")
        XCTAssertEqual(makeModel().library.wikiPaths, [first.path])
    }

    func testAddingAnAliasDoesNotDuplicateAFolder() async throws {
        preferences.set(root.path, forKey: AppDefaults.Key.vaultPath)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        let model = makeModel()
        model.library.addWikiFolders([alias.path, root.path])
        try await waitForScan(model)
        XCTAssertEqual(model.library.wikiPaths, [root.path])
        XCTAssertEqual(model.library.wikiPath, root.path)
    }

    func testOpeningARunFileWorksInAFolderBehindASymbolicLink() async throws {
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("# Run\n".utf8).write(to: target.appendingPathComponent("run.md"))
        let folder = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: target)
        preferences.set(root.path, forKey: AppDefaults.Key.vaultPath)
        let model = makeModel()
        let desk = PaperDesk(model: model, defaults: preferences)
        defer { desk.hide() }

        model.files.openRunFile("run.md", in: folder.path)
        for _ in 0..<400 where model.files.selectedDocument != "run.md" {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.library.wikiPath, folder.path)
        XCTAssertEqual(model.files.selectedDocument, "run.md")
        XCTAssertTrue(desk.paper.marks.isOpenFile("run.md"))
    }

    func testAConflictKeepsTheDraftAndFolderList() async throws {
        preferences.set(root.path, forKey: AppDefaults.Key.vaultPath)
        try Data("# Original".utf8).write(to: root.appendingPathComponent("note.md"))
        let model = makeModel()
        model.library.reload()
        try await waitForScan(model)
        model.files.openDocument("note.md")
        let edit = try XCTUnwrap(model.files.editor)
        edit.text = "# Unsaved"
        try Data("# Agent edit".utf8).write(to: root.appendingPathComponent("note.md"))
        model.library.addWikiFolders([root.appendingPathComponent("next").path])
        XCTAssertEqual(model.library.wikiPaths, [root.path])
        XCTAssertEqual(model.library.wikiPath, root.path)
        XCTAssertTrue(model.files.editor === edit)
        XCTAssertTrue(edit.hasChanges)
        XCTAssertNil(preferences.array(forKey: AppDefaults.Key.wikiPaths))
    }
}
