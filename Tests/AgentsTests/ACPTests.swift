import Foundation
import XCTest
@testable import Agents

final class ACPMessageTests: XCTestCase {

    func testJSONRPCReadsEachKindAndWritesOneLine() throws {
        XCTAssertEqual(JSONRPCMessage.parse(#"{"jsonrpc":"2.0","id":3,"result":{"stopReason":"end_turn"}}"#),
                       .response(id: .number(3), result: .object(["stopReason": .string("end_turn")])))
        XCTAssertEqual(JSONRPCMessage.parse(#"{"jsonrpc":"2.0","id":4,"error":{"code":-32000,"message":"Auth required"}}"#),
                       .error(id: .number(4), code: -32000, message: "Auth required"))
        XCTAssertEqual(JSONRPCMessage.parse(#"{"jsonrpc":"2.0","method":"session/update","params":{}}"#),
                       .notification(method: "session/update", params: .object([:])))
        XCTAssertEqual(JSONRPCMessage.parse(#"{"jsonrpc":"2.0","id":"p1","method":"fs/read_text_file","params":{}}"#),
                       .request(id: .string("p1"), method: "fs/read_text_file", params: .object([:])))
        XCTAssertNil(JSONRPCMessage.parse("not json"))

        let line = JSONRPCMessage.request(id: .number(1), method: "session/new",
                                          params: .object(["cwd": .string("/w/a b")])).line
        XCTAssertFalse(line.contains("\n"))
        XCTAssertTrue(line.contains(#""id":1,"#) || line.contains(#""id":1}"#), line)
        XCTAssertTrue(line.contains(#""cwd":"/w/a b""#), line)
    }

    func testSessionUpdatesReadToolCallsOptionsAndUsage() throws {
        func update(_ text: String) throws -> ACP.SessionUpdate {
            let data = try XCTUnwrap(text.data(using: .utf8))
            return ACP.SessionUpdate(json: JSONValue(try JSONSerialization.jsonObject(with: data)))
        }
        let call = try update("""
        {"sessionUpdate":"tool_call","toolCallId":"t1","title":"Edit a.md","kind":"edit","status":"pending",
         "locations":[{"path":"/w/a.md"}],
         "content":[{"type":"diff","path":"/w/a.md","oldText":"x","newText":"y"},
                    {"type":"content","content":{"type":"text","text":"done"}}]}
        """)
        XCTAssertEqual(call, .toolCall(ACP.ToolCallUpdate(id: "t1", title: "Edit a.md", kind: .edit, status: .pending,
                                                         paths: ["/w/a.md"],
                                                         diffs: [ACP.Diff(path: "/w/a.md", oldText: "x", newText: "y")],
                                                         text: "done")))
        XCTAssertEqual(try update(#"{"sessionUpdate":"tool_call_update","toolCallId":"t1","kind":"brand_new","status":"failed"}"#),
                       .toolCallUpdate(ACP.ToolCallUpdate(id: "t1", kind: .other, status: .failed)))
        XCTAssertEqual(try update(#"{"sessionUpdate":"usage_update","used":1200,"size":200000,"cost":{"amount":0.03,"currency":"USD"}}"#),
                       .usage(used: 1200, size: 200000, costUSD: 0.03))
        XCTAssertEqual(try update(#"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Hi"}}"#),
                       .agentMessage("Hi"))
        guard case .configOptions(let options) = try update("""
        {"sessionUpdate":"config_option_update","configOptions":[
          {"type":"select","id":"model","name":"Model","category":"model","currentValue":"b",
           "options":[{"group":"g","name":"Fast","options":[{"value":"a","name":"A"}]},{"group":"h","name":"Smart","options":[{"value":"b","name":"B"}]}]},
          {"type":"boolean","id":"fast","name":"Fast","currentValue":true}]}
        """) else { return XCTFail("No options") }
        XCTAssertEqual(options.map(\.id), ["model"])
        XCTAssertEqual(options.first?.values.map(\.id), ["a", "b"])
        XCTAssertEqual(try update(#"{"sessionUpdate":"something_new"}"#), .other)
    }

    func testOlderModelListBecomesTheModelOption() throws {
        let json = #"{"models":{"currentModelId":"a/b","availableModels":[{"modelId":"a/b","name":"A B"},{"modelId":"c"}]},"modes":{"currentModeId":"build","availableModes":[{"id":"build","name":"build"}]}}"#
        let setup = ACP.SessionSetup(sessionID: "s", json: JSONValue(try JSONSerialization.jsonObject(with: Data(json.utf8))))
        XCTAssertEqual(setup.currentMode, "build")
        let model = try XCTUnwrap(setup.configOptions.first)
        XCTAssertEqual(model.id, ACP.SessionSetup.legacyModelOptionID)
        XCTAssertEqual(model.category, "model")
        XCTAssertEqual(model.currentValue, "a/b")
        XCTAssertEqual(model.values, [.init(id: "a/b", name: "A B"), .init(id: "c", name: "c")])
    }

    func testIntIsNilForAFractionOrANumberOutOfRange() {
        XCTAssertEqual(JSONValue.number(3).int, 3)
        XCTAssertNil(JSONValue.number(1.5).int)
        XCTAssertNil(JSONValue.number(1e300).int)
        XCTAssertNil(JSONValue.number(.nan).int)
        XCTAssertNil(JSONRPCMessage.parse(#"{"jsonrpc":"2.0","id":1e300,"result":{}}"#).flatMap { message -> Int? in
            if case .response(let id, _) = message { return id.int } else { return nil }
        })
    }

    func testReadOnlyModeTakesTheBestMatch() {
        let modes = [ACP.Mode(id: "code", name: "Code"), ACP.Mode(id: "ask", name: "Ask"), ACP.Mode(id: "architect", name: "Plan")]
        XCTAssertEqual(ACP.Mode.readOnly(in: modes)?.id, "architect")
        XCTAssertEqual(ACP.Mode.readOnly(in: [ACP.Mode(id: "auto", name: "Auto"), ACP.Mode(id: "read_only", name: "Safe")])?.id,
                       "read_only")
        XCTAssertEqual(ACP.Mode.readOnly(in: [ACP.Mode(id: "default", name: "Read-Only")])?.id, "default")
        XCTAssertNil(ACP.Mode.readOnly(in: [ACP.Mode(id: "build", name: "Build"), ACP.Mode(id: "planner-x", name: "Planner")]))
    }

    func testClaudeCodeModesComeFromThePermissionModes() {
        XCTAssertEqual(ClaudeCodeConnection.modes.map(\.id), ["auto", "acceptEdits", "manual", "plan", "bypassPermissions"])
        XCTAssertEqual(PermissionMode(rawValue: "plan"), .plan)
    }

    func testOldSnapshotDecodesAsAClaudeCodeSession() throws {
        let json = """
        {"id":"8D8B7E6F-5C4B-4A39-8271-6F5E4D3C2B1A","folder":"/w","claudeSessionID":"s-9","state":"idle",
         "createdAt":0,"updatedAt":0,"unread":false,"blocks":[]}
        """
        let snapshot = try JSONDecoder().decode(AgentSession.Snapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.resumeToken, "s-9")
        XCTAssertNil(snapshot.agentID)
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertTrue(encoded.contains(#""claudeSessionID":"s-9""#))
    }

    func testClaudeCodeMarginSessionGetsOnlyReadAndWebTools() {
        let folder = URL(fileURLWithPath: "/w")
        let margin = ClaudeCodeConnection.arguments(for: SessionConfig(folder: folder, model: "haiku", mode: "auto", purpose: .margin))
        let tools = "Read,Grep,Glob,WebSearch,WebFetch"
        XCTAssertEqual(margin.split(separator: "--tools").count, 2)
        XCTAssertTrue(margin.joined(separator: " ").contains("--tools \(tools) --allowedTools \(tools) --strict-mcp-config"))
        XCTAssertTrue(margin.joined(separator: " ").contains("--model haiku"))
        let session = ClaudeCodeConnection.arguments(for: SessionConfig(folder: folder, resumeToken: "s-1", mode: "plan",
                                                                        purpose: .session))
        XCTAssertFalse(session.contains("--tools"))
        XCTAssertFalse(session.contains("--strict-mcp-config"))
        XCTAssertTrue(session.joined(separator: " ").contains("--permission-mode plan"))
        XCTAssertTrue(session.joined(separator: " ").contains("--resume s-1"))
    }
}

@MainActor
final class ACPAgentTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("acp-agent-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try FileManager.default.removeItem(at: folder) }

    private nonisolated static let newSession = #"{"sessionId":"acp-1","modes":{"currentModeId":"ask","availableModes":[{"id":"ask","name":"Ask"},{"id":"code","name":"Code"}]},"configOptions":[{"type":"select","id":"model","name":"Model","category":"model","currentValue":"m1","options":[{"value":"m1","name":"M1"},{"value":"m2","name":"M2"}]}]}"#

    /// Writes a script that stands in for an ACP agent. It records each line
    /// that it reads, answers `initialize`, `session/new`, `session/load`, and
    /// each change of mode or model, and runs `turn` for each prompt with `$pid`
    /// set to the id of the prompt. `reply` runs for each answer to a
    /// permission request. `newSession` is the result of `session/new`. The
    /// arms in `cases` come first, so they replace the usual answers.
    private func fakeAgent(turn: String, reply: String = "", newSession: String = newSession,
                           cases: String = "") throws -> AgentDefinition {
        let url = folder.appendingPathComponent("agent-\(UUID().uuidString)")
        let script = """
        #!/bin/sh
        say() { printf '%s\\n' "$1"; }
        while IFS= read -r line; do
          printf '%s\\n' "$line" >> received.txt
          id=$(printf '%s' "$line" | sed -n 's/.*"id":\\([0-9]*\\).*/\\1/p')
          case "$line" in
            \(cases)
            *'"method":"initialize"'*)
              say '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{"loadSession":true},"agentInfo":{"name":"fake","version":"1.0"}}}' ;;
            *'"method":"session/new"'*)
              say '{"jsonrpc":"2.0","id":'$id',"result":\(newSession)}' ;;
            *'"method":"session/load"'*)
              say '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"acp-1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"REPLAY"}}}}'
              say '{"jsonrpc":"2.0","id":'$id',"result":{}}' ;;
            *'"method":"session/prompt"'*)
              pid=$id
              \(turn) ;;
            *'"method":"session/set_mode"'*|*'"method":"session/set_config_option"'*|*'"method":"session/set_model"'*)
              say '{"jsonrpc":"2.0","id":'$id',"result":{}}' ;;
            *'"method":"session/cancel"'*)
              say '{"jsonrpc":"2.0","id":'$pid',"result":{"stopReason":"cancelled"}}' ;;
            *'"outcome"'*)
              \(reply) ;;
          esac
        done
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return AgentDefinition(id: "fake", name: "Fake", command: url.path)
    }

    private static func update(_ json: String) -> String {
        #"say '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"acp-1","update":"# + json + "}}'"
    }

    private static let endTurn = #"say '{"jsonrpc":"2.0","id":'$pid',"result":{"stopReason":"end_turn"}}'"#

    private func permission(kind: String, id: Int) -> String {
        #"say '{"jsonrpc":"2.0","id":\#(id),"method":"session/request_permission","params":{"sessionId":"acp-1","toolCall":{"toolCallId":"t\#(id)","title":"\#(kind) a.md","kind":"\#(kind)"},"options":[{"optionId":"yes","name":"Allow","kind":"allow_once"},{"optionId":"always","name":"Always","kind":"allow_always"},{"optionId":"no","name":"Reject","kind":"reject_once"}]}}'"#
    }

    private func runner(_ agent: AgentDefinition) -> SessionRunner {
        let runner = SessionRunner(database: nil)
        runner.agents = [agent]
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

    private func received() -> [String] {
        let text = (try? String(contentsOf: folder.appendingPathComponent("received.txt"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    /// The lines that Piper sent with a method, in order.
    private func received(_ method: String) -> [String] {
        received().filter { $0.contains(#""method":"\#(method)""#) }
    }

    /// The position of the first line that Piper sent with a method.
    private func index(of method: String) -> Int? {
        received().firstIndex { $0.contains(#""method":"\#(method)""#) }
    }

    // MARK: - Turns

    func testAgentStreamsTextAndToolsAndWaitsForAPermission() async throws {
        let agent = try fakeAgent(turn: [
            Self.update(#"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Hel"}}"#),
            Self.update(#"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"lo"}}"#),
            #"printf '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"acp-1","update":{"sessionUpdate":"tool_call","toolCallId":"t1","title":"Write a.md","kind":"edit","status":"pending","locations":[{"path":"%s/a.md"}]}}}\n' "$PWD""#,
            permission(kind: "edit", id: 100)
        ].joined(separator: "\n"), reply: [
            Self.update(#"{"sessionUpdate":"tool_call_update","toolCallId":"t1","status":"completed","content":[{"type":"content","content":{"type":"text","text":"written"}}]}"#),
            Self.update(#"{"sessionUpdate":"usage_update","used":10,"size":100,"cost":{"amount":0.02,"currency":"USD"}}"#),
            Self.endTurn
        ].joined(separator: "\n"))
        let runner = runner(agent)
        defer { runner.stopAll() }
        let session = runner.newSession(in: folder.path, agentID: agent.id)
        runner.send("Write it", to: session)

        try await wait { session.state == .needsYou }
        XCTAssertEqual(session.resumeToken, "acp-1")
        XCTAssertEqual(session.modes.map(\.id), ["ask", "code"])
        XCTAssertEqual(session.configOptions.first?.currentValue, "m1")
        let request = try XCTUnwrap(session.pendingRequest)
        XCTAssertEqual(request.options?.map(\.id), ["yes", "always", "no"])
        XCTAssertEqual(request.kind, .edit)

        runner.respond(request, with: try XCTUnwrap(request.options?[1]), in: session)
        try await wait { session.state == .idle }
        XCTAssertTrue(received().contains { $0.contains(#""optionId":"always""#) && $0.contains(#""id":100"#) })
        XCTAssertTrue(received().first?.contains(#""protocolVersion":1"#) == true)
        guard case .assistant(_, let text) = session.blocks[1] else { return XCTFail("No message") }
        XCTAssertEqual(text, "Hello")
        guard case .toolCall(let call) = session.blocks[2] else { return XCTFail("No tool call") }
        XCTAssertEqual(call.path, "a.md")
        XCTAssertEqual(call.kind, .edit)
        XCTAssertTrue(call.isFinished)
        XCTAssertEqual(call.resultPreview, "written")
        XCTAssertTrue(session.blocks.contains { if case .permission(_, .allowedAlways) = $0 { return true } else { return false } })
        XCTAssertEqual(session.totalCost, 0.02, accuracy: 0.0001)
        XCTAssertEqual(session.files, ["a.md"])
    }

    func testNextProcessLoadsTheSessionAndSkipsTheReplay() async throws {
        let agent = try fakeAgent(turn: Self.update(#"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"ok"}}"#)
                                  + "\n" + Self.endTurn)
        let runner = runner(agent)
        let session = runner.newSession(in: folder.path, agentID: agent.id)
        runner.send("One", to: session)
        try await wait { session.state == .idle }
        runner.stopAll()
        try await Task.sleep(for: .milliseconds(100))

        runner.send("Two", to: session)
        try await wait { session.state == .idle && session.blocks.count == 6 }
        XCTAssertTrue(received().contains { $0.contains(#""method":"session/load""#) && $0.contains(#""sessionId":"acp-1""#) })
        XCTAssertFalse(session.blocks.contains { if case .assistant(_, let text) = $0 { return text.contains("REPLAY") } else { return false } })
        runner.stopAll()
    }

    func testStopCancelsTheTurnAndKeepsTheProcess() async throws {
        let agent = try fakeAgent(turn: ":")
        let runner = runner(agent)
        defer { runner.stopAll() }
        let session = runner.newSession(in: folder.path, agentID: agent.id)
        runner.send("Wait", to: session)
        try await wait { received().contains { $0.contains("session/prompt") } }
        runner.stop(session)
        try await wait { session.state == .idle }
        XCTAssertTrue(received().contains { $0.contains(#""method":"session/cancel""#) })
        guard case .result(_, let result)? = session.blocks.last else { return XCTFail("No result") }
        XCTAssertEqual(result.failure, "Stopped.")

        runner.send("Again", to: session)
        try await wait { received("session/prompt").count == 2 }
        XCTAssertEqual(received("initialize").count, 1)
        XCTAssertEqual(received("session/new").count, 1)
        XCTAssertTrue(received("session/prompt")[1].contains("Again"))
    }

    func testQueuedMessagesGoToTheAgentAsOnePrompt() async throws {
        let agent = try fakeAgent(turn: Self.endTurn)
        let runner = runner(agent)
        defer { runner.stopAll() }
        runner.concurrency = 1
        let first = runner.newSession(in: folder.path, agentID: agent.id)
        let second = runner.newSession(in: folder.path, agentID: agent.id)
        runner.send("First", to: first)
        runner.send("One", context: ["/w/a.md"], to: second)
        runner.send("Two", context: ["/w/a.md", "/w/b.md"], to: second)
        XCTAssertEqual(second.state, .waiting)

        try await wait { first.state == .idle && second.state == .idle }
        let prompts = received("session/prompt")
        XCTAssertEqual(prompts.count, 2)
        XCTAssertTrue(prompts[1].contains(#"One\n\nTwo\n\nContext file: /w/a.md\nContext file: /w/b.md"#), prompts[1])
        XCTAssertEqual(second.blocks.filter { if case .result = $0 { return true } else { return false } }.count, 1)
        XCTAssertNil(second.failure)
    }

    func testPromptWaitsUntilTheSessionOpens() async throws {
        let agent = try fakeAgent(turn: Self.endTurn, cases: #"""
            *'"method":"initialize"'*)
              sleep 0.3
              say '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1}}' ;;
        """#)
        let runner = runner(agent)
        defer { runner.stopAll() }
        let session = runner.newSession(in: folder.path, agentID: agent.id)
        runner.send("Hello", to: session)
        try await wait { session.state == .idle }
        let initialize = try XCTUnwrap(index(of: "initialize"))
        let open = try XCTUnwrap(index(of: "session/new"))
        let prompt = try XCTUnwrap(index(of: "session/prompt"))
        XCTAssertLessThan(initialize, open)
        XCTAssertLessThan(open, prompt)
        XCTAssertEqual(received("session/prompt").count, 1)
    }

    func testInitializeFailureFailsTheTurn() async throws {
        let agent = try fakeAgent(turn: Self.endTurn, cases: #"""
            *'"method":"initialize"'*)
              say '{"jsonrpc":"2.0","id":'$id',"error":{"code":-32000,"message":"Sign in first"}}' ;;
        """#)
        let runner = runner(agent)
        defer { runner.stopAll() }
        let session = runner.newSession(in: folder.path, agentID: agent.id)
        runner.send("Hello", to: session)
        try await wait { session.state == .failed }
        XCTAssertEqual(session.failure, "The agent did not start: Sign in first")
        XCTAssertNil(index(of: "session/new"))
        XCTAssertNil(index(of: "session/prompt"))
    }

    func testFailedLoadStartsANewSession() async throws {
        let agent = try fakeAgent(turn: Self.endTurn, cases: #"""
            *'"method":"session/load"'*)
              say '{"jsonrpc":"2.0","id":'$id',"error":{"code":-32002,"message":"Unknown session"}}' ;;
        """#)
        let runner = runner(agent)
        let session = runner.newSession(in: folder.path, agentID: agent.id)
        runner.send("One", to: session)
        try await wait { session.state == .idle }
        runner.stopAll()
        try await Task.sleep(for: .milliseconds(100))

        runner.send("Two", to: session)
        try await wait { session.state == .idle && received("session/prompt").count == 2 }
        let load = try XCTUnwrap(index(of: "session/load"))
        XCTAssertEqual(received("session/new").count, 2)
        XCTAssertLessThan(load, try XCTUnwrap(received().lastIndex { $0.contains(#""method":"session/new""#) }))
        XCTAssertNil(session.failure)
        runner.stopAll()
    }

    func testModelAndModeChangesGoToTheRunningAgent() async throws {
        let agent = try fakeAgent(turn: Self.endTurn)
        let runner = runner(agent)
        defer { runner.stopAll() }
        let session = runner.newSession(in: folder.path, agentID: agent.id)
        runner.send("Hello", to: session)
        try await wait { session.state == .idle }

        runner.setMode("code", for: session)
        runner.setModel("m2", for: session)
        try await wait { session.currentMode == "code" && received("session/set_config_option").count == 1 }
        XCTAssertTrue(received("session/set_mode").first?.contains(#""modeId":"code""#) == true)
        let model = try XCTUnwrap(received("session/set_config_option").first)
        XCTAssertTrue(model.contains(#""configId":"model""#) && model.contains(#""value":"m2""#), model)
        XCTAssertEqual(received("initialize").count, 1)
    }

    func testOlderModelListChangesThroughSetModel() async throws {
        let agent = try fakeAgent(turn: Self.endTurn, newSession: #"{"sessionId":"acp-1","models":{"currentModelId":"a","availableModels":[{"modelId":"a"},{"modelId":"b"}]}}"#)
        let runner = runner(agent)
        defer { runner.stopAll() }
        let session = runner.newSession(in: folder.path, agentID: agent.id)
        runner.send("Hello", to: session)
        try await wait { session.state == .idle }

        runner.setModel("b", for: session)
        try await wait { received("session/set_model").count == 1 }
        XCTAssertTrue(received("session/set_model")[0].contains(#""modelId":"b""#))
        XCTAssertTrue(received("session/set_config_option").isEmpty)
    }

    func testRejectedModeGoesBackToTheModeOfTheAgent() async throws {
        let agent = try fakeAgent(turn: Self.endTurn, cases: #"""
            *'"method":"session/set_mode"'*)
              say '{"jsonrpc":"2.0","id":'$id',"error":{"code":-32603,"message":"No such mode"}}' ;;
        """#)
        var errors: [String] = []
        let runner = SessionRunner(database: nil) { errors.append($0.localizedDescription) }
        runner.agents = [agent]
        runner.usesLoginShell = false
        defer { runner.stopAll() }
        let session = runner.newSession(in: folder.path, agentID: agent.id)
        runner.send("Hello", to: session)
        try await wait { session.state == .idle }

        runner.setMode("code", for: session)
        XCTAssertEqual(session.mode, "code")
        try await wait { session.mode == nil }
        XCTAssertEqual(session.currentMode, "ask")
        XCTAssertEqual(errors, ["The agent did not change the mode: No such mode"])
    }

    func testMarginSessionAllowsReadsAndRejectsEdits() async throws {
        let agent = try fakeAgent(turn: permission(kind: "read", id: 100) + "\n" + permission(kind: "edit", id: 101),
                                  reply: #"case "$line" in *'"id":101'*) "# + Self.endTurn + ";; esac")
        let runner = runner(agent)
        defer { runner.stopAll() }
        let session = runner.newSession(in: folder.path, agentID: agent.id, purpose: .margin)
        runner.send("Explain", to: session)
        try await wait { session.state == .idle }
        XCTAssertTrue(received().contains { $0.contains(#""id":100"#) && $0.contains(#""optionId":"yes""#) })
        XCTAssertTrue(received().contains { $0.contains(#""id":101"#) && $0.contains(#""optionId":"no""#) })
        XCTAssertFalse(session.blocks.contains { if case .permission = $0 { return true } else { return false } })
        XCTAssertTrue(runner.sessions(in: folder.path).isEmpty)
    }

    func testMarginSessionChangesToAReadOnlyModeBeforeThePrompt() async throws {
        let agent = try fakeAgent(turn: Self.endTurn, newSession: #"{"sessionId":"acp-1","modes":{"currentModeId":"code","availableModes":[{"id":"code","name":"Code"},{"id":"plan","name":"Plan"}]}}"#)
        let runner = runner(agent)
        defer { runner.stopAll() }
        let session = runner.newSession(in: folder.path, agentID: agent.id, purpose: .margin)
        runner.setMode("code", for: session)
        runner.send("Explain", to: session)
        try await wait { session.state == .idle }
        let setMode = try XCTUnwrap(index(of: "session/set_mode"))
        XCTAssertTrue(received()[setMode].contains(#""modeId":"plan""#))
        XCTAssertEqual(received("session/set_mode").count, 1)
        XCTAssertLessThan(setMode, try XCTUnwrap(index(of: "session/prompt")))
        XCTAssertEqual(session.currentMode, "plan")
        XCTAssertTrue(runner.agentsWithoutReadOnlyMode.isEmpty)
    }

    func testMarginSessionFailsOnAnAgentWithoutAReadOnlyMode() async throws {
        let agent = try fakeAgent(turn: Self.endTurn, newSession: #"{"sessionId":"acp-1","modes":{"currentModeId":"code","availableModes":[{"id":"code","name":"Code"}]}}"#)
        let runner = runner(agent)
        defer { runner.stopAll() }
        let session = runner.newSession(in: folder.path, agentID: agent.id, purpose: .margin)
        runner.send("Explain", to: session)
        try await wait { session.state == .failed }
        XCTAssertEqual(session.failure, StdioAgentConnection.noReadOnlyMode("Fake"))
        XCTAssertNil(index(of: "session/prompt"))
        XCTAssertEqual(runner.agentsWithoutReadOnlyMode, [agent.id])
    }

    func testPermissionRequestWithoutAToolCallGetsAnError() async throws {
        let agent = try fakeAgent(turn: #"say '{"jsonrpc":"2.0","id":100,"method":"session/request_permission","params":{"sessionId":"acp-1","toolCall":{"title":"Edit"},"options":[]}}'"#,
                                  cases: #"""
            *'"code":-32602'*)
              say '{"jsonrpc":"2.0","id":'$pid',"result":{"stopReason":"end_turn"}}' ;;
        """#)
        let runner = runner(agent)
        defer { runner.stopAll() }
        let session = runner.newSession(in: folder.path, agentID: agent.id)
        runner.send("Edit it", to: session)
        try await wait { session.state == .idle }
        XCTAssertTrue(received().contains { $0.contains(#""code":-32602"#) && $0.contains(#""id":100"#) })
        XCTAssertNil(session.pendingRequest)
    }

    func testPermissionRequestCarriesTheDiffsOfTheCall() async throws {
        let agent = try fakeAgent(turn: #"say '{"jsonrpc":"2.0","id":100,"method":"session/request_permission","params":{"sessionId":"acp-1","toolCall":{"toolCallId":"t1","title":"Edit a.md","kind":"edit","content":[{"type":"diff","path":"/w/a.md","oldText":"x","newText":"y"}]},"options":[{"optionId":"yes","name":"Allow","kind":"allow_once"}]}}'"#)
        let runner = runner(agent)
        defer { runner.stopAll() }
        let session = runner.newSession(in: folder.path, agentID: agent.id)
        runner.send("Edit it", to: session)
        try await wait { session.state == .needsYou }
        XCTAssertEqual(session.pendingRequest?.diffs, [ACP.Diff(path: "/w/a.md", oldText: "x", newText: "y")])
    }

    func testUnknownAgentFailsTheTurn() {
        let runner = SessionRunner(database: nil)
        let session = runner.newSession(in: folder.path, agentID: "removed")
        runner.send("Hello", to: session)
        XCTAssertEqual(session.state, .failed)
        XCTAssertTrue(session.failure?.contains("Settings > AI") == true)
    }
}

final class AgentProbeTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("agent-probe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try FileManager.default.removeItem(at: folder) }

    private func script(_ body: String) throws -> URL {
        let url = folder.appendingPathComponent("tool-\(UUID().uuidString)")
        try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func testClaudeCodeReportsTheVersionAndTheSignIn() async throws {
        let signedIn = try script("""
        case "$1" in
          --version) echo "2.1.300 (Claude Code)" ;;
          auth) echo '{"loggedIn":true,"authMethod":"claude.ai"}' ;;
        esac
        """)
        let status = await AgentProbe.claudeCode(executable: signedIn, usesLoginShell: false)
        XCTAssertEqual(status, AgentStatus(health: .ready, headline: "Signed in · claude.ai", version: "2.1.300"))

        let signedOut = try script("""
        case "$1" in
          --version) echo "2.1.300 (Claude Code)" ;;
          auth) echo '{"loggedIn":false}' ;;
        esac
        """)
        let out = await AgentProbe.claudeCode(executable: signedOut, usesLoginShell: false)
        XCTAssertEqual(out.health, .warning)
        let missing = await AgentProbe.claudeCode(executable: nil)
        XCTAssertEqual(missing.health, .error)
    }

    func testACPAgentAnswersInitialize() async throws {
        let agent = try script("""
        read -r line
        echo '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentInfo":{"name":"OpenCode","version":"1.2.27"},"authMethods":[{"id":"login","name":"Login","description":"Run opencode auth login"}]}}'
        sleep 30
        """)
        let status = await AgentProbe.acp(AgentDefinition(name: "OpenCode", command: agent.path), usesLoginShell: false)
        XCTAssertEqual(status, AgentStatus(health: .ready, headline: "ACP · OpenCode · Run opencode auth login", version: "1.2.27"))

        let spaced = try script("""
        read -r line
        echo '{"jsonrpc": "2.0", "method": "log", "params": {"id": 1}}'
        echo '{"jsonrpc": "2.0", "id": 1, "result": {"agentInfo": {"name": "Spaced", "version": "2.0"}}}'
        sleep 30
        """)
        let spacedStatus = await AgentProbe.acp(AgentDefinition(name: "Spaced", command: spaced.path), usesLoginShell: false)
        XCTAssertEqual(spacedStatus, AgentStatus(health: .ready, headline: "ACP · Spaced", version: "2.0"))

        let silent = try script("echo 'not acp' >&2; exit 1")
        let failed = await AgentProbe.acp(AgentDefinition(name: "Broken", command: silent.path), usesLoginShell: false)
        XCTAssertEqual(failed.health, .error)
        XCTAssertEqual(failed.headline, "not acp")
    }

    func testInitializeAnswerNeedsACompleteLineWithIDOne() {
        XCTAssertTrue(AgentProbe.answersInitialize(#"{"jsonrpc": "2.0", "id": 1, "result": {}}"# + "\n"))
        XCTAssertTrue(AgentProbe.answersInitialize(#"{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"No"}}"# + "\n"))
        XCTAssertFalse(AgentProbe.answersInitialize(#"{"jsonrpc":"2.0","id":1,"result":{}"#))
        XCTAssertFalse(AgentProbe.answersInitialize(#"{"jsonrpc":"2.0","id":11,"result":{}}"# + "\n"))
        XCTAssertFalse(AgentProbe.answersInitialize(#"{"jsonrpc":"2.0","method":"log","params":{"id":1}}"# + "\n"))
    }
}
