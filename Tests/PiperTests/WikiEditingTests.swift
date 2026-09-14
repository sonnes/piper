import AppKit
import MarkdownEngine
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

    func testSummaryTextDropsMarkupAndKeepsLinkLabels() {
        let markdown = "* **Update**: [A Graph-Based Firebase](/sources/a.md) verified\n- [[topics/Reading|Read more]] and `code`\n> quoted"
        XCTAssertEqual(SummaryText.plain(markdown),
                       "Update: A Graph-Based Firebase verified Read more and code quoted")
    }

    func testSummaryTextLeavesPlainProseAlone() {
        XCTAssertEqual(SummaryText.plain("Standing orders for any agent."), "Standing orders for any agent.")
    }

    func testNativeEngineRoundtripPreservesWikiAliasesAndCode() {
        let markdown = "[[topics/Reading#A heading|Read more]] [[Plain]] [[研究/🍵|Tea]]\n`[[Code|example]]`\n```md\n[[Code|sample]]\n```\n![[image.png|200]]\n"
        let encoded = WikiEditorLinks.encode(markdown)
        let display = WikiLinkService.makeDisplayState(from: encoded)
        let stored = WikiLinkService.makeStorageState(from: display.display, existingMetadata: display.metadata, textStorage: nil)
        XCTAssertEqual(WikiEditorLinks.decode(stored.storage), markdown)
        XCTAssertEqual(WikiEditorLinks.decode("[[New#Heading|A new alias]]"), "[[New#Heading|A new alias]]")
    }

    func testEditingAliasKeepsOriginalTarget() {
        let encoded = WikiEditorLinks.encode("[[topics/Reading#A heading|Read more]]")
        let edited = encoded.replacingOccurrences(of: "Read more", with: "A different label")
        XCTAssertEqual(WikiEditorLinks.decode(edited), "[[topics/Reading#A heading|A different label]]")
    }

    func testMarkdownDestinationsKeepRelativePathsAndFragments() {
        for destination in ["../topics/Tea%20notes.md", "/Start%20Here.md#capture-first", "#details", "https://example.com/a(b)", "mailto:hello@example.com"] {
            let text = "Tea 🍵 [Read more](\(destination))"
            let label = (text as NSString).range(of: "Read more")
            XCTAssertEqual(WikiEditorLinks.markdownURL(in: text, after: label)?.absoluteString, destination)
        }
    }

    func testPageAnchorsUseVisibleTextOffsets() {
        let text = "# Tea 🍵\r\n\r\n```md\r\n## Repeat\r\n```\r\n## Repeat\r\nA [[short alias]].\r\n## Repeat\r\n[^source]: A source.\r\n"
        let first = WikiMarkdown.range(ofAnchor: "repeat", in: text)!
        let second = WikiMarkdown.range(ofAnchor: "repeat-1", in: text)!
        XCTAssertEqual((text as NSString).substring(with: first), "## Repeat\r")
        XCTAssertEqual((text as NSString).substring(with: second), "## Repeat\r")
        XCTAssertGreaterThan(second.location, first.location)
        XCTAssertEqual(first.location, "# Tea 🍵\r\n\r\n```md\r\n## Repeat\r\n```\r\n".utf16.count)
        let footnote = WikiMarkdown.range(ofAnchor: "fn-source", in: text)!
        XCTAssertEqual((text as NSString).substring(with: footnote), "[^source]: A source.\r")
        XCTAssertNil(WikiMarkdown.range(ofAnchor: "missing", in: text))
    }

    @MainActor func testSamePageAnchorKeepsUnsavedEdit() throws {
        let raw = "# Note\n\n## Details\nOriginal.\n"
        let path = root.appendingPathComponent("Note.md")
        try Data(raw.utf8).write(to: path)
        let document = makeFile(raw, path: "Note.md")
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent("captures.sqlite")), wikiPath: root.path)
        model.files = [document]
        model.openDocument(document.id)
        let session = model.wikiEdit
        session?.text += "Unsaved thought.\n"
        model.openDocument(document.id, anchor: "details")
        XCTAssertTrue(model.wikiEdit === session)
        XCTAssertEqual(model.requestedAnchor, "details")
        XCTAssertTrue(model.wikiEdit?.hasChanges == true)
        XCTAssertEqual(try String(contentsOf: path), raw)
    }

    func testSavingPreservesFrontmatterBytesAndOtherFiles() throws {
        let prefix = "---\r\n# Keep this comment\r\ntitle: 'Tea 🍵'\r\ncustom: [one, two]\r\n---\r\n"
        let raw = prefix + "\r\n# Tea\r\n\r\nOriginal.\r\n"
        let url = root.appendingPathComponent("Tea.md")
        try Data(raw.utf8).write(to: url)
        let neighbor = root.appendingPathComponent("Other.md")
        try Data("untouched".utf8).write(to: neighbor)
        let document = makeFile(raw, path: "Tea.md")
        XCTAssertEqual(document.frontmatterPrefix, prefix)
        let body = document.editableBody.replacingOccurrences(of: "Original.", with: "Updated **text** and [[Other|other note]].")
        let saved = try WikiSave.body(body, of: document, in: Vault(root: root))
        XCTAssertEqual(try Data(contentsOf: url), Data((prefix + body).utf8))
        XCTAssertEqual(saved.metadata["custom"] as? [String], ["one", "two"])
        XCTAssertEqual(try String(contentsOf: neighbor), "untouched")
    }

    func testSavingRefusesExternalChangesAndDeletedFiles() throws {
        let document = makeFile("# Original\n", path: "Note.md")
        let url = root.appendingPathComponent("Note.md")
        try Data("# External edit\n".utf8).write(to: url)
        let vault = Vault(root: root)
        XCTAssertThrowsError(try WikiSave.body("# My edit\n", of: document, in: vault))
        XCTAssertEqual(try String(contentsOf: url), "# External edit\n")
        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try WikiSave.body("# My edit\n", of: document, in: vault))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor func testEditorStartsOnOpenAndSavesOnlyOnRequest() throws {
        let path = root.appendingPathComponent("Note.md")
        let raw = "# Note\nOriginal.\n"
        try Data(raw.utf8).write(to: path)
        let document = makeFile(raw, path: "Note.md")
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent("captures.sqlite")), wikiPath: root.path)
        model.files = [document]
        model.openDocument(document.id)
        let session = try XCTUnwrap(model.wikiEdit)
        XCTAssertFalse(session.hasChanges)
        session.text += "Unsaved thought.\n"
        model.openDocument(document.id)
        model.reload()
        XCTAssertTrue(model.wikiEdit === session)
        XCTAssertFalse(model.loading)
        XCTAssertEqual(try String(contentsOf: path), raw)
        XCTAssertTrue(model.saveWikiEdit())
        XCTAssertEqual(try String(contentsOf: path), raw + "Unsaved thought.\n")
        XCTAssertTrue(model.wikiEdit === session)
        XCTAssertFalse(session.hasChanges)
    }

    @MainActor func testNavigationRequiresSaveDiscardOrCancel() throws {
        for choice in [NSApplication.ModalResponse.alertFirstButtonReturn, .alertSecondButtonReturn, .alertThirdButtonReturn] {
            let path = root.appendingPathComponent("First.md")
            let raw = "---\ntitle: First\n---\n\nOriginal.\n"
            try Data(raw.utf8).write(to: path)
            let first = makeFile(raw, path: "First.md")
            let second = makeFile("# Second", path: "Second.md")
            let model = AppModel(store: CaptureStore(url: root.appendingPathComponent("captures.sqlite")), wikiPath: root.path)
            model.files = [first, second]
            var prompts = 0
            model.confirmWikiChanges = { document in
                XCTAssertEqual(document.id, first.id)
                prompts += 1
                return choice
            }
            model.openDocument(first.id)
            model.wikiEdit?.text = "\nChanged text.\n"
            model.openDocument(second.id)
            XCTAssertEqual(prompts, 1)
            if choice == .alertThirdButtonReturn {
                XCTAssertEqual(model.selectedDocument, first.id)
                XCTAssertEqual(model.wikiEdit?.markdown, "\nChanged text.\n")
            } else {
                XCTAssertEqual(model.selectedDocument, second.id)
                XCTAssertEqual(model.wikiEdit?.document.id, second.id)
                XCTAssertFalse(try XCTUnwrap(model.wikiEdit).hasChanges)
                model.navigate(-1)
                XCTAssertEqual(model.wikiEdit?.document.id, first.id)
            }
            XCTAssertEqual(try String(contentsOf: path), choice == .alertFirstButtonReturn ? first.frontmatterPrefix + "\nChanged text.\n" : raw)
        }
    }

    @MainActor func testFailedSaveKeepsDraftOpen() throws {
        let path = root.appendingPathComponent("First.md")
        let first = makeFile("# First\n", path: "First.md")
        try Data(first.raw.utf8).write(to: path)
        let second = makeFile("# Second", path: "Second.md")
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent("captures.sqlite")), wikiPath: root.path)
        model.files = [first, second]
        model.confirmWikiChanges = { _ in .alertFirstButtonReturn }
        model.openDocument(first.id)
        model.wikiEdit?.text = "My newer edit."
        try Data("External edit.".utf8).write(to: path)
        model.openDocument(second.id)
        XCTAssertEqual(model.selectedDocument, first.id)
        XCTAssertEqual(model.wikiEdit?.markdown, "My newer edit.")
        XCTAssertNotNil(model.store.errorMessage)
        XCTAssertEqual(try String(contentsOf: path), "External edit.")
        model.discardWikiEdit()
        XCTAssertEqual(model.wikiEdit?.markdown, "External edit.")
        XCTAssertFalse(try XCTUnwrap(model.wikiEdit).hasChanges)
    }

    @MainActor func testCloseCanCancelAndDiscardWithoutSaving() throws {
        let path = root.appendingPathComponent("Note.md")
        let document = makeFile("# Note\n", path: "Note.md")
        try Data(document.raw.utf8).write(to: path)
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent("captures.sqlite")), wikiPath: root.path)
        model.files = [document]
        model.openDocument(document.id)
        model.wikiEdit?.text += "Unsaved."
        model.confirmWikiChanges = { _ in .alertThirdButtonReturn }
        XCTAssertFalse(model.finishWikiEdit())
        XCTAssertTrue(try XCTUnwrap(model.wikiEdit).hasChanges)
        model.confirmWikiChanges = { _ in .alertSecondButtonReturn }
        XCTAssertTrue(model.finishWikiEdit())
        XCTAssertNil(model.wikiEdit)
        XCTAssertEqual(try String(contentsOf: path), document.raw)
        model.openDocument(document.id)
        XCTAssertEqual(model.wikiEdit?.markdown, document.editableBody)
    }

    @MainActor func testRefreshUpdatesCleanEditorAndPreservesUnchangedSession() async throws {
        let path = root.appendingPathComponent("Note.md")
        let document = makeFile("# Note\n", path: "Note.md")
        try Data(document.raw.utf8).write(to: path)
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent("captures.sqlite")), wikiPath: root.path)
        model.files = [document]
        model.openDocument(document.id)
        let session = try XCTUnwrap(model.wikiEdit)
        model.reload()
        for _ in 0..<100 where model.loading { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.loading)
        XCTAssertTrue(model.wikiEdit === session)
        try Data("# External update\n".utf8).write(to: path)
        model.reload()
        for _ in 0..<100 where model.loading { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.loading)
        XCTAssertEqual(model.wikiEdit?.markdown, "# External update\n")
        XCTAssertFalse(try XCTUnwrap(model.wikiEdit).hasChanges)
    }
}
