import XCTest
@testable import PiperCommands

final class CommandParserTests: XCTestCase {
    private let capture = WikiCommand(
        name: "capture",
        summary: "Fetch a payment page and save it",
        argumentHint: "<url>",
        scope: .wiki
    )
    private let review = WikiCommand(
        name: "review",
        summary: "List stale files",
        argumentHint: "",
        scope: .personal
    )
    private let reading = WikiSkill(
        name: "reading-notes",
        summary: "Turn a saved article into a payment reading note.",
        scope: .wiki
    )
    private let whip = WikiSkill(name: "whip", summary: "Rewrite prose.", scope: .personal)

    private var parser: CommandParser {
        CommandParser(
            commands: [capture, review],
            skills: [reading, whip],
            actions: [
                CommandAction(title: "New Capture", detail: "Open the capture panel", shortcut: "⌘1") {},
                CommandAction(title: "Payment Report", detail: "Show this month") {}
            ]
        )
    }

    private var files: [FileCandidate] {
        [
            FileCandidate(
                url: URL(fileURLWithPath: "/w/engineering/payment-retries.md"),
                folder: "engineering",
                excerpt: "Retries are capped at three attempts."
            ),
            FileCandidate(
                url: URL(fileURLWithPath: "/w/meeting-notes/q3.md"),
                folder: "meeting-notes",
                excerpt: "Payment volume and the retries backlog."
            ),
            FileCandidate(url: URL(fileURLWithPath: "/w/queue.md"), excerpt: "Posts to read.")
        ]
    }

    // MARK: - Empty Input

    func testEmptyTextGivesNoRows() {
        XCTAssertTrue(parser.suggestions(for: "").isEmpty)
        XCTAssertTrue(parser.suggestions(for: "   \n ").isEmpty)
    }

    // MARK: - Slash

    func testSlashListsCommandsBeforeSkills() {
        let rows = parser.suggestions(for: "/re")

        // "capture" and "review" both hold "re", and so does the skill name.
        XCTAssertEqual(rows.map(\.kind), [.command, .command, .skill])
        XCTAssertEqual(rows.map(\.title), ["/capture <url>", "/review", "/reading-notes"])
    }

    func testSlashAloneListsEveryCommandThenEverySkill() {
        let rows = parser.suggestions(for: "/")

        XCTAssertEqual(rows.map(\.kind), [.command, .command, .skill, .skill])
    }

    func testSlashShowsTheArgumentHintInTheTitle() {
        let rows = parser.suggestions(for: "/capture")

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.title, "/capture <url>")
        XCTAssertEqual(rows.first?.detail, "Fetch a payment page and save it")
    }

    func testSlashCarriesTheArgumentsIntoTheTarget() {
        let rows = parser.suggestions(for: "/capture https://example.com")

        guard let first = rows.first, case .command(let command, let arguments) = first.target else {
            return XCTFail("Expected a command target")
        }
        XCTAssertEqual(command.name, "capture")
        XCTAssertEqual(arguments, "https://example.com")
    }

    func testSlashCarriesTheArgumentsIntoASkillTarget() {
        let rows = parser.suggestions(for: "/whip  tighten this  ")

        guard let first = rows.first, case .skill(let skill, let arguments) = first.target else {
            return XCTFail("Expected a skill target")
        }
        XCTAssertEqual(skill.name, "whip")
        XCTAssertEqual(arguments, "tighten this")
    }

    func testSlashRowShowsThePersonalTagOnlyForThePersonalScope() {
        let rows = parser.suggestions(for: "/")
        let byTitle = Dictionary(uniqueKeysWithValues: rows.map { ($0.title, $0) })

        XCTAssertEqual(byTitle["/capture <url>"]?.tag, "")
        XCTAssertEqual(byTitle["/review"]?.tag, "personal")
        XCTAssertEqual(byTitle["/whip"]?.tag, "personal")
    }

    // MARK: - Greater Than

    func testGreaterThanListsOnlyTheInjectedActions() {
        let rows = parser.suggestions(for: ">")

        XCTAssertEqual(rows.map(\.kind), [.action, .action])
        XCTAssertEqual(rows.map(\.title), ["New Capture", "Payment Report"])
    }

    func testGreaterThanFiltersTheActionsByTitle() {
        let rows = parser.suggestions(for: ">new")

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.title, "New Capture")
        XCTAssertEqual(rows.first?.tag, "⌘1")
    }

    func testGreaterThanRunsTheInjectedClosure() {
        var ran = false
        let parser = CommandParser(actions: [CommandAction(title: "Run Me") { ran = true }])

        guard let first = parser.suggestions(for: ">run").first, case .action(let action) = first.target else {
            return XCTFail("Expected an action target")
        }
        action.run()
        XCTAssertTrue(ran)
    }

    // MARK: - Free Text

    func testFreeTextRanksFileNamesThenFileTextThenCommandsThenSkillsThenActions() {
        let rows = parser.suggestions(for: "payment", files: files)

        XCTAssertEqual(rows.map(\.kind), [.file, .fileText, .command, .skill, .action])
        XCTAssertEqual(rows.map(\.title), [
            "payment-retries.md", "q3.md", "/capture <url>", "/reading-notes", "Payment Report"
        ])
        XCTAssertEqual(Array(rows.map(\.detail).prefix(2)), [
            "engineering/payment-retries.md", "Payment volume and the retries backlog."
        ])
    }

    func testFreeTextListsAFileOnceWhenTheNameAndTheTextBothMatch() {
        let rows = parser.suggestions(for: "retries", files: files)

        XCTAssertEqual(rows.map(\.kind), [.file, .fileText])
        XCTAssertEqual(rows.map(\.title), ["payment-retries.md", "q3.md"])
    }

    func testFreeTextReadsNoFileSystem() {
        let rows = parser.suggestions(for: "payment")

        XCTAssertTrue(rows.allSatisfy { $0.kind != .file && $0.kind != .fileText })
    }

    // MARK: - Fallback

    func testNoMatchGivesExactlyOneFallbackRow() {
        let rows = parser.suggestions(for: "zzzzz", files: files)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.kind, .fallback)
        guard let first = rows.first, case .searchEverything(let text) = first.target else {
            return XCTFail("Expected a search target")
        }
        XCTAssertEqual(text, "zzzzz")
    }

    func testNoSlashMatchGivesExactlyOneFallbackRow() {
        let rows = parser.suggestions(for: "/zzzzz")

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.kind, .fallback)
    }

    func testNoActionMatchGivesExactlyOneFallbackRow() {
        let rows = parser.suggestions(for: ">zzzzz")

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.kind, .fallback)
    }
}
