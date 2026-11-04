import AppKit
import Captures
import Vault
import WebKit
import XCTest
@testable import Piper

/// Loads the built editor page in an offscreen web view and drives it through
/// the bridge, the way the detail pane does.
@MainActor
final class EditorPageTests: XCTestCase {
    private var root: URL!
    private var window: NSWindow!
    private var pageForErrors: EditorPage?

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("piper-editor-page-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        window?.close()
        window = nil
        try? FileManager.default.removeItem(at: root)
    }

    private func makeModel(_ files: [(String, String)]) throws -> AppModel {
        for (path, raw) in files {
            try Data(raw.utf8).write(to: root.appendingPathComponent(path))
        }
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent("captures.sqlite")), wikiPath: root.path)
        model.files = try files.map { try model.vault.read($0.0) }
        return model
    }

    /// Puts the page in an offscreen window and waits until it reports that it is ready.
    private func load(_ model: AppModel) async throws -> EditorPage {
        let page = model.editorPage
        pageForErrors = page
        window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 900, height: 700),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        page.webView.frame = window.contentView?.bounds ?? .zero
        window.contentView?.addSubview(page.webView)
        try await wait("The page loads.") { try await self.evaluate(page, "typeof window.piper") as? String == "object" }
        return page
    }

    private func show(_ page: EditorPage, _ model: AppModel, source: Bool = false) throws {
        let session = try XCTUnwrap(model.editor)
        page.show(EditorPane.request(for: session, model: model, source: source), session: ObjectIdentifier(session),
                  revision: session.revision,
                  theme: EditorTheme(theme: "Paper", font: "Serif", size: 18, appearance: "Light"),
                  anchorRequest: model.anchorRequest)
    }

    private func evaluate(_ page: EditorPage, _ script: String) async throws -> Any? {
        try await page.webView.evaluateJavaScript(script)
    }

    private func wait(_ message: String, timeout: TimeInterval = 10, _ condition: @escaping () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? await condition()) == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        var errors: Any?
        if let page = pageForErrors { errors = try? await evaluate(page, "JSON.stringify(window.piperErrors)") }
        XCTFail("\(message) \(String(describing: errors))")
    }

    func testThePageShowsAFileAndSavesAnEdit() async throws {
        let raw = "---\ntitle: Tea\n---\n# Tea\n\nOriginal text.\n"
        let model = try makeModel([("Tea.md", raw)])
        model.openDocument("Tea.md")
        let page = try await load(model)
        try show(page, model)

        try await wait("The editor shows the file.") {
            (try await self.evaluate(page, "document.querySelector('.ProseMirror')?.textContent") as? String)?
                .contains("Original text.") == true
        }
        let flushed = await page.flush()
        XCTAssertEqual(flushed?.path, "Tea.md")
        XCTAssertEqual(flushed?.text, raw)

        _ = try await evaluate(page, "document.querySelector('.ProseMirror').editor.commands.insertContentAt(document.querySelector('.ProseMirror').editor.state.doc.content.size - 1, ' Added.')")
        try await wait("The edit reaches the disk.") {
            (try String(contentsOf: self.root.appendingPathComponent("Tea.md"), encoding: .utf8)).contains("Original text. Added.")
        }
        let saved = try String(contentsOf: root.appendingPathComponent("Tea.md"), encoding: .utf8)
        XCTAssertTrue(saved.hasPrefix("---\ntitle: Tea\n---\n"), "The frontmatter stays: \(saved)")
        XCTAssertEqual(model.editor?.status, .saved)
    }

    func testThePageHasTheBrowserFeaturesThatTheEditorUses() async throws {
        let model = try makeModel([("Note.md", "# Note\n")])
        model.openDocument("Note.md")
        let page = try await load(model)
        let uuid = try await evaluate(page, "typeof crypto.randomUUID") as? String
        let clipboard = try await evaluate(page, "typeof navigator.clipboard?.writeText") as? String
        XCTAssertEqual(uuid, "function")
        XCTAssertEqual(clipboard, "function")
    }

    func testAFileWithFootnotesIsReadOnlyInPreview() async throws {
        let model = try makeModel([("Notes.md", "A claim.[^1]\n\n[^1]: The source.\n")])
        model.openDocument("Notes.md")
        let page = try await load(model)
        try show(page, model)
        try await wait("The page reports the footnotes.") { model.editor?.lossy == ["footnotes"] }
        let editable = try await evaluate(page, "document.querySelector('.ProseMirror').getAttribute('contenteditable')") as? String
        XCTAssertEqual(editable, "false")
    }

    func testADiskChangeLoadsIntoTheEditor() async throws {
        let model = try makeModel([("Note.md", "# Note\n\nFirst.\n")])
        model.openDocument("Note.md")
        let page = try await load(model)
        try show(page, model)
        try await wait("The editor shows the file.") {
            (try await self.evaluate(page, "document.querySelector('.ProseMirror')?.textContent") as? String)?.contains("First.") == true
        }
        try Data("# Note\n\nSecond.\n".utf8).write(to: root.appendingPathComponent("Note.md"))
        model.editors["Note.md"]?.diskChanged(in: model.vault)
        try show(page, model)
        try await wait("The editor shows the new text.") {
            (try await self.evaluate(page, "document.querySelector('.ProseMirror')?.textContent") as? String)?.contains("Second.") == true
        }
        let flushed = await page.flush()
        XCTAssertEqual(flushed?.text, "# Note\n\nSecond.\n")
    }

    func testTheSourceTabEditsTheRawText() async throws {
        let raw = "A claim.[^1]\n\n[^1]: The source.\n"
        let model = try makeModel([("Notes.md", raw)])
        model.openDocument("Notes.md")
        let page = try await load(model)
        try show(page, model, source: true)
        try await wait("The source editor shows the raw text.") {
            (try await self.evaluate(page, "document.querySelector('.ProseMirror')?.textContent") as? String)?.contains("[^1]: The source.") == true
        }
        _ = try await evaluate(page, "document.querySelector('.ProseMirror').editor.commands.insertContentAt(document.querySelector('.ProseMirror').editor.state.doc.content.size - 1, 'More.')")
        try await wait("The raw edit reaches the disk.") {
            (try String(contentsOf: self.root.appendingPathComponent("Notes.md"), encoding: .utf8)).hasSuffix("More.")
        }
        let saved = try String(contentsOf: root.appendingPathComponent("Notes.md"), encoding: .utf8)
        XCTAssertTrue(saved.contains("[^1]: The source."), "The footnote stays: \(saved)")
    }

    func testTheSelectionBarHighlightsAndAddsANote() async throws {
        let model = try makeModel([("Tea.md", "# Tea\n\nGreen tea has less caffeine than coffee.\n")])
        model.openDocument("Tea.md")
        let page = try await load(model)
        try show(page, model)
        try await wait("The editor shows the file.") {
            (try await self.evaluate(page, "document.querySelector('.ProseMirror')?.textContent") as? String)?.contains("caffeine") == true
        }
        let select = """
        (() => {
          const editor = document.querySelector('.ProseMirror').editor;
          let from = 0;
          editor.state.doc.descendants((node, pos) => {
            if (node.isText && node.text.includes('less caffeine')) from = pos + node.text.indexOf('less caffeine');
          });
          editor.commands.focus();
          editor.commands.setTextSelection({ from, to: from + 'less caffeine'.length });
          editor.view.dom.dispatchEvent(new MouseEvent('mouseup', { bubbles: true }));
        })()
        """
        _ = try await evaluate(page, select)
        try await wait("The selection bar shows.") {
            try await self.evaluate(page, "!!document.querySelector('.piper-selbar')") as? Bool == true
        }
        _ = try await evaluate(page, "document.querySelector('.piper-selbar button.sw.green').click()")
        try await wait("The highlight reaches the file.") {
            (try String(contentsOf: self.root.appendingPathComponent("Tea.md"), encoding: .utf8))
                .contains("<mark class=\"green\">less caffeine</mark>")
        }

        _ = try await evaluate(page, select)
        try await wait("The selection bar shows again.") {
            try await self.evaluate(page, "!!document.querySelector('.piper-selbar')") as? Bool == true
        }
        _ = try await evaluate(page, "[...document.querySelectorAll('.piper-selbar button')].find(b => b.textContent === 'Note').click()")
        try await wait("The note line shows.") {
            try await self.evaluate(page, "!!document.querySelector('.piper-askline input')") as? Bool == true
        }
        _ = try await evaluate(page, """
        (() => {
          const input = document.querySelector('.piper-askline input');
          Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(input, 'Check the source.');
          input.dispatchEvent(new Event('input', { bubbles: true }));
          input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
        })()
        """)
        try await wait("Piper saves the note.") {
            model.store.notes.contains { $0.text.contains("Check the source.") }
        }
        let note = try XCTUnwrap(model.store.notes.first { $0.text.contains("Check the source.") })
        let parent = try XCTUnwrap(model.store.notes.first { $0.id == note.parent })
        XCTAssertEqual(parent.sourceURLs, [model.fileLink("Tea.md")])
        XCTAssertEqual(note.anchor?.quote, "less caffeine")

        let session = try XCTUnwrap(model.editor)
        page.setNotes(model.fileNotes(session.document))
        try await wait("The page shows the card.") {
            (try await self.evaluate(page, "document.querySelector('.piper-card.mine')?.textContent") as? String)?
                .contains("Check the source.") == true
        }
    }
}
