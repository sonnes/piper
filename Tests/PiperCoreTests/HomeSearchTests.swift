import XCTest
@testable import PiperCore

final class HomeSearchTests: XCTestCase {
    private var parser: HomeSearch {
        HomeSearch(
            actions: [
                HomeAction(title: "New Capture", detail: "Open the capture panel", shortcut: "⌘1") {},
                HomeAction(title: "Payment Report", detail: "Show this month") {}
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
        let parser = HomeSearch(actions: [HomeAction(title: "Run Me") { ran = true }])

        guard let first = parser.suggestions(for: ">run").first, case .action(let action) = first.target else {
            return XCTFail("Expected an action target")
        }
        action.run()
        XCTAssertTrue(ran)
    }

    // MARK: - Free Text

    func testFreeTextRanksFileNamesThenFileTextThenActions() {
        let rows = parser.suggestions(for: "payment", files: files)

        XCTAssertEqual(rows.map(\.kind), [.file, .fileText, .action])
        XCTAssertEqual(rows.map(\.title), [
            "payment-retries.md", "q3.md", "Payment Report"
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

    func testSlashSearchesLiteralFileText() {
        let file = FileCandidate(url: URL(fileURLWithPath: "/w/note.md"), excerpt: "Run /hello locally.")
        let rows = parser.suggestions(for: "/hello", files: [file])
        XCTAssertEqual(rows.map(\.kind), [.fileText])
        XCTAssertEqual(rows.first?.title, "note.md")
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
