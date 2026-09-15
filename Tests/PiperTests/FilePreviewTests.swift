import AppKit
import Captures
import Vault
import XCTest
@testable import Piper

final class FilePreviewTests: XCTestCase {
    func testRawMarkdownKeepsFrontmatterAndShowsTheDraft() {
        let prefix = "---\r\ntitle: 'QA'\r\n---\r\n"
        let file = makeFile(prefix + "# Original\r\n", path: "note.MD")
        XCTAssertEqual(FilePresentation.sourceText(for: file), file.raw)
        XCTAssertEqual(FilePresentation.sourceText(for: file, markdown: "# Draft\r\n[[Target|Label]]\r\n"),
                       prefix + "# Draft\r\n[[Target|Label]]\r\n")
    }

    func testRawHTMLKeepsLiteralMarkupAndRejectsUnavailableText() {
        let html = "<!doctype html>\n<h1>QA &amp; source</h1>\n"
        for path in ["page.html", "page.HTM"] {
            XCTAssertEqual(FilePresentation.sourceText(for: makeFile(html, path: path)), html)
        }
        XCTAssertNil(FilePresentation.sourceText(for: makeFile("{}", path: "data.json")))
        let large = VaultFile(relativePath: "large.md", size: 5_000_000, modifiedAt: Date(), text: nil)
        XCTAssertNil(FilePresentation.sourceText(for: large))
    }

    func testPreviewRoutesTextAndRichFormatsWithoutMarkdownFormatting() {
        for path in ["notes.txt", "config.json", "script.swift", "config.yaml", "README"] {
            XCTAssertEqual(FilePresentation(makeFile("# Literal *text*", path: path)), .text, path)
        }
        for path in ["page.html", "page.HTM", "drawing.svg", "rich.rtf"] {
            XCTAssertEqual(FilePresentation(makeFile("<html>Content</html>", path: path)), .quickLook, path)
        }
        for path in ["photo.png", "photo.HEIC", "document.pdf", "movie.mov", "unknown.bin", "large.md"] {
            let file = VaultFile(relativePath: path, size: 100, modifiedAt: Date(), text: nil)
            XCTAssertEqual(FilePresentation(file), .quickLook, path)
        }
        XCTAssertEqual(FilePresentation(makeFile("# Markdown", path: "Note.MD")), .markdown)
    }

    @MainActor func testPreviewsNeverCreateAMarkdownEditOrOverwriteTheFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent("captures.sqlite")), wikiPath: root.path)
        for (path, bytes) in [
            ("photo.png", Data([0, 1, 2, 255])),
            ("data.json", Data("{\"literal\":\"[[value|alias]]\"}".utf8)),
            ("notes.txt", Data("---\ntitle: Keep this text\n---\n".utf8)),
            ("binary.md", Data([0, 1, 2, 255]))
        ] {
            let url = root.appendingPathComponent(path)
            try bytes.write(to: url)
            let file = try model.vault.read(path)
            model.files.append(file)
            model.openDocument(path)
            XCTAssertEqual(model.currentDocument?.id, path)
            XCTAssertNil(model.wikiEdit)
            XCTAssertTrue(model.saveWikiEdit())
            XCTAssertThrowsError(try WikiSave.body("Replacement", of: file, in: model.vault))
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }

    @MainActor func testOpeningAPreviewRespectsUnsavedMarkdownChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent("captures.sqlite")), wikiPath: root.path)
        let note = makeFile("# Note\n", path: "Note.md")
        let image = VaultFile(relativePath: "image.png", size: 10, modifiedAt: Date(), text: nil)
        model.files = [note, image]
        model.openDocument(note.id)
        model.wikiEdit?.text += "Unsaved"
        model.confirmWikiChanges = { _ in .alertThirdButtonReturn }
        model.openDocument(image.id)
        XCTAssertEqual(model.selectedDocument, note.id)
        XCTAssertTrue(model.wikiEdit?.hasChanges == true)
        model.confirmWikiChanges = { _ in .alertSecondButtonReturn }
        model.openDocument(image.id)
        XCTAssertEqual(model.selectedDocument, image.id)
        XCTAssertNil(model.wikiEdit)
    }
}
