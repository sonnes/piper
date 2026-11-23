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
            if !model.loading { return }
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
        XCTAssertEqual(model.wikiPaths, [first.path])
        model.addWikiFolders([second.path, third.path, second.path])
        try await waitForScan(model)
        XCTAssertEqual(model.wikiPaths, [first.path, second.path, third.path])
        XCTAssertEqual(model.currentDocument?.raw, "second")
        model.changeWiki(to: first.path)
        try await waitForScan(model)
        XCTAssertEqual(model.currentDocument?.raw, "first")
        let restored = makeModel()
        XCTAssertEqual(restored.wikiPaths, model.wikiPaths)
        XCTAssertEqual(restored.wikiPath, first.path)
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
        model.addWikiFolders([second.path])
        try await waitForScan(model)
        XCTAssertEqual(model.wikiPath, second.path)

        model.removeWikiFolder(second.path)
        try await waitForScan(model)
        XCTAssertEqual(model.wikiPaths, [first.path])
        XCTAssertEqual(model.wikiPath, first.path)
        XCTAssertEqual(model.currentDocument?.raw, "first")
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.appendingPathComponent("same.md").path))

        model.removeWikiFolder(first.path)
        XCTAssertEqual(model.wikiPaths, [first.path], "The last folder stays")
        XCTAssertEqual(makeModel().wikiPaths, [first.path])
    }

    func testAddingAnAliasDoesNotDuplicateAFolder() async throws {
        preferences.set(root.path, forKey: AppDefaults.Key.vaultPath)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        let model = makeModel()
        model.addWikiFolders([alias.path, root.path])
        try await waitForScan(model)
        XCTAssertEqual(model.wikiPaths, [root.path])
        XCTAssertEqual(model.wikiPath, root.path)
    }

    func testOpeningARunFileWorksInAFolderBehindASymbolicLink() async throws {
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("# Run\n".utf8).write(to: target.appendingPathComponent("run.md"))
        let folder = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: target)
        preferences.set(root.path, forKey: AppDefaults.Key.vaultPath)
        let model = makeModel()
        var shown: [String] = []
        model.showFile = { shown.append($0) }

        model.openRunFile("run.md", in: folder.path)
        for _ in 0..<400 where model.selectedDocument != "run.md" {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.wikiPath, folder.path)
        XCTAssertEqual(model.selectedDocument, "run.md")
        XCTAssertEqual(shown, ["run.md"])
    }

    func testAConflictKeepsTheDraftAndFolderList() async throws {
        preferences.set(root.path, forKey: AppDefaults.Key.vaultPath)
        try Data("# Original".utf8).write(to: root.appendingPathComponent("note.md"))
        let model = makeModel()
        model.reload()
        try await waitForScan(model)
        model.openDocument("note.md")
        let edit = try XCTUnwrap(model.editor)
        edit.text = "# Unsaved"
        try Data("# Agent edit".utf8).write(to: root.appendingPathComponent("note.md"))
        model.addWikiFolders([root.appendingPathComponent("next").path])
        XCTAssertEqual(model.wikiPaths, [root.path])
        XCTAssertEqual(model.wikiPath, root.path)
        XCTAssertTrue(model.editor === edit)
        XCTAssertTrue(edit.hasChanges)
        XCTAssertNil(preferences.array(forKey: AppDefaults.Key.wikiPaths))
    }
}
