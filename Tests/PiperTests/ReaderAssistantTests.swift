import Agents
import Captures
import XCTest
@testable import Piper

@MainActor
final class ReaderAssistantTests: XCTestCase {
    private var root: URL!
    private var suite: String!
    private var preferences: UserDefaults!
    private var store: CaptureStore!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("reader-assistant-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "ReaderAssistantTests." + UUID().uuidString
        preferences = UserDefaults(suiteName: suite)!
        store = CaptureStore(url: root.appendingPathComponent("notes.sqlite"))
    }

    override func tearDown() async throws {
        preferences.removePersistentDomain(forName: suite)
        store = nil
        try FileManager.default.removeItem(at: root)
    }

    /// A stand-in for `claude`. It records each message, waits a short time,
    /// and answers with "Answer 1", "Answer 2", and so on.
    private func fakeClaude() throws -> URL {
        let url = root.appendingPathComponent("claude")
        let script = """
        #!/bin/sh
        echo '{"type":"system","subtype":"init","session_id":"s-1"}'
        n=0
        while IFS= read -r line; do
          n=$((n+1))
          printf '%s\\n' "$line" >> "\(root.path)/inputs.txt"
          sleep 0.2
          echo '{"type":"result","subtype":"success","is_error":false,"result":"Answer '$n'"}'
        done
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func makeAssistant(executable: URL?) -> (ReaderAssistant, FolderAgents) {
        let agents = FolderAgents(store: store, preferences: preferences)
        agents.runner.executable = executable
        agents.runner.usesLoginShell = false
        let assistant = ReaderAssistant(store: store, agents: agents)
        assistant.folder = { [root] in root?.path }
        return (assistant, agents)
    }

    private func capture() throws -> UUID {
        XCTAssertTrue(store.add("https://example.com/article"))
        return try XCTUnwrap(store.notes.last?.id)
    }

    private let article = ReaderArticle(url: URL(string: "https://example.com/article")!, site: "example.com",
                                        title: "An Article", author: "",
                                        blocks: [.init(kind: "paragraph", text: "The first paragraph of the article.")])

    private func anchor(_ quote: String) -> NoteAnchor { NoteAnchor(quote: quote, block: 0, offset: 0) }

    private func wait(until condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("The condition did not hold in time")
        throw XCTSkip("The condition did not hold in time")
    }

    private func text(of id: UUID) -> String { store.notes.first { $0.id == id }?.text ?? "" }

    private func inputs() -> [String] {
        let text = (try? String(contentsOf: root.appendingPathComponent("inputs.txt"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    // MARK: - Tests

    func testSecondQuestionWaitsForTheFirstAnswerAndEachAnswerGoesToItsNote() async throws {
        let (assistant, agents) = makeAssistant(executable: try fakeClaude())
        defer { agents.runner.stopAll() }
        let parent = try capture()
        let first = try XCTUnwrap(assistant.ask(.explain, about: anchor("first passage"), in: parent, article: article))
        let second = try XCTUnwrap(assistant.ask(.define, about: anchor("second"), in: parent, article: article))
        XCTAssertEqual(assistant.waitingNotes, [first.id, second.id])
        XCTAssertEqual(agents.runner.sessions.count, 1)

        try await wait { assistant.waitingNotes.isEmpty }
        XCTAssertTrue(text(of: first.id).hasSuffix("Answer 1"), text(of: first.id))
        XCTAssertTrue(text(of: second.id).hasSuffix("Answer 2"), text(of: second.id))
        XCTAssertTrue(assistant.failures.isEmpty)
        // One message per turn. Only the first message carries the article.
        XCTAssertEqual(inputs().count, 2)
        XCTAssertTrue(inputs()[0].contains("The first paragraph of the article."))
        XCTAssertFalse(inputs()[1].contains("The first paragraph of the article."))
        XCTAssertEqual(assistant.session(for: parent)?.purpose, .margin)
    }

    func testMarginSessionLookupSkipsAnOrdinarySessionOfTheSameNote() throws {
        let (assistant, agents) = makeAssistant(executable: nil)
        let parent = try capture()
        let question = try XCTUnwrap(store.addChild("Explain: x", to: parent, tags: [ReaderAssistant.questionTag]))
        XCTAssertNil(assistant.session(for: parent))

        let margin = agents.newMarginSession(in: root.path, noteID: question.id)
        _ = agents.runner.newSession(in: root.path, noteID: question.id)
        XCTAssertEqual(assistant.session(for: parent)?.id, margin.id)
    }

    func testFailedTurnRecordsTheFailureOfTheNote() async throws {
        let (assistant, _) = makeAssistant(executable: nil)
        let parent = try capture()
        let note = try XCTUnwrap(assistant.ask(.explain, about: anchor("passage"), in: parent, article: article))
        try await wait { assistant.waitingNotes.isEmpty }
        XCTAssertTrue(assistant.failures[note.id]?.contains("Settings > AI") == true, assistant.failures[note.id] ?? "")
        XCTAssertEqual(text(of: note.id), "Explain: passage")
    }
}
