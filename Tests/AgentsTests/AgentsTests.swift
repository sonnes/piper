import CapturesDatabase
import Foundation
import XCTest
import Agents

final class SlashCommandTests: XCTestCase {

    func testParsesNameAndArguments() {
        XCTAssertEqual(SlashCommand("/capture https://example.com  note "),
                       SlashCommand(name: "capture", arguments: "https://example.com  note"))
        XCTAssertEqual(SlashCommand("/stale")?.prompt, "/stale")
        XCTAssertEqual(SlashCommand("/new Decision\nbody")?.arguments, "Decision\nbody")
        XCTAssertEqual(SlashCommand("/okf:new title")?.name, "okf:new")
    }

    func testRejectsTextThatIsNotACommand() {
        XCTAssertNil(SlashCommand("capture"))
        XCTAssertNil(SlashCommand("/"))
        XCTAssertNil(SlashCommand("/ capture"))
        XCTAssertNil(SlashCommand("/usr/bin/env"))
    }

    func testPartialNameOnlyWhileTypingTheName() {
        XCTAssertEqual(SlashCommand.partialName("/"), "")
        XCTAssertEqual(SlashCommand.partialName("/cap"), "cap")
        XCTAssertNil(SlashCommand.partialName("/capture url"))
        XCTAssertNil(SlashCommand.partialName("/usr/bin"))
        XCTAssertNil(SlashCommand.partialName("note"))
    }
}

final class FolderSkillTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("agents-skills-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    private func skill(_ directory: String, _ text: String) throws {
        let url = folder.appendingPathComponent(".claude/skills/\(directory)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try text.write(to: url.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    func testLoadsFrontmatterAndSkipsHiddenOrInvalidSkills() throws {
        try skill("capture", "---\nname: capture\ndescription: Fetch a URL. Use when asked.\nargument-hint: <url> [note]\n---\nBody")
        try skill("index", "---\nname: index\ndescription: Rebuild indexes.\n---\n")
        try skill("plain", "No frontmatter")
        try skill("hidden", "---\nname: hidden\nuser-invocable: false\n---\n")
        try skill("bad", "---\nname: two words\n---\n")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".claude/skills/empty"), withIntermediateDirectories: true)

        let skills = FolderSkill.load(from: folder)

        XCTAssertEqual(skills.map(\.name), ["capture", "index", "plain"])
        XCTAssertEqual(skills[0].argumentHint, "<url> [note]")
        XCTAssertEqual(skills[0].summary, "Fetch a URL")
        XCTAssertEqual(skills[1].summary, "Rebuild indexes.")
    }

    func testFolderWithoutSkillsHasNone() {
        XCTAssertEqual(FolderSkill.load(from: folder), [])
    }

    func testPreferredSkillUsesStoredChoiceThenConvention() {
        let skills = ["ask", "capture", "new"].map { FolderSkill(name: $0) }
        XCTAssertEqual(FolderSkill.preferred(in: skills, forLink: true, stored: nil)?.name, "capture")
        XCTAssertEqual(FolderSkill.preferred(in: skills, forLink: false, stored: nil)?.name, "new")
        XCTAssertEqual(FolderSkill.preferred(in: skills, forLink: true, stored: "ask")?.name, "ask")
        XCTAssertEqual(FolderSkill.preferred(in: skills, forLink: true, stored: "gone")?.name, "capture")
        XCTAssertNil(FolderSkill.preferred(in: [FolderSkill(name: "ask")], forLink: false, stored: nil))
    }
}

final class SkillTargetTests: XCTestCase {

    func testTargetCarriesItsArgumentAndNote() {
        let id = UUID()
        XCTAssertEqual(SkillTarget.page("/w/a.md").argument, "/w/a.md")
        XCTAssertEqual(SkillTarget.text("note", noteID: id).noteID, id)
        XCTAssertEqual(SkillTarget.folder.argument, "")
    }
}
