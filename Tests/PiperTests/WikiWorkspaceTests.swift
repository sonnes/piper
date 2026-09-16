import XCTest
@testable import Piper
import PiperCore
import Captures
import CapturesDatabase
import Vault

final class WikiWorkspaceTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("piper-workspace-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func document(_ path: String, title: String? = nil, body: String = "") -> VaultFile {
        let frontmatter = title.map { "---\ntitle: \($0)\n---\n" } ?? ""
        return makeFile(frontmatter + body, path: path)
    }

    func testNavigationKeepsAnchorsAndNewVisitDropsForwardHistory() {
        var workspace = WikiWorkspace()
        workspace.open(WikiLocation(path: "a.md"))
        workspace.open(WikiLocation(path: "b.md", anchor: "details"))
        workspace.move(-1)
        XCTAssertEqual(workspace.location?.path, "a.md")
        XCTAssertTrue(workspace.canGoForward)
        workspace.move(1)
        XCTAssertEqual(workspace.location, WikiLocation(path: "b.md", anchor: "details"))
        workspace.move(-1)
        workspace.open(WikiLocation(path: "d.md"))
        XCTAssertFalse(workspace.canGoForward)
        XCTAssertEqual(workspace.history.map(\.path), ["a.md", "d.md"])
    }

    func testRefreshRemovesDeletedFilesFromHistory() {
        var workspace = WikiWorkspace()
        workspace.open(WikiLocation(path: "a.md"))
        workspace.open(WikiLocation(path: "deleted.md"))
        workspace.open(WikiLocation(path: "b.md"))
        workspace.move(-1)
        workspace.reconcile(paths: ["a.md", "b.md"])
        XCTAssertEqual(workspace.location?.path, "b.md")
        workspace.move(-1)
        XCTAssertEqual(workspace.location?.path, "a.md")
        workspace.reconcile(paths: [])
        XCTAssertNil(workspace.location)
        workspace.move(-1)
        XCTAssertTrue(workspace.history.isEmpty)
    }


    func testMarkdownAndWikiLinksResolvePathsTitlesAndAnchors() throws {
        let docs = [document("Start Here.md"), document("Topics/Reading.md", title: "Reading rhythm"), document("Research/Journal.md")]
        let vault = Vault(root: root)
        XCTAssertEqual(try WikiLinks.resolve("../Topics/Reading.md#A%20comfortable%20measure", from: docs[2], files: docs, vault: vault), WikiLocation(path: "Topics/Reading.md", anchor: "A comfortable measure"))
        XCTAssertEqual(try WikiLinks.resolve("/Start%20Here.md", from: docs[1], files: docs, vault: vault).path, "Start Here.md")
        XCTAssertEqual(try WikiLinks.resolve("Reading rhythm", from: docs[0], files: docs, vault: vault, wikiStyle: true).path, "Topics/Reading.md")
        XCTAssertEqual(try WikiLinks.resolve("Topics/Reading", from: docs[2], files: docs, vault: vault, wikiStyle: true).path, "Topics/Reading.md")
        XCTAssertEqual(try WikiLinks.resolve("#Details", from: docs[1], files: docs, vault: vault), WikiLocation(path: "Topics/Reading.md", anchor: "Details"))
    }

    func testAmbiguousMissingAndUnsafeLinksFail() throws {
        let docs = [document("Home.md"), document("One/Note.md"), document("Two/Note.md")]
        let vault = Vault(root: root)
        for path in ["Note", "Missing", "../../outside.md", "%2e%2e/outside.md"] {
            XCTAssertThrowsError(try WikiLinks.resolve(path, from: docs[0], files: docs, vault: vault, wikiStyle: true))
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.deletingLastPathComponent())
        XCTAssertThrowsError(try WikiLinks.resolve("link/Note", from: docs[0], files: docs, vault: vault, wikiStyle: true))
    }

    func testBacklinksIgnoreCodeAndImagesAndDeduplicateNotes() {
        let target = document("Topics/Reading.md", title: "Reading rhythm")
        let linked = document("Home.md", body: "[[Reading rhythm|Read]] and [again](Topics/Reading.md#Measure)")
        let code = document("Code.md", body: "`[[Reading rhythm]]`\n\n```md\n[[Reading rhythm]]\n```\n\n![image](Topics/Reading.md)")
        let unrelated = document("Other.md", body: "Reading rhythm is plain text.")
        let docs = [target, linked, code, unrelated]
        XCTAssertEqual(WikiLinks.backlinks(to: target, in: docs, vault: Vault(root: root)).map(\.id), ["Home.md"])
    }

    func testMarkdownStructureKeepsCodeAndCreatesStableHeadingAnchors() {
        let text = "# Title\n\n## Same heading\n\nOne\nline.\n\n## Same heading\n\n- [x] Done\n  - Nested\n\n```swift\nlet code = \"[[Not a link]]\"\n# Not a heading\n```\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n[^source]: A source."
        let blocks = WikiMarkdown.parse(text)
        XCTAssertEqual(blocks.filter { $0.kind == .heading }.map(\.anchor), ["title", "same-heading", "same-heading-1"])
        XCTAssertEqual(blocks.first { $0.kind == .paragraph }?.text, "One line.")
        XCTAssertEqual(blocks.filter { $0.kind == .listItem }.map(\.marker), ["☑", "•"])
        XCTAssertEqual(blocks.filter { $0.kind == .listItem }.last?.level, 1)
        XCTAssertEqual(blocks.first { $0.kind == .code }?.text, "let code = \"[[Not a link]]\"\n# Not a heading")
        XCTAssertEqual(blocks.filter { $0.kind == .table }.count, 1)
        XCTAssertEqual(blocks.last?.anchor, "fn-source")
    }

    func testInlineWikiAliasAndFootnoteProduceNavigableURLs() {
        let value = WikiMarkdown.inline("Read [[Topics/Reading#Measure|this note]], then [^source]. Keep `[[literal]]`.")
        XCTAssertEqual(String(value.characters), "Read this note, then source. Keep [[literal]].")
        let links = value.runs.compactMap { $0.link }
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(URLComponents(url: links[0], resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "Topics/Reading#Measure")
        XCTAssertEqual(links[1].scheme, "piper-footnote")
        XCTAssertEqual(String(WikiMarkdown.inline("![alt](https://example.invalid/image.png)").characters), "Image: alt")
    }

    /// One scan lists everything. Piper names no file special.
    func testIndexAndLogAreOrdinaryFiles() throws {
        try Data("---\nokf_version: \"0.2\"\n---\n# Wiki\n".utf8).write(to: root.appendingPathComponent("index.md"))
        try Data("# Log\n".utf8).write(to: root.appendingPathComponent("log.md"))
        try Data("Plain text.\n".utf8).write(to: root.appendingPathComponent("notes.txt"))
        let scan = try Vault(root: root).scan()
        XCTAssertEqual(scan.files.map(\.id).sorted(), ["index.md", "log.md", "notes.txt"])
        XCTAssertTrue(scan.problems.isEmpty, "A file with no frontmatter is not a problem")
    }

    @MainActor func testSearchKeepsActiveDocumentAndMatchesMultipleWords() {
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent("captures.sqlite")), wikiPath: root.path)
        model.files = [document("Topics/Reading.md", title: "Reading rhythm", body: "A comfortable measure"), document("Other.md", body: "Another note")]
        model.openDocument("Other.md")
        model.wikiQuery = "reading measure"
        XCTAssertEqual(model.filteredFiles.map(\.id), ["Topics/Reading.md"])
        XCTAssertEqual(model.selectedDocument, "Other.md")
        model.wikiQuery = "   "
        XCTAssertEqual(model.filteredFiles.count, 2)
        model.wikiQuery = "unmatched"
        XCTAssertTrue(model.filteredFiles.isEmpty)
    }

    @MainActor func testListSearchStaysInItsFolder() {
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent("captures.sqlite")), wikiPath: root.path)
        model.files = [
            document("Root.md", body: "matching text"),
            document("Topics/One.md", body: "matching text"),
            document("Topics/Nested/Two.md", body: "matching text"),
            document("Other/Three.md", body: "matching text")
        ]
        model.wikiQuery = "matching"
        XCTAssertEqual(model.filteredFiles(in: "Topics").map(\.id), ["Topics/One.md"])
        XCTAssertEqual(model.filteredFiles(in: "").map(\.id), ["Root.md"])
        XCTAssertEqual(model.filteredFiles(in: nil).count, 4)
        model.wikiQuery = "   "
        XCTAssertEqual(model.filteredFiles(in: "Topics").map(\.id), ["Topics/One.md"])
        model.wikiQuery = "absent"
        XCTAssertTrue(model.filteredFiles(in: "Topics").isEmpty)
    }

}
