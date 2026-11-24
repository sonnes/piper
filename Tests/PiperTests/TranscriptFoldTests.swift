import Agents
import XCTest
@testable import Piper

final class TranscriptFoldTests: XCTestCase {

    private func call(_ id: String, _ name: String, _ kind: ACP.ToolKind) -> TranscriptBlock {
        .toolCall(ToolCall(id: id, name: name, detail: "", kind: kind))
    }

    func testFinishedTurnFoldsItsCallsWhereTheFirstCallWas() {
        let blocks: [TranscriptBlock] = [
            .user(id: "u1", text: "Fix it", context: []),
            .assistant(id: "a1", text: "Looking."),
            call("t1", "Read", .read),
            call("t2", "Read", .read),
            .permission(PermissionRequest(requestID: "r1", toolName: "Edit", input: .null), decision: .allowed),
            call("t3", "Edit", .edit),
            .assistant(id: "a2", text: "Fixed."),
            .result(id: "res1", TurnResult(durationMs: 72_000)),
            .user(id: "u2", text: "And again", context: []),
            call("t4", "Bash", .execute)
        ]
        let rows = TranscriptRow.rows(of: blocks)
        XCTAssertEqual(rows.map(\.id), ["u1", "a1", "fold-t1", "a2", "res1", "u2", "t4"])
        guard case .fold(_, let summary, let folded) = rows[2] else { return XCTFail("No fold") }
        XCTAssertEqual(folded.map(\.id), ["t1", "t2", "request-r1", "t3"])
        XCTAssertTrue(summary.hasPrefix("Worked for 1"), summary)
        XCTAssertTrue(summary.hasSuffix("1 edit, 2 reads"), summary)
    }

    func testTurnWithoutCallsDoesNotFold() {
        let blocks: [TranscriptBlock] = [
            .user(id: "u1", text: "Hi", context: []),
            .assistant(id: "a1", text: "Hello."),
            .result(id: "res1", TurnResult())
        ]
        XCTAssertEqual(TranscriptRow.rows(of: blocks).map(\.id), ["u1", "a1", "res1"])
    }
}
