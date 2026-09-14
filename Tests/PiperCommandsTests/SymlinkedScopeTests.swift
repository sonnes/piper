import XCTest
import PiperCommands

/// A symlinked `.claude/skills` folder, which is what a dotfiles setup produces.
///
/// The URL form of `contentsOfDirectory` fails with ENOTDIR on a symlink, so a
/// scan that does not resolve the link finds nothing and reports no error.
final class SymlinkedScopeTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("piper-symlink-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    private func makeSkill(in root: URL, named name: String, description: String) throws {
        let directory = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("---\nname: \(name)\ndescription: \(description)\n---\n\nBody.\n".utf8)
            .write(to: directory.appendingPathComponent("SKILL.md"))
    }

    func testASymlinkedSkillsFolderIsRead() throws {
        let real = folder.appendingPathComponent("dotfiles/skills")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try makeSkill(in: real, named: "whip", description: "Rewrite prose. It also audits tropes.")

        let home = folder.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".claude/skills"), withDestinationURL: real)

        let skills = SkillIndex.all(wikiRoot: folder.appendingPathComponent("absent"), homeRoot: home)
        XCTAssertEqual(skills.map(\.name), ["whip"])
        XCTAssertEqual(skills.first?.summary, "Rewrite prose.")
        XCTAssertEqual(skills.first?.scope, .personal)
    }

    func testASymlinkedCommandsFolderIsRead() throws {
        let real = folder.appendingPathComponent("dotfiles/commands")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try Data("---\ndescription: Commit the changes\nargument-hint: <message>\n---\n\nBody.\n".utf8)
            .write(to: real.appendingPathComponent("commit.md"))

        let home = folder.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".claude/commands"), withDestinationURL: real)

        let commands = CommandIndex.all(wikiRoot: folder.appendingPathComponent("absent"), homeRoot: home)
        XCTAssertEqual(commands.map(\.name), ["commit"])
        XCTAssertEqual(commands.first?.argumentHint, "<message>")
    }

    /// Reads the real home folder. It asserts shape, not contents, so it passes
    /// on a machine that defines no skills.
    func testTheRealHomeFolderProducesOneLineSummaries() {
        let skills = SkillIndex.all(wikiRoot: folder.appendingPathComponent("absent"))
        XCTAssertFalse(skills.contains { $0.summary.contains("\n") }, "A row summary must be one line")
        XCTAssertFalse(skills.contains { $0.name.isEmpty }, "Every skill needs a name")
    }
}
