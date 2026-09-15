import AppKit
import Captures
import Vault
import XCTest
@testable import Piper

final class FileReadStateTests: XCTestCase {
    @MainActor func testReadTimestampsPersistAndAnyChangedTimestampIsUnread() throws {
        try withModel { model, defaults in
            let file = VaultFile(relativePath: "data.json", size: 2, modifiedAt: Date(timeIntervalSince1970: 1234.56789), text: "{}")
            XCTAssertTrue(model.isUnread(file))
            model.fileReadState.markRead(file, in: model.vault.root)
            let restored = FileReadState(defaults: defaults)
            XCTAssertFalse(restored.isUnread(file, in: model.vault.root))
            for seconds in [1000.0, 2000.0, Date().timeIntervalSince1970 + 3600] {
                let changed = VaultFile(relativePath: file.id, size: 2, modifiedAt: Date(timeIntervalSince1970: seconds), text: "{}")
                XCTAssertTrue(restored.isUnread(changed, in: model.vault.root))
                restored.markRead(changed, in: model.vault.root)
                XCTAssertFalse(FileReadState(defaults: defaults).isUnread(changed, in: model.vault.root))
            }
        }
    }

    @MainActor func testSameRelativePathHasSeparateStateInEachWiki() throws {
        try withModel { model, _ in
            let file = makeFile("# Note", path: "Note.md")
            let otherRoot = model.vault.root.appendingPathComponent("Other")
            model.fileReadState.markRead(file, in: model.vault.root)
            XCTAssertTrue(model.fileReadState.isUnread(file, in: otherRoot))
            XCTAssertFalse(model.fileReadState.isUnread(file, in: model.vault.root.appendingPathComponent("Sub/..")))
        }
    }

    @MainActor func testUnreadCountsIncludeDescendantsAndIgnoreRemovedFiles() throws {
        try withModel { model, _ in
            let files = [
                makeFile("# Root", path: "root.md"),
                makeFile("{}", path: "a/config.json"),
                VaultFile(relativePath: "a/nested/image.png", size: 8, modifiedAt: Date(), text: nil),
                makeFile("Text", path: "ab/notes.txt")
            ]
            model.files = files
            XCTAssertEqual(model.unreadFolderCounts, ["": 4, "a": 2, "a/nested": 1, "ab": 1])
            model.openDocument(files[2].id)
            XCTAssertFalse(model.isUnread(files[2]))
            XCTAssertEqual(model.unreadFolderCounts, ["": 3, "a": 1, "ab": 1])
            model.files.removeAll { $0.id == files[1].id }
            XCTAssertEqual(model.unreadFolderCounts, ["": 2, "ab": 1])
            model.openDocument(files[0].id)
            model.openDocument(files[3].id)
            XCTAssertTrue(model.unreadFolderCounts.isEmpty)
        }
    }

    @MainActor func testCancelledNavigationLeavesTheTargetUnread() throws {
        try withModel { model, _ in
            let note = makeFile("# Note", path: "Note.md")
            let html = makeFile("<p>Page</p>", path: "page.html")
            model.files = [note, html]
            model.openDocument(note.id)
            model.wikiEdit?.text += " changed"
            model.confirmWikiChanges = { _ in .alertThirdButtonReturn }
            model.openDocument(html.id)
            XCTAssertEqual(model.selectedDocument, note.id)
            XCTAssertTrue(model.isUnread(html))
            model.confirmWikiChanges = { _ in .alertSecondButtonReturn }
            model.openDocument(html.id)
            XCTAssertFalse(model.isUnread(html))
            let changed = VaultFile(relativePath: note.id, size: note.size,
                                    modifiedAt: note.modifiedAt.addingTimeInterval(1), text: note.text)
            model.files[0] = changed
            XCTAssertTrue(model.isUnread(changed))
            model.navigate(-1)
            XCTAssertEqual(model.selectedDocument, note.id)
            XCTAssertFalse(model.isUnread(changed))
        }
    }

    @MainActor func testPreselectionDoesNotMarkAFileReadUntilItIsShown() throws {
        try withModel { model, _ in
            let file = makeFile("Text", path: "notes.txt")
            model.files = [file]
            model.openDocument(file.id, markAsRead: false)
            XCTAssertTrue(model.isUnread(file))
            model.markCurrentDocumentRead()
            XCTAssertFalse(model.isUnread(file))
            let changed = VaultFile(relativePath: file.id, size: 7, modifiedAt: file.modifiedAt.addingTimeInterval(1), text: "Changed")
            model.files = [changed]
            XCTAssertTrue(model.isUnread(changed))
            model.openDocument(changed.id)
            XCTAssertFalse(model.isUnread(changed))
        }
    }

    @MainActor func testSavingOwnEditsKeepsTheSavedVersionRead() throws {
        try withModel { model, defaults in
            let url = model.vault.root.appendingPathComponent("Note.md")
            try "# Note\nOriginal".write(to: url, atomically: true, encoding: .utf8)
            model.files = [try model.vault.read("Note.md")]
            model.openDocument("Note.md")
            model.wikiEdit?.text += "\nSaved change"
            XCTAssertTrue(model.saveWikiEdit())
            let saved = try XCTUnwrap(model.currentDocument)
            XCTAssertFalse(FileReadState(defaults: defaults).isUnread(saved, in: model.vault.root))
            XCTAssertTrue(try String(contentsOf: url).contains("Saved change"))
        }
    }

    @MainActor private func withModel(_ body: (AppModel, UserDefaults) throws -> Void) throws {
        let suite = "FileReadStateTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent("captures.sqlite")),
                             wikiPath: root.path, fileReadState: FileReadState(defaults: defaults))
        try body(model, defaults)
    }
}
