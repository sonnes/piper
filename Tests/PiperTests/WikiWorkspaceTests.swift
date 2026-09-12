import XCTest
@testable import Piper

final class WikiWorkspaceTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("piper-workspace-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func document(_ path: String, title: String? = nil, body: String = "") -> WikiDocument {
        WikiDocument(relativePath: path, raw: body, body: body, metadata: title.map { ["title": $0] } ?? [:], problem: nil)
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

    func testTreePreservesNestedFoldersAndCountsLeaves() {
        let documents = [document("Start Here.md"), document("Research/Interviews/Maya.md"), document("Research/Journal.md"), document("Topics/Reading.md")]
        let nodes = WikiTreeNode.build(documents)
        XCTAssertEqual(nodes.map(\.id), ["Research", "Topics", "Start Here.md"])
        XCTAssertEqual(nodes[0].count, 2)
        XCTAssertEqual(nodes[0].children?.first?.id, "Research/Interviews")
        XCTAssertEqual(nodes[0].children?.first?.children?.first?.id, "Research/Interviews/Maya.md")
    }

    func testMarkdownAndWikiLinksResolvePathsTitlesAndAnchors() throws {
        let docs = [document("Start Here.md"), document("Topics/Reading.md", title: "Reading rhythm"), document("Research/Journal.md")]
        let repository = WikiRepository(root: root)
        XCTAssertEqual(try WikiLinks.resolve("../Topics/Reading.md#A%20comfortable%20measure", from: docs[2], documents: docs, repository: repository), WikiLocation(path: "Topics/Reading.md", anchor: "A comfortable measure"))
        XCTAssertEqual(try WikiLinks.resolve("/Start%20Here.md", from: docs[1], documents: docs, repository: repository).path, "Start Here.md")
        XCTAssertEqual(try WikiLinks.resolve("Reading rhythm", from: docs[0], documents: docs, repository: repository, wikiStyle: true).path, "Topics/Reading.md")
        XCTAssertEqual(try WikiLinks.resolve("Topics/Reading", from: docs[2], documents: docs, repository: repository, wikiStyle: true).path, "Topics/Reading.md")
        XCTAssertEqual(try WikiLinks.resolve("#Details", from: docs[1], documents: docs, repository: repository), WikiLocation(path: "Topics/Reading.md", anchor: "Details"))
    }

    func testAmbiguousMissingAndUnsafeLinksFail() throws {
        let docs = [document("Home.md"), document("One/Note.md"), document("Two/Note.md")]
        let repository = WikiRepository(root: root)
        for path in ["Note", "Missing", "../../outside.md", "%2e%2e/outside.md"] {
            XCTAssertThrowsError(try WikiLinks.resolve(path, from: docs[0], documents: docs, repository: repository, wikiStyle: true))
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.deletingLastPathComponent())
        XCTAssertThrowsError(try WikiLinks.resolve("link/Note", from: docs[0], documents: docs, repository: repository, wikiStyle: true))
    }

    func testBacklinksIgnoreCodeAndImagesAndDeduplicateNotes() {
        let target = document("Topics/Reading.md", title: "Reading rhythm")
        let linked = document("Home.md", body: "[[Reading rhythm|Read]] and [again](Topics/Reading.md#Measure)")
        let code = document("Code.md", body: "`[[Reading rhythm]]`\n\n```md\n[[Reading rhythm]]\n```\n\n![image](Topics/Reading.md)")
        let unrelated = document("Other.md", body: "Reading rhythm is plain text.")
        let docs = [target, linked, code, unrelated]
        XCTAssertEqual(WikiLinks.backlinks(to: target, in: docs, repository: WikiRepository(root: root)).map(\.id), ["Home.md"])
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

    func testReaderIncludesIndexesWithoutChangingExportScan() throws {
        try Data("---\nokf_version: \"0.2\"\n---\n# Wiki\n".utf8).write(to: root.appendingPathComponent("index.md"))
        try Data("# Log\n".utf8).write(to: root.appendingPathComponent("log.md"))
        let repository = WikiRepository(root: root)
        XCTAssertEqual(try repository.scan().documents.count, 0)
        let scan = try repository.scan(includeIndexes: true)
        XCTAssertEqual(scan.documents.count, 2)
        XCTAssertTrue(scan.problems.isEmpty)
    }

    @MainActor func testSearchKeepsActiveDocumentAndMatchesMultipleWords() {
        let model = AppModel(store: AppStore(url: root.appendingPathComponent("captures.sqlite")), wikiPath: root.path)
        model.documents = [document("Topics/Reading.md", title: "Reading rhythm", body: "A comfortable measure"), document("Other.md", body: "Another note")]
        model.openDocument("Other.md")
        model.wikiQuery = "reading measure"
        XCTAssertEqual(model.filteredDocuments.map(\.id), ["Topics/Reading.md"])
        XCTAssertEqual(model.selectedDocument, "Other.md")
        model.wikiQuery = "   "
        XCTAssertEqual(model.filteredDocuments.count, 2)
        model.wikiQuery = "unmatched"
        XCTAssertTrue(model.filteredDocuments.isEmpty)
    }
}
