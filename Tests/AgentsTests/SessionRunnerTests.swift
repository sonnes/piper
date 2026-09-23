import CapturesDatabase
import Foundation
import XCTest
@testable import Agents

@MainActor
final class SessionRunnerTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("agents-sessions-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try FileManager.default.removeItem(at: folder) }

    /// Writes a script that stands in for `claude`. It records its arguments,
    /// names its session, and runs `turn` for each user message and `reply`
    /// for each permission reply.
    private func fakeClaude(turn: String, reply: String = "") throws -> URL {
        let url = folder.appendingPathComponent("claude-\(UUID().uuidString)")
        let script = """
        #!/bin/sh
        echo "$@" >> args.txt
        echo '{"type":"system","subtype":"init","session_id":"s-1"}'
        while IFS= read -r line; do
          case "$line" in
            *'"control_response"'*)
              printf '%s\\n' "$line" >> replies.txt
              \(reply)
              ;;
            *'"type":"user"'*)
              printf '%s\\n' "$line" >> inputs.txt
              \(turn)
              ;;
          esac
        done
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private static let result = #"echo '{"type":"result","subtype":"success","is_error":false,"result":"ok","duration_ms":1200,"total_cost_usd":0.01}'"#

    private func runner(_ executable: URL?, database: Database? = nil) -> SessionRunner {
        let runner = SessionRunner(database: database)
        runner.executable = executable
        runner.usesLoginShell = false
        return runner
    }

    private func wait(_ message: String = "The condition did not hold in time", until condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail(message)
        throw XCTSkip(message)
    }

    private func lines(_ name: String) -> [String] {
        let text = (try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    private func start(_ runner: SessionRunner, _ text: String = "Hello") -> AgentSession {
        let session = runner.newSession(in: folder.path)
        runner.send(text, to: session)
        return session
    }

    // MARK: - Turns

    func testCompactFollowUpUsesTheSameSessionAndShowsCommandOutput() async throws {
        let claude = try fakeClaude(turn: """
        echo '{"type":"system","subtype":"init","session_id":"s-1","slash_commands":["compact","context"]}'
        echo '{"type":"result","subtype":"success","is_error":false,"result":"Not enough messages to compact."}'
        """)
        let runner = runner(claude)
        defer { runner.stopAll() }
        let session = start(runner)
        try await wait { session.state == .idle }
        XCTAssertEqual(session.slashCommands, ["compact", "context"])

        runner.send("/compact keep decisions", context: ["/tmp/page.md"], to: session)
        try await wait { session.state == .idle && lines("inputs.txt").count == 2 }
        XCTAssertEqual(lines("args.txt").count, 1)
        let input = try XCTUnwrap(lines("inputs.txt").last?.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: input) as? [String: Any])
        let message = try XCTUnwrap(object["message"] as? [String: Any])
        let content = try XCTUnwrap(message["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["text"] as? String, "/compact keep decisions")
        XCTAssertEqual(session.lastPrompt, "/compact keep decisions")
        XCTAssertEqual(session.claudeSessionID, "s-1")
        guard case .assistant(_, let output) = session.blocks[session.blocks.count - 2] else {
            return XCTFail("The command output is missing")
        }
        XCTAssertEqual(output, "Not enough messages to compact.")
    }

    func testTurnRecordsTextToolsAndResultThenReusesTheProcess() async throws {
        let claude = try fakeClaude(turn: """
        mkdir -p sources; printf 'x' > sources/page.md
        echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Filing it."}]}}'
        printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Write","input":{"file_path":"%s/sources/page.md"}}]}}\\n' "$PWD"
        echo '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"written"}]}}'
        \(Self.result)
        """)
        let runner = runner(claude)
        runner.model = "sonnet"
        let session = start(runner, "Save this page")
        XCTAssertEqual(session.state, .running)

        try await wait { session.state == .idle }
        XCTAssertEqual(session.claudeSessionID, "s-1")
        XCTAssertTrue(session.unread)
        XCTAssertEqual(session.files, ["sources/page.md"])
        XCTAssertEqual(session.title, "Save this page")
        XCTAssertEqual(session.totalCost, 0.01, accuracy: 0.0001)
        guard case .toolCall(let call) = session.blocks[2] else { return XCTFail("No tool call") }
        XCTAssertTrue(call.isFinished)
        XCTAssertEqual(call.resultPreview, "written")
        XCTAssertEqual(lines("args.txt"), ["-p --input-format stream-json --output-format stream-json --verbose --permission-prompt-tool stdio --permission-mode auto --model sonnet"])
        XCTAssertTrue(lines("inputs.txt").first?.contains(#""text":"Save this page""#) == true)

        runner.send("And again", to: session)
        try await wait { session.state == .idle && lines("inputs.txt").count == 2 }
        XCTAssertEqual(lines("args.txt").count, 1)
        runner.stopAll()
    }

    func testMessageAfterAStopResumesTheSession() async throws {
        let runner = runner(try fakeClaude(turn: ""))
        runner.permissionMode = .ask
        let session = start(runner)
        try await wait { lines("inputs.txt").count == 1 }
        runner.stop(session)
        try await wait { session.state == .idle }

        runner.send("Later", to: session)
        try await wait { lines("args.txt").count == 2 && lines("inputs.txt").count == 2 }
        XCTAssertTrue(lines("args.txt")[1].hasSuffix("--permission-mode manual --resume s-1"), lines("args.txt")[1])
        runner.stopAll()
    }

    /// An idle process waits on its input. Its output must not hold a thread,
    /// or a few idle sessions stop every new session from reading its output.
    func testIdleSessionsDoNotBlockNewSessions() async throws {
        let runner = runner(try fakeClaude(turn: Self.result))
        let sessions = (0..<8).map { start(runner, "Session \($0)") }
        try await wait { sessions.allSatisfy { $0.state == .idle } }
        runner.stopAll()
    }

    // MARK: - Cards

    func testAllowAndDenyAnswerTheRequest() async throws {
        let claude = try fakeClaude(turn: """
        echo '{"type":"control_request","request_id":"r1","request":{"subtype":"can_use_tool","tool_name":"Write","input":{"file_path":"/w/a.md","content":"hi"},"tool_use_id":"t1"}}'
        """, reply: """
        echo '{"type":"result","subtype":"success","is_error":false,"result":"ok","permission_denials":[{"tool_name":"Write","tool_use_id":"t1","tool_input":{"file_path":"/w/a.md"}}]}'
        """)
        let runner = runner(claude)
        let session = start(runner)
        try await wait { session.state == .needsYou }
        let request = try XCTUnwrap(session.pendingRequest)
        XCTAssertEqual(runner.attentionCount, 1)

        runner.allow(request, in: session)
        XCTAssertEqual(session.state, .running)
        try await wait { session.state != .running }
        let reply = try XCTUnwrap(lines("replies.txt").first)
        XCTAssertTrue(reply.contains(#""request_id":"r1""#))
        XCTAssertTrue(reply.contains(#""behavior":"allow""#))
        XCTAssertTrue(reply.contains(#""content":"hi""#))
        // The result lists t1 as denied, but the reader did not deny it, so the turn fails.
        XCTAssertEqual(session.state, .failed)
        XCTAssertTrue(session.failure?.hasPrefix("Needs permission for Write.") == true)

        runner.send("Try again", to: session)
        try await wait { session.state == .needsYou }
        runner.deny(try XCTUnwrap(session.pendingRequest), message: "Not there", in: session)
        try await wait { session.state == .idle }
        XCTAssertTrue(lines("replies.txt")[1].contains(#""behavior":"deny""#))
        XCTAssertTrue(lines("replies.txt")[1].contains(#""message":"Not there""#))
        XCTAssertNil(session.failure)
        runner.stopAll()
    }

    func testAlwaysWritesTheRuleAndAllowsTheNextCall() async throws {
        let request = #"echo '{"type":"control_request","request_id":"r'$n'","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"python3 x.py"},"tool_use_id":"t'$n'"}}'"#
        let claude = try fakeClaude(turn: "n=1; " + request, reply: """
        if [ "$n" = 1 ]; then n=2; \(request); else \(Self.result); fi
        """)
        let runner = runner(claude)
        let session = start(runner)
        try await wait { session.state == .needsYou }
        runner.allow(try XCTUnwrap(session.pendingRequest), always: true, in: session)
        try await wait { session.state == .idle }

        XCTAssertEqual(lines("replies.txt").count, 2)
        XCTAssertEqual(session.blocks.filter { if case .permission = $0 { return true } else { return false } }.count, 1)
        XCTAssertTrue(session.blocks.contains(where: { if case .permission(_, .allowedAlways) = $0 { return true } else { return false } }))
        let settings = try String(contentsOf: folder.appendingPathComponent(".claude/settings.local.json"), encoding: .utf8)
        XCTAssertTrue(settings.contains("Bash(python3:*)"))
        runner.stopAll()
    }

    func testQuestionTakesTheAnswers() async throws {
        let claude = try fakeClaude(turn: """
        echo '{"type":"control_request","request_id":"q1","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","input":{"questions":[{"question":"Which color?","header":"Color","options":[{"label":"Red","description":""},{"label":"Blue","description":""}],"multiSelect":false}]},"tool_use_id":"t1"}}'
        """, reply: Self.result)
        let runner = runner(claude)
        let session = start(runner)
        try await wait { session.state == .needsYou }
        guard case .question(let request, nil)? = session.blocks.last else { return XCTFail("No question") }

        runner.answer(request, answers: ["Which color?": "Blue"], in: session)
        try await wait { session.state == .idle }
        XCTAssertTrue(lines("replies.txt").first?.contains(#""answers":{"Which color?":"Blue"}"#) == true)
        guard case .question(_, let answers)? = session.blocks.first(where: { $0.id == "request-q1" }) else { return XCTFail("No question") }
        XCTAssertEqual(answers, ["Which color?": "Blue"])
        runner.stopAll()
    }

    func testMessageWhileACardWaitsAnswersTheCard() async throws {
        let claude = try fakeClaude(turn: """
        echo '{"type":"control_request","request_id":"q1","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","input":{"questions":[{"question":"Which docs?","header":"Docs","options":[{"label":"A","description":""}],"multiSelect":false}]},"tool_use_id":"t1"}}'
        """, reply: Self.result)
        let runner = runner(claude)
        let session = start(runner, "Go in depth of it docs")
        try await wait { session.state == .needsYou }

        runner.send("The projects docs", to: session)
        try await wait { session.state == .idle }
        let reply = try XCTUnwrap(lines("replies.txt").first)
        XCTAssertTrue(reply.contains(#""behavior":"deny""#))
        XCTAssertTrue(reply.contains("The projects docs"))
        XCTAssertEqual(lines("inputs.txt").count, 1)
        XCTAssertNil(session.failure)
        guard case .question(_, let answers)? = session.blocks.first(where: { $0.id == "request-q1" }) else { return XCTFail("No question") }
        XCTAssertEqual(answers, [:])
        runner.stopAll()
    }

    // MARK: - Ending

    func testStopFailuresAndMissingExecutable() async throws {
        let runner = runner(try fakeClaude(turn: ""))
        let session = start(runner)
        try await wait { runner.activeCount == 1 && lines("inputs.txt").count == 1 }
        runner.stop(session)
        try await wait { session.state == .idle }
        guard case .result(_, let result)? = session.blocks.last else { return XCTFail("No result") }
        XCTAssertEqual(result.failure, "Stopped.")

        let crashed = self.runner(try fakeClaude(turn: "echo boom >&2; exit 3"))
        let crash = start(crashed)
        try await wait { crash.state == .failed }
        XCTAssertEqual(crash.failure, "boom")

        let missing = self.runner(nil)
        let lost = start(missing)
        XCTAssertEqual(lost.state, .failed)
        XCTAssertTrue(lost.failure?.contains("Settings > Claude") == true)
    }

    func testTurnTimeoutStopsTheTurn() async throws {
        let runner = runner(try fakeClaude(turn: ""))
        runner.turnTimeout = 0.3
        let session = start(runner)
        try await wait { session.state == .failed }
        XCTAssertTrue(session.failure?.hasPrefix("Stopped after ") == true, session.failure ?? "")
    }

    func testConcurrencyQueuesTurnsAndStopAllDeniesACard() async throws {
        let claude = try fakeClaude(turn: """
        echo '{"type":"control_request","request_id":"r1","request":{"subtype":"can_use_tool","tool_name":"Edit","input":{"file_path":"/w/a.md"},"tool_use_id":"t1"}}'
        """)
        let runner = runner(claude)
        runner.concurrency = 1
        let first = start(runner, "One")
        let second = start(runner, "Two")
        XCTAssertEqual(first.state, .running)
        XCTAssertEqual(second.state, .waiting)
        try await wait { first.state == .needsYou }
        XCTAssertEqual(second.state, .waiting)

        runner.stop(second)
        XCTAssertEqual(second.state, .idle)
        runner.stopAll()
        try await wait { !first.isActive }
        XCTAssertTrue(first.blocks.contains(where: { if case .permission(_, .denied) = $0 { return true } else { return false } }))
        XCTAssertEqual(runner.activeCount, 0)
    }

    func testSessionsSurviveARestartAndActiveOnesBecomeIdle() async throws {
        let url = folder.appendingPathComponent("notes.sqlite")
        let runner = runner(try fakeClaude(turn: Self.result), database: try Database(url: url))
        let note = UUID()
        let done = runner.newSession(in: folder.path, noteID: note, command: SlashCommand(name: "capture", arguments: "x"))
        runner.send("/capture x", to: done)
        try await wait { done.state == .idle }
        runner.executable = try fakeClaude(turn: "")
        let active = start(runner, "Slow")
        _ = runner.newSession(in: folder.path)

        let reopened = SessionRunner(database: try Database(url: url))

        XCTAssertEqual(reopened.sessions.map(\.id), [active.id, done.id])
        XCTAssertEqual(reopened.latestSession(for: note)?.state, .idle)
        XCTAssertEqual(reopened.session(active.id)?.state, .idle)
        guard case .result(_, let result)? = reopened.session(active.id)?.blocks.last else { return XCTFail("No result") }
        XCTAssertEqual(result.failure, "Piper quit before the turn finished.")
        XCTAssertEqual(reopened.folders(), [folder.path])
        XCTAssertEqual(reopened.sessions(in: folder.path).first?.id, active.id)

        reopened.delete(try XCTUnwrap(reopened.session(done.id)))
        XCTAssertEqual(SessionRunner(database: try Database(url: url)).sessions.map(\.id), [active.id])
        runner.stopAll()
    }
}
