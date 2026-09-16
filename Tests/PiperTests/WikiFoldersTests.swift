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
        model.addWikiFolders([second, third, second])
        try await waitForScan(model)
        XCTAssertEqual(model.wikiPaths, [first.path, second.path, third.path])
        XCTAssertEqual(model.currentDocument?.raw, "second")
        model.changeWiki(to: first)
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
        model.addWikiFolders([second])
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
        model.addWikiFolders([alias, root])
        try await waitForScan(model)
        XCTAssertEqual(model.wikiPaths, [root.path])
        XCTAssertEqual(model.wikiPath, root.path)
    }

    func testCancelKeepsTheDraftAndFolderList() async throws {
        preferences.set(root.path, forKey: AppDefaults.Key.vaultPath)
        try Data("# Original".utf8).write(to: root.appendingPathComponent("note.md"))
        let model = makeModel()
        model.reload()
        try await waitForScan(model)
        model.openDocument("note.md")
        let edit = try XCTUnwrap(model.wikiEdit)
        edit.text = "# Unsaved"
        model.confirmWikiChanges = { _ in .alertThirdButtonReturn }
        model.addWikiFolders([root.appendingPathComponent("next")])
        XCTAssertEqual(model.wikiPaths, [root.path])
        XCTAssertEqual(model.wikiPath, root.path)
        XCTAssertTrue(model.wikiEdit === edit)
        XCTAssertTrue(edit.hasChanges)
        XCTAssertNil(preferences.array(forKey: AppDefaults.Key.wikiPaths))
    }
}
