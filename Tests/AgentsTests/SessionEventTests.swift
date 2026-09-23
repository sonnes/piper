import CapturesDatabase
import Foundation
import XCTest
@testable import Agents

final class SessionEventTests: XCTestCase {

    func testSessionCommandsAndCompaction() {
        let line = #"{"type":"system","subtype":"init","session_id":"s-1","slash_commands":["compact","clear","plugin:review","bad name"]}"#
        XCTAssertEqual(SessionEvent.parse(line), [.started(sessionID: "s-1"), .commands(["compact", "clear", "plugin:review"])])
        XCTAssertEqual(SessionEvent.parse(#"{"type":"system","subtype":"compact_boundary","compact_metadata":{"trigger":"manual","pre_tokens":1842}}"#),
                       [.text("Conversation compacted.")])
    }

    func testInitTextAndToolCalls() {
        XCTAssertEqual(SessionEvent.parse(#"{"type":"system","subtype":"init","session_id":"s-1"}"#),
                       [.started(sessionID: "s-1")])
        let line = #"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"Filing it."},{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"/w/a.md","old_string":"a","new_string":"b"}},{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"python3 x.py\nmore"}}]},"parent_tool_use_id":null}"#
        XCTAssertEqual(SessionEvent.parse(line), [
            .text("Filing it."),
            .toolCall(ToolCall(id: "t1", name: "Edit", detail: "/w/a.md", path: "/w/a.md", diff: ToolCall.Diff(old: "a", new: "b"))),
            .toolCall(ToolCall(id: "t2", name: "Bash", detail: "python3 x.py more"))
        ])
    }

    func testToolResultsTakeStringOrBlocks() {
        let string = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok","is_error":false}]}}"#
        XCTAssertEqual(SessionEvent.parse(string), [.toolResult(toolUseID: "t1", isError: false, preview: "ok")])
        let blocks = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t2","content":[{"type":"text","text":"a"},{"type":"text","text":"b"}],"is_error":true}]}}"#
        XCTAssertEqual(SessionEvent.parse(blocks), [.toolResult(toolUseID: "t2", isError: true, preview: "a\nb")])
    }

    func testSubagentMessagesAreSkipped() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"inner"}]},"parent_tool_use_id":"t9"}"#
        XCTAssertEqual(SessionEvent.parse(line), [])
    }

    func testPermissionRequest() {
        let line = #"{"type":"control_request","request_id":"r1","request":{"subtype":"can_use_tool","tool_name":"Write","input":{"file_path":"/w/hello.txt","content":"hi"},"description":"hello.txt","tool_use_id":"t1"}}"#
        guard case .permission(let request)? = SessionEvent.parse(line).first else { return XCTFail("No request") }
        XCTAssertEqual(request.requestID, "r1")
        XCTAssertEqual(request.toolName, "Write")
        XCTAssertEqual(request.toolUseID, "t1")
        XCTAssertEqual(request.detail, "/w/hello.txt")
        XCTAssertEqual(request.input["content"], .string("hi"))
        XCTAssertFalse(request.isQuestion)
    }

    func testQuestionsComeFromTheInput() {
        let line = #"{"type":"control_request","request_id":"r2","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","input":{"questions":[{"question":"Which color?","header":"Color","options":[{"label":"Red","description":"The color red"},{"label":"Blue","description":""}],"multiSelect":false}]},"tool_use_id":"t2"}}"#
        guard case .permission(let request)? = SessionEvent.parse(line).first else { return XCTFail("No request") }
        XCTAssertTrue(request.isQuestion)
        XCTAssertEqual(request.questions.first?.question, "Which color?")
        XCTAssertEqual(request.questions.first?.options.map(\.label), ["Red", "Blue"])
        XCTAssertEqual(request.questions.first?.multiSelect, false)
    }

    func testResultsAndDenials() {
        let success = #"{"type":"result","subtype":"success","is_error":false,"result":"Done.","duration_ms":5291,"total_cost_usd":0.029,"permission_denials":[]}"#
        XCTAssertEqual(SessionEvent.parse(success), [.turnEnded(TurnResult(text: "Done.", durationMs: 5291, costUSD: 0.029), denials: [])])

        let error = #"{"type":"result","subtype":"error_max_turns","is_error":false}"#
        guard case .turnEnded(let failed, _)? = SessionEvent.parse(error).first else { return XCTFail("No result") }
        XCTAssertEqual(failed.failure, "error_max_turns")

        let denied = #"{"type":"result","subtype":"success","result":"","permission_denials":[{"tool_name":"WebFetch","tool_use_id":"t1","tool_input":{"url":"https://a.io/"}},{"tool_name":"WebFetch","tool_use_id":"t2","tool_input":{"url":"https://a.io/"}},{"tool_name":"Bash","tool_input":{"command":"curl x"}}]}"#
        guard case .turnEnded(_, let denials)? = SessionEvent.parse(denied).first else { return XCTFail("No result") }
        XCTAssertEqual(denials.map(\.toolUseID), ["t1", "t2", nil])
        let lines = SessionEvent.failure(for: denials)?.components(separatedBy: "\n") ?? []
        XCTAssertEqual(lines.first, "Needs permission for WebFetch, Bash.")
        XCTAssertEqual(lines.filter { $0 == "• WebFetch: https://a.io/" }.count, 1)
        XCTAssertNil(SessionEvent.failure(for: []))
    }

    func testIgnoresOtherLines() {
        XCTAssertEqual(SessionEvent.parse("not json"), [])
        XCTAssertEqual(SessionEvent.parse(#"{"type":"system","subtype":"session_state_changed","state":"idle"}"#), [])
        XCTAssertEqual(SessionEvent.parse(#"{"type":"rate_limit_event"}"#), [])
    }

    func testRelativePathStaysInsideTheFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agents-paths-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sources"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("sources/a.md")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(SessionEvent.relativePath(file.path, in: folder), "sources/a.md")
        XCTAssertEqual(SessionEvent.relativePath(file.resolvingSymlinksInPath().path, in: folder), "sources/a.md")
        XCTAssertEqual(SessionEvent.relativePath("sources/a.md", in: folder), "sources/a.md")
        XCTAssertNil(SessionEvent.relativePath("/etc/hosts", in: folder))
        XCTAssertNil(SessionEvent.relativePath(folder.path + "/../x.md", in: folder))
    }
}

final class SessionHelperTests: XCTestCase {

    func testJSONValueKeepsItsShape() throws {
        let object = try JSONSerialization.jsonObject(with: Data(#"{"a":1,"b":true,"c":[null,"x",2.5],"d":{"e":"f"}}"#.utf8))
        let value = JSONValue(object)
        XCTAssertEqual(value["a"], .number(1))
        XCTAssertEqual(value["b"], .bool(true))
        XCTAssertEqual(value["c"], .array([.null, .string("x"), .number(2.5)]))
        let data = try JSONSerialization.data(withJSONObject: value.any, options: [.sortedKeys])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"a":1,"b":true,"c":[null,"x",2.5],"d":{"e":"f"}}"#)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)), value)
        XCTAssertEqual(value.setting("z", to: .string("y"))["z"], .string("y"))
    }

    func testPermissionRules() {
        XCTAssertEqual(PermissionRule.rule(toolName: "Edit", input: .object([:])), "Edit")
        XCTAssertEqual(PermissionRule.rule(toolName: "Bash", input: .object(["command": .string("python3 tools/x.py --all")])), "Bash(python3:*)")
        XCTAssertEqual(PermissionRule.rule(toolName: "Bash", input: .object([:])), "Bash")
        XCTAssertEqual(PermissionRule.rule(toolName: "WebFetch", input: .object(["url": .string("https://example.com/a")])), "WebFetch(domain:example.com)")
        XCTAssertNil(PermissionRule.rule(toolName: "AskUserQuestion", input: .object([:])))
    }

    func testAppendingARuleKeepsTheOtherSettings() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agents-rules-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try PermissionRule.append("Edit", to: folder)
        let url = folder.appendingPathComponent(".claude/settings.local.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual((object["permissions"] as? [String: Any])?["allow"] as? [String], ["Edit"])

        try Data(#"{"model":"opus","permissions":{"allow":["Edit"],"deny":["Bash(rm:*)"]}}"#.utf8).write(to: url)
        try PermissionRule.append("Bash(python3:*)", to: folder)
        try PermissionRule.append("Edit", to: folder)
        object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let permissions = try XCTUnwrap(object["permissions"] as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "opus")
        XCTAssertEqual(permissions["allow"] as? [String], ["Edit", "Bash(python3:*)"])
        XCTAssertEqual(permissions["deny"] as? [String], ["Bash(rm:*)"])
    }

    func testDiffKeepsTheSharedLines() {
        XCTAssertEqual(DiffText.lines(old: "a\nb\nc", new: "a\nB\nc"), [.context("a"), .removed("b"), .added("B"), .context("c")])
        XCTAssertEqual(DiffText.lines(old: "a", new: "a\nb"), [.context("a"), .added("b")])
        XCTAssertEqual(DiffText.lines(old: "x", new: ""), [.removed("x"), .added("")])
    }

    func testMentions() {
        XCTAssertEqual(SessionComposerText.partialMention("see @"), "")
        XCTAssertEqual(SessionComposerText.partialMention("@sou"), "sou")
        XCTAssertNil(SessionComposerText.partialMention("me@example"))
        XCTAssertNil(SessionComposerText.partialMention("@a.md and more"))
        XCTAssertNil(SessionComposerText.partialMention("no mention"))
        XCTAssertEqual(SessionComposerText.replacingMention(in: "read @sou", with: "sources/a.md"), "read @sources/a.md ")
        XCTAssertEqual(SessionComposerText.replacingMention(in: "plain", with: "a.md"), "plain")
    }

    func testUserLineAddsTheContext() throws {
        func text(_ line: String) throws -> String? {
            let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            let content = (object?["message"] as? [String: Any])?["content"] as? [[String: Any]]
            return content?.first?["text"] as? String
        }
        XCTAssertEqual(try text(SessionRunner.userLine("Why?", context: [])), "Why?")
        XCTAssertEqual(try text(SessionRunner.userLine("Why?", context: ["/w/a.md"])), "Why?\n\nContext file: /w/a.md")
        XCTAssertEqual(try text(SessionRunner.userLine("/verify", context: ["/w/a.md"])), "/verify /w/a.md")
    }
}

final class SessionsTableTests: XCTestCase {

    func testSavesLoadsDeletesAndTrims() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sessions-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try Database(url: url)
        let ids = (0..<3).map { _ in UUID() }
        for (index, id) in ids.enumerated() {
            try database.saveSession(id: id, folder: "/w", updatedAt: Date(timeIntervalSince1970: Double(index)), data: Data([UInt8(index)]))
        }
        try database.saveSession(id: ids[0], folder: "/w", updatedAt: Date(timeIntervalSince1970: 10), data: Data([9]))
        XCTAssertEqual(try database.loadSessions(), [Data([9]), Data([2]), Data([1])])

        try database.deleteSession(id: ids[2])
        XCTAssertEqual(try database.loadSessions(), [Data([9]), Data([1])])

        try database.keepNewestSessions(1)
        XCTAssertEqual(try Database(url: url).loadSessions(), [Data([9])])
    }
}

@MainActor
final class AgentSessionTests: XCTestCase {

    func testDerivedValues() {
        let session = AgentSession(folder: "/w/wiki", command: SlashCommand(name: "capture", arguments: "https://a.io"))
        XCTAssertEqual(session.title, "/capture https://a.io")
        session.append(.user(id: "u1", text: "/capture https://a.io\nsecond line", context: []))
        session.append(.toolCall(ToolCall(id: "t1", name: "Write", detail: "/w/wiki/index.md", path: "index.md")))
        var failed = ToolCall(id: "t2", name: "Write", detail: "x", path: "bad.md")
        failed.isError = true
        session.append(.toolCall(failed))
        session.append(.toolCall(ToolCall(id: "t3", name: "Edit", detail: "/w/wiki/sources/a.md", path: "sources/a.md")))
        session.append(.assistant(id: "a1", text: "Filed it."))
        session.append(.result(id: "r1", TurnResult(text: "Filed it.", durationMs: 1500, costUSD: 0.02)))
        session.append(.user(id: "u2", text: "Thanks", context: []))
        session.append(.result(id: "r2", TurnResult(durationMs: 500, costUSD: 0.01, failure: "boom")))

        XCTAssertEqual(session.title, "/capture https://a.io")
        XCTAssertEqual(session.folderName, "wiki")
        XCTAssertEqual(session.files, ["index.md", "sources/a.md"])
        XCTAssertEqual(session.primaryFile, "sources/a.md")
        XCTAssertEqual(session.totalCost, 0.03, accuracy: 0.0001)
        XCTAssertEqual(session.totalDuration, 2)
        XCTAssertEqual(session.lastStep, "Edit /w/wiki/sources/a.md")
        XCTAssertEqual(session.lastPrompt, "Thanks")
        XCTAssertEqual(session.snippet, "boom")
        XCTAssertNil(session.failure)
        session.state = .failed
        XCTAssertEqual(session.failure, "boom")
    }

    func testPendingRequestAndSnapshot() throws {
        let session = AgentSession(folder: "/w")
        let request = PermissionRequest(requestID: "r1", toolName: "Write", input: .object(["file_path": .string("/w/a")]))
        session.append(.permission(request, decision: .pending))
        XCTAssertEqual(session.pendingRequest, request)
        session.update(TranscriptBlock.permission(request, decision: .pending).id) { $0 = .permission(request, decision: .allowed) }
        XCTAssertNil(session.pendingRequest)

        session.slashCommands = ["compact", "context"]
        let data = try JSONEncoder().encode(session.snapshot)
        let copy = AgentSession(try JSONDecoder().decode(AgentSession.Snapshot.self, from: data))
        XCTAssertEqual(copy.snapshot, session.snapshot)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "slashCommands")
        let oldData = try JSONSerialization.data(withJSONObject: old)
        let restored = AgentSession(try JSONDecoder().decode(AgentSession.Snapshot.self, from: oldData))
        XCTAssertNil(restored.slashCommands)
    }
}
