import XCTest
@testable import PiperCommands

/// Tests the prompt that `WikiAgent` sends. These tests start no process.
final class WikiAgentJobTests: XCTestCase {
    private let capture = WikiCommand(
        name: "capture",
        summary: "Fetch a page",
        argumentHint: "<url>",
        scope: .wiki
    )
    private let whip = WikiSkill(name: "whip", summary: "Rewrite prose.", scope: .personal)

    func testCommandPromptIsASlashCommand() {
        let job = WikiAgentJob.command(capture)

        XCTAssertEqual(job.prompt(arguments: "https://example.com"), "/capture https://example.com")
    }

    func testCommandPromptWithoutArgumentsIsTheNameAlone() {
        let job = WikiAgentJob.command(capture)

        XCTAssertEqual(job.prompt(arguments: ""), "/capture")
        XCTAssertEqual(job.prompt(arguments: "   \n"), "/capture")
    }

    func testSkillPromptAsksForTheSkillByName() {
        let job = WikiAgentJob.skill(whip)

        XCTAssertEqual(job.prompt(arguments: "tighten this"), "Use the whip skill. tighten this")
    }

    func testSkillPromptWithoutArgumentsIsTheSentenceAlone() {
        let job = WikiAgentJob.skill(whip)

        XCTAssertEqual(job.prompt(arguments: "  "), "Use the whip skill.")
    }

    func testJobCarriesTheNameScopeAndDirectory() {
        XCTAssertEqual(WikiAgentJob.command(capture).name, "capture")
        XCTAssertEqual(WikiAgentJob.command(capture).scope, .wiki)
        XCTAssertEqual(WikiAgentJob.command(capture).directoryPath, ".claude/commands")
        XCTAssertEqual(WikiAgentJob.skill(whip).scope, .personal)
        XCTAssertEqual(WikiAgentJob.skill(whip).directoryPath, ".claude/skills")
    }

    func testACommandAndASkillOfOneNameAreDifferentJobs() {
        let command = WikiAgentJob.command(
            WikiCommand(name: "docs", summary: "", argumentHint: "", scope: .wiki)
        )
        let skill = WikiAgentJob.skill(WikiSkill(name: "docs", summary: "", scope: .wiki))

        XCTAssertNotEqual(command.id, skill.id)
        XCTAssertNotEqual(command, skill)
    }

    @MainActor
    func testTheAllowedToolListIsUnchanged() {
        XCTAssertEqual(
            WikiAgent.tools,
            ["Read", "Write", "Edit", "Glob", "Grep", "WebFetch", "Bash(python3:*)"]
        )
    }

    @MainActor
    func testAFreshAgentIsNotRunning() {
        let agent = WikiAgent()

        XCTAssertFalse(agent.isRunning)
        XCTAssertNil(agent.running)
        XCTAssertEqual(agent.transcript, "")
    }
}
