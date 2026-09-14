import XCTest
@testable import Vault

final class VaultTests: XCTestCase {

    private var root: URL!
    private var vault: Vault!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("VaultTests-" + UUID().uuidString, isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        vault = Vault(root: root)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: root.path) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try FileManager.default.removeItem(at: root)
        }
        try super.tearDownWithError()
    }

    // MARK: Helpers

    private func write(_ text: String, to path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func file(_ path: String, in scan: VaultScan) throws -> VaultFile {
        try XCTUnwrap(scan.files.first { $0.relativePath == path }, "\(path) is not in the scan")
    }

    // MARK: Scan

    func testFileWithoutFrontmatterIsListedAndReportsNoProblem() throws {
        try write("# Loose note\n\nNo metadata here.\n", to: "loose.md")
        let scan = try vault.scan()
        XCTAssertEqual(scan.problems, [])
        let file = try file("loose.md", in: scan)
        XCTAssertNil(file.frontmatterProblem)
        XCTAssertTrue(file.metadata.isEmpty)
        XCTAssertTrue(file.isText)
        XCTAssertEqual(file.body, "# Loose note\n\nNo metadata here.\n")
    }

    func testFrontmatterExposesMetadataAndBody() throws {
        try write("---\ntitle: Payment retries\nowner: platform\n---\n\n# Retries\n\nBody.\n", to: "notes/retries.md")
        let file = try file("notes/retries.md", in: try vault.scan())
        XCTAssertEqual(file.metadata["title"] as? String, "Payment retries")
        XCTAssertEqual(file.metadata["owner"] as? String, "platform")
        XCTAssertEqual(file.body, "\n# Retries\n\nBody.\n")
        XCTAssertEqual(file.folder, "notes")
        XCTAssertEqual(file.name, "retries.md")
        XCTAssertNil(file.frontmatterProblem)
    }

    func testNonMarkdownTextFileIsListed() throws {
        try write("port = 8080\n", to: "server.toml")
        try write("plain text\n", to: "notes.txt")
        let scan = try vault.scan()
        XCTAssertEqual(scan.problems, [])
        XCTAssertTrue(try file("server.toml", in: scan).isText)
        XCTAssertEqual(try file("notes.txt", in: scan).text, "plain text\n")
    }

    func testIndexAndLogGetNoSpecialTreatment() throws {
        try write("# Overview text\n", to: "index.md")
        try write("# Log text\n", to: "log.md")
        try write("# Other\n", to: "other.md")
        let scan = try vault.scan()
        XCTAssertEqual(scan.problems, [])
        XCTAssertEqual(scan.files.map(\.relativePath), ["index.md", "log.md", "other.md"])
        XCTAssertEqual(try file("index.md", in: scan).title, "Overview text")
        XCTAssertEqual(try file("log.md", in: scan).title, "Log text")
    }

    func testBrokenFrontmatterKeepsTheFileInTheList() throws {
        try write("---\ntitle: [unclosed\n---\n\nBody.\n", to: "broken.md")
        let scan = try vault.scan()
        let file = try file("broken.md", in: scan)
        XCTAssertNotNil(file.frontmatterProblem)
        XCTAssertEqual(file.body, "\nBody.\n")
    }

    func testBinaryFileIsListedAsNonText() throws {
        let url = root.appendingPathComponent("image.bin")
        try Data([0x00, 0x01, 0xFF, 0xFE]).write(to: url)
        let scan = try vault.scan()
        XCTAssertEqual(scan.problems, [])
        let file = try file("image.bin", in: scan)
        XCTAssertFalse(file.isText)
        XCTAssertNil(file.text)
        XCTAssertEqual(file.size, 4)
        XCTAssertEqual(file.title, "image")
    }

    func testScanSkipsHiddenFilesAndBuildFolders() throws {
        try write("keep\n", to: "keep.md")
        try write("hidden\n", to: ".hidden.md")
        try write("dependency\n", to: "node_modules/left-pad/index.js")
        try write("dependency\n", to: "venv/lib/thing.py")
        try write("cache\n", to: "__pycache__/thing.pyc")
        let scan = try vault.scan()
        XCTAssertEqual(scan.files.map(\.relativePath), ["keep.md"])
        XCTAssertEqual(scan.problems, [])
    }

    func testUnreadableFileBecomesAProblemAndTheScanContinues() throws {
        try XCTSkipIf(geteuid() == 0, "The root user reads a file with no permission bits.")
        try write("readable\n", to: "readable.md")
        let locked = root.appendingPathComponent("locked.md")
        try Data("secret\n".utf8).write(to: locked)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        let scan = try vault.scan()
        XCTAssertEqual(scan.files.map(\.relativePath), ["readable.md"])
        XCTAssertEqual(scan.problems.count, 1)
        XCTAssertTrue(scan.problems[0].hasPrefix("locked.md:"), scan.problems[0])
    }

    func testMissingRootThrows() throws {
        let absent = Vault(root: root.appendingPathComponent("absent", isDirectory: true))
        XCTAssertThrowsError(try absent.scan())
    }

    func testFileRootThrows() throws {
        try write("not a folder\n", to: "file.md")
        let vault = Vault(root: root.appendingPathComponent("file.md"))
        XCTAssertThrowsError(try vault.scan())
    }

    // MARK: Titles

    func testTitlePrefersFrontmatterThenHeadingThenFileName() throws {
        try write("---\ntitle: From metadata\n---\n\n# From heading\n", to: "a.md")
        try write("\n# From heading\n\nBody.\n", to: "b.md")
        try write("Body with no heading.\n", to: "c-file.md")
        let scan = try vault.scan()
        XCTAssertEqual(try file("a.md", in: scan).title, "From metadata")
        XCTAssertEqual(try file("b.md", in: scan).title, "From heading")
        XCTAssertEqual(try file("c-file.md", in: scan).title, "c-file")
    }

    // MARK: Containment

    func testPathTraversalThrows() throws {
        XCTAssertThrowsError(try vault.containedURL("../../etc/passwd"))
        XCTAssertThrowsError(try vault.containedURL("notes/../../escape.md"))
        XCTAssertThrowsError(try vault.containedURL("../../outside.md", relativeTo: "notes/deep.md"))
        XCTAssertThrowsError(try vault.containedURL("/../escape.md"))
    }

    func testContainedURLResolvesPathsInsideTheVault() throws {
        try write("body\n", to: "notes/one.md")
        XCTAssertEqual(try vault.containedURL("notes/one.md").path, root.appendingPathComponent("notes/one.md").path)
        XCTAssertEqual(try vault.containedURL("/notes/one.md").path, root.appendingPathComponent("notes/one.md").path)
        XCTAssertEqual(
            try vault.containedURL("one.md", relativeTo: "notes/two.md").path,
            root.appendingPathComponent("notes/one.md").path
        )
    }

    func testContainedURLRefusesAPathThroughASymbolicLink() throws {
        try write("body\n", to: "real/one.md")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link"),
            withDestinationURL: root.appendingPathComponent("real")
        )
        XCTAssertThrowsError(try vault.containedURL("link/one.md"))
    }

    func testScanDoesNotFollowSymbolicLinks() throws {
        let outside = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("VaultOutside-" + UUID().uuidString, isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("outside\n".utf8).write(to: outside.appendingPathComponent("secret.md"))

        try write("inside\n", to: "inside.md")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked-folder"),
            withDestinationURL: outside
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked-file.md"),
            withDestinationURL: outside.appendingPathComponent("secret.md")
        )
        let scan = try vault.scan()
        XCTAssertEqual(scan.files.map(\.relativePath), ["inside.md"])
        XCTAssertEqual(scan.problems, [])
    }

    // MARK: Create, read, and write

    func testCreateMakesAnEmptyFolderAndWritesNoIndex() throws {
        let folder = root.appendingPathComponent("new", isDirectory: true)
        try Vault(root: folder).create()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
        XCTAssertEqual(try Vault(root: folder).scan().files.count, 0)
    }

    func testCreateRefusesAFolderThatHoldsFiles() throws {
        try write("existing\n", to: "used/one.md")
        XCTAssertThrowsError(try Vault(root: root.appendingPathComponent("used", isDirectory: true)).create())
    }

    func testWriteThenReadReturnsTheFile() throws {
        try vault.write("---\ntitle: Written\n---\n\n# Written\n", to: "drafts/new.md")
        let file = try vault.read("drafts/new.md")
        XCTAssertEqual(file.relativePath, "drafts/new.md")
        XCTAssertEqual(file.title, "Written")
        XCTAssertEqual(file.body, "\n# Written\n")
        XCTAssertTrue(file.isText)
    }

    func testWriteRefusesAPathOutsideTheVault() throws {
        XCTAssertThrowsError(try vault.write("bad", to: "../escape.md"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("escape.md").path))
    }
}
