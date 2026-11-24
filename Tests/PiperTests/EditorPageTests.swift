import AppKit
import Captures
import Vault
import WebKit
import XCTest
@testable import Piper

/// Loads the built editor page in an offscreen web view and drives it through
/// the bridge, the way the file paper does.
@MainActor
final class EditorPageTests: XCTestCase {
    private var root: URL!
    private var window: NSWindow!

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
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent("captures.sqlite")), wikiPath: root.path, preferences: temporaryDefaults())
        model.library.files = try files.map { try model.library.vault.file($0.0) }
        return model
    }

    /// Puts the page in an offscreen window and waits until it reports that it is ready.
    private func load(_ model: AppModel) async throws -> EditorPage {
        let page = model.files.editorPage
        window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 900, height: 700),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        page.webView.frame = window.contentView?.bounds ?? .zero
        window.contentView?.addSubview(page.webView)
        try await waitFor("The page loads.") { try await self.evaluate(page, "typeof window.piper") as? String == "object" }
        return page
    }

    private func show(_ page: EditorPage, _ model: AppModel, source: Bool = false) throws {
        let session = try XCTUnwrap(model.files.editor)
        page.show(EditorPane.request(for: session, files: model.files, source: source), session: ObjectIdentifier(session),
                  revision: session.revision,
                  theme: EditorTheme(theme: "Paper", font: "Serif", size: 18, appearance: "Light"),
                  anchor: model.files.requestedAnchor, anchorRequest: model.files.anchorRequest,
                  notes: model.files.fileNotes(session.document))
    }

    private func evaluate(_ page: EditorPage, _ script: String) async throws -> Any? {
        try await page.webView.evaluateJavaScript(script)
    }

    private func editorText(_ page: EditorPage) async throws -> String? {
        try await evaluate(page, "document.querySelector('.ProseMirror')?.textContent") as? String
    }

    /// Puts the caret after the last text inside `selector` and types `text`, the way the keyboard does.
    private func type(_ text: String, atEndOf selector: String, in page: EditorPage) async throws {
        let typed = try await evaluate(page, """
        (() => {
          const walker = document.createTreeWalker(document.querySelector('\(selector)'), NodeFilter.SHOW_TEXT);
          let last = null;
          while (walker.nextNode()) last = walker.currentNode;
          document.querySelector('.ProseMirror').focus();
          getSelection().collapse(last, last.length);
          return document.execCommand('insertText', false, '\(text)');
        })()
        """) as? Bool
        XCTAssertEqual(typed, true, "The page takes the typed text.")
    }

    /// Selects the first copy of `quote` in the editor the way a drag does: a selection, then a mouse up
    /// in a later call, after the page has seen the selection change.
    private func select(_ quote: String, in page: EditorPage) async throws {
        _ = try await evaluate(page, """
        (() => {
          const editor = document.querySelector('.ProseMirror');
          const walker = document.createTreeWalker(editor, NodeFilter.SHOW_TEXT);
          while (walker.nextNode()) {
            const at = walker.currentNode.data.indexOf('\(quote)');
            if (at < 0) continue;
            editor.focus();
            const range = document.createRange();
            range.setStart(walker.currentNode, at);
            range.setEnd(walker.currentNode, at + '\(quote)'.length);
            getSelection().removeAllRanges();
            getSelection().addRange(range);
            return;
          }
        })()
        """)
        _ = try await evaluate(page, "document.querySelector('.ProseMirror').dispatchEvent(new MouseEvent('mouseup', { bubbles: true }))")
    }

    func testThePageShowsAFileAndSavesAnEdit() async throws {
        let raw = "---\ntitle: Tea\n---\n# Tea\n\nOriginal text.\n"
        let model = try makeModel([("Tea.md", raw)])
        model.files.openDocument("Tea.md")
        let page = try await load(model)
        try show(page, model)

        try await waitFor("The editor shows the file.") {
            try await self.editorText(page)?
                .contains("Original text.") == true
        }
        let flushed = try await page.flush()
        XCTAssertEqual(flushed?.path, "Tea.md")
        XCTAssertEqual(flushed?.text, raw)

        try await type(" Added.", atEndOf: ".ProseMirror", in: page)
        try await waitFor("The edit reaches the disk.") {
            (try String(contentsOf: self.root.appendingPathComponent("Tea.md"), encoding: .utf8)).contains("Original text. Added.")
        }
        let saved = try String(contentsOf: root.appendingPathComponent("Tea.md"), encoding: .utf8)
        XCTAssertTrue(saved.hasPrefix("---\ntitle: Tea\n---\n"), "The frontmatter stays: \(saved)")
        XCTAssertEqual(model.files.editor?.status, .saved)
    }

    func testASecondFileReplacesTheFirstInTheEditor() async throws {
        let model = try makeModel([("Green tea.md", "# Green tea\n\nLess caffeine.\n"), ("Matcha.md", "# Matcha\n\nShade-grown leaves.\n")])
        model.files.openDocument("Green tea.md")
        let page = try await load(model)
        try show(page, model)
        try await waitFor("The editor shows the first file.") {
            try await self.editorText(page)?
                .contains("Less caffeine.") == true
        }

        model.files.openDocument("Matcha.md")
        try show(page, model)
        try await waitFor("The editor shows the second file.") {
            try await self.editorText(page)?
                .contains("Shade-grown leaves.") == true
        }
        let errors = try await evaluate(page, "JSON.stringify(window.piperErrors)") as? String
        XCTAssertEqual(errors, "[]")
    }

    func testThePageHasTheBrowserFeaturesThatTheEditorUses() async throws {
        let model = try makeModel([("Note.md", "# Note\n")])
        model.files.openDocument("Note.md")
        let page = try await load(model)
        let uuid = try await evaluate(page, "typeof crypto.randomUUID") as? String
        let clipboard = try await evaluate(page, "typeof navigator.clipboard?.writeText") as? String
        XCTAssertEqual(uuid, "function")
        XCTAssertEqual(clipboard, "function")
    }

    func testAFileWithLinkTitlesIsReadOnlyInPreview() async throws {
        let model = try makeModel([("Notes.md", "[A source](https://example.com \"Title\").\n")])
        model.files.openDocument("Notes.md")
        let page = try await load(model)
        try show(page, model)
        try await waitFor("The page reports the link titles.") { model.files.editor?.lossy == ["link titles"] }
        let editable = try await evaluate(page, "document.querySelector('.ProseMirror').getAttribute('contenteditable')") as? String
        XCTAssertEqual(editable, "false")
    }

    func testAnEditKeepsTheFootnotesOfAFile() async throws {
        let raw = "A claim.[^1]\n\n[^1]: The source.\n"
        let model = try makeModel([("Notes.md", raw)])
        model.files.openDocument("Notes.md")
        let page = try await load(model)
        try show(page, model)
        try await waitFor("The editor shows the footnote.") {
            (try await self.evaluate(page, "document.querySelector('.piper-footnote')?.textContent") as? String) == "The source."
        }
        let editable = try await evaluate(page, "document.querySelector('.ProseMirror').getAttribute('contenteditable')") as? String
        XCTAssertEqual(editable, "true")
        XCTAssertEqual(model.files.editor?.lossy, [])
        let flushed = try await page.flush()
        XCTAssertEqual(flushed?.text, raw, "Opening the file does not change it.")

        try await type(" More.", atEndOf: ".piper-footnote", in: page)
        try await waitFor("The edit reaches the disk.") {
            (try String(contentsOf: self.root.appendingPathComponent("Notes.md"), encoding: .utf8)).contains("More.")
        }
        let saved = try String(contentsOf: root.appendingPathComponent("Notes.md"), encoding: .utf8)
        XCTAssertEqual(saved, "A claim.[^1]\n\n[^1]: The source. More.\n")
    }

    func testADiskChangeLoadsIntoTheEditor() async throws {
        let model = try makeModel([("Note.md", "# Note\n\nFirst.\n")])
        model.files.openDocument("Note.md")
        let page = try await load(model)
        try show(page, model)
        try await waitFor("The editor shows the file.") {
            try await self.editorText(page)?.contains("First.") == true
        }
        try Data("# Note\n\nSecond.\n".utf8).write(to: root.appendingPathComponent("Note.md"))
        model.files.editors["Note.md"]?.diskChanged(in: model.library.vault)
        try show(page, model)
        try await waitFor("The editor shows the new text.") {
            try await self.editorText(page)?.contains("Second.") == true
        }
        let flushed = try await page.flush()
        XCTAssertEqual(flushed?.text, "# Note\n\nSecond.\n")
    }

    func testTheSourceTabEditsTheRawText() async throws {
        let raw = "A claim.[^1]\n\n[^1]: The source.\n"
        let model = try makeModel([("Notes.md", raw)])
        model.files.openDocument("Notes.md")
        let page = try await load(model)
        try show(page, model, source: true)
        try await waitFor("The source editor shows the raw text.") {
            try await self.editorText(page)?.contains("[^1]: The source.") == true
        }
        try await type("More.", atEndOf: ".ProseMirror", in: page)
        try await waitFor("The raw edit reaches the disk.") {
            (try String(contentsOf: self.root.appendingPathComponent("Notes.md"), encoding: .utf8)).hasSuffix("More.")
        }
        let saved = try String(contentsOf: root.appendingPathComponent("Notes.md"), encoding: .utf8)
        XCTAssertTrue(saved.contains("[^1]: The source."), "The footnote stays: \(saved)")
    }

    func testTheSelectionBarHighlightsAndAddsANote() async throws {
        let model = try makeModel([("Tea.md", "# Tea\n\nGreen tea has less caffeine than coffee.\n")])
        model.files.openDocument("Tea.md")
        let page = try await load(model)
        try show(page, model)
        try await waitFor("The editor shows the file.") {
            try await self.editorText(page)?.contains("caffeine") == true
        }
        // The selection bar listens only after the page reports its editor, so select until it shows.
        try await waitFor("The selection bar shows.") {
            try await self.select("less caffeine", in: page)
            return try await self.evaluate(page, "!!document.querySelector('.piper-selbar')") as? Bool == true
        }
        _ = try await evaluate(page, "[...document.querySelectorAll('.piper-selbar button')].find(b => b.textContent === 'Highlight').click()")
        try await waitFor("The highlight reaches the file.") {
            (try String(contentsOf: self.root.appendingPathComponent("Tea.md"), encoding: .utf8))
                .contains("==less caffeine==")
        }

        try await waitFor("The selection bar shows again.") {
            try await self.select("less caffeine", in: page)
            return try await self.evaluate(page, "!!document.querySelector('.piper-selbar')") as? Bool == true
        }
        _ = try await evaluate(page, "[...document.querySelectorAll('.piper-selbar button')].find(b => b.textContent === 'Note').click()")
        try await waitFor("The note line shows.") {
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
        try await waitFor("Piper saves the note.") {
            model.store.notes.contains { $0.text.contains("Check the source.") }
        }
        let note = try XCTUnwrap(model.store.notes.first { $0.text.contains("Check the source.") })
        let parent = try XCTUnwrap(model.store.notes.first { $0.id == note.parent })
        XCTAssertEqual(parent.sourceURLs, [model.files.fileLink("Tea.md")])
        XCTAssertEqual(note.anchor?.quote, "less caffeine")

        try show(page, model)
        try await waitFor("The page shows the card.") {
            (try await self.evaluate(page, "document.querySelector('.piper-card.mine')?.textContent") as? String)?
                .contains("Check the source.") == true
        }
    }

    func testThePageShowsTheFileAndTheNotesAgainAfterACrash() async throws {
        let model = try makeModel([("Tea.md", "# Tea\n\nGreen tea has less caffeine than coffee.\n")])
        model.files.openDocument("Tea.md")
        let parent = try model.store.pageNote(for: model.files.fileLink("Tea.md"), title: "Tea", source: ReaderAssistant.source)
        try model.reader.highlight(NoteAnchor(quote: "less caffeine", block: 1, offset: 14), color: ReaderAssistant.colors[0],
                                   in: parent.id, comment: "Check the source.")
        let page = try await load(model)
        try show(page, model)
        let card = "document.querySelector('.piper-card.mine')?.textContent"
        try await waitFor("The page shows the card.") {
            (try await self.evaluate(page, card) as? String)?.contains("Check the source.") == true
        }

        page.webView.navigationDelegate?.webViewWebContentProcessDidTerminate?(page.webView)
        try await waitFor("The page loads again with the file and the card.") {
            let text = try await self.editorText(page)
            let shown = try await self.evaluate(page, card) as? String
            return text?.contains("less caffeine") == true && shown?.contains("Check the source.") == true
        }
    }

    func testAJavaScriptErrorOfACallReachesTheMessages() async throws {
        let model = try makeModel([("Note.md", "# Note\n")])
        model.files.openDocument("Note.md")
        let page = try await load(model)
        try show(page, model)
        try await waitFor("The page is ready.") { model.files.editor?.lossy == [] }
        _ = try await evaluate(page, "void (window.piper.assetChanged = () => { throw new Error('Broken embed') })")
        page.assetChanged("Note.md")
        try await waitFor("The error reaches the messages.") { model.messages.last?.isError == true }
    }
}
