import Foundation

/// One fact from a line of `claude -p --output-format stream-json`.
public enum SessionEvent: Equatable, Sendable {

    /// A tool call that Claude Code refused without a card, from the
    /// `permission_denials` of a result.
    public struct Denial: Equatable, Sendable {
        public let toolName: String
        public let toolUseID: String?
        public let detail: String?
    }

    /// Claude Code started and names its session.
    case started(sessionID: String)
    case commands([String])
    case text(String)
    case toolCall(ToolCall)
    case toolResult(toolUseID: String, isError: Bool, preview: String)
    /// A tool call waits for an answer on standard input.
    case permission(PermissionRequest)
    case turnEnded(TurnResult, denials: [Denial])

    // MARK: - Parsing

    /// The tools whose input names a file that they write.
    private static let writers: [String: String] = [
        "Write": "file_path", "Edit": "file_path", "MultiEdit": "file_path", "NotebookEdit": "notebook_path"
    ]
    private static let detailKeys = ["file_path", "notebook_path", "command", "url", "pattern", "skill", "description"]
    static let lineLimit = 160
    private static let previewLimit = 400

    /// Reads one line. A line that is not JSON, or that holds nothing Piper
    /// shows, returns no events. A message from a subagent is skipped, because
    /// its parent tool call already shows.
    public static func parse(_ line: String) -> [SessionEvent] {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let isSubagent = object["parent_tool_use_id"].map { !($0 is NSNull) } ?? false
        switch object["type"] as? String {
        case "system":
            if object["subtype"] as? String == "compact_boundary" {
                return [.text("Conversation compacted.")]
            }
            guard object["subtype"] as? String == "init", let id = object["session_id"] as? String else { return [] }
            var events: [SessionEvent] = [.started(sessionID: id)]
            if let names = object["slash_commands"] as? [String] {
                events.append(.commands(names.filter { SlashCommand.isName($0) }))
            }
            return events
        case "assistant":
            guard !isSubagent else { return [] }
            let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return content.compactMap(assistantEvent)
        case "user":
            guard !isSubagent else { return [] }
            let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return content.compactMap(resultEvent)
        case "control_request":
            guard let id = object["request_id"] as? String,
                  let request = object["request"] as? [String: Any],
                  request["subtype"] as? String == "can_use_tool",
                  let tool = request["tool_name"] as? String else { return [] }
            return [.permission(PermissionRequest(requestID: id, toolName: tool, input: JSONValue(request["input"]),
                                                  description: request["description"] as? String,
                                                  toolUseID: request["tool_use_id"] as? String))]
        case "result":
            return [turnEnded(object)]
        default:
            return []
        }
    }

    /// One line from a tool input: the first of the path, the command, the
    /// URL, and the other keys that name what the call acts on.
    public static func detail(of input: JSONValue) -> String {
        let text = detailKeys.lazy.compactMap { input[$0]?.string }.first ?? ""
        return String(text.replacingOccurrences(of: "\n", with: " ").prefix(lineLimit))
    }

    private static func assistantEvent(_ block: [String: Any]) -> SessionEvent? {
        switch block["type"] as? String {
        case "text":
            guard let text = block["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return .text(text)
        case "tool_use":
            guard let id = block["id"] as? String, let name = block["name"] as? String else { return nil }
            let input = JSONValue(block["input"])
            let path = writers[name].flatMap { input[$0]?.string }
            var diff: ToolCall.Diff?
            if name == "Edit", let old = input["old_string"]?.string, let new = input["new_string"]?.string {
                diff = ToolCall.Diff(old: old, new: new)
            }
            return .toolCall(ToolCall(id: id, name: name, detail: detail(of: input), path: path, diff: diff))
        default:
            return nil
        }
    }

    private static func resultEvent(_ block: [String: Any]) -> SessionEvent? {
        guard block["type"] as? String == "tool_result", let id = block["tool_use_id"] as? String else { return nil }
        let text: String
        if let string = block["content"] as? String {
            text = string
        } else {
            let parts = block["content"] as? [[String: Any]] ?? []
            text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return .toolResult(toolUseID: id, isError: block["is_error"] as? Bool ?? false,
                           preview: String(text.prefix(previewLimit)))
    }

    private static func turnEnded(_ object: [String: Any]) -> SessionEvent {
        let text = object["result"] as? String ?? ""
        var failure: String?
        if object["is_error"] as? Bool == true || object["subtype"] as? String != "success" {
            failure = text.isEmpty ? (object["subtype"] as? String ?? "The turn failed.") : text
        }
        let result = TurnResult(text: text,
                                durationMs: object["duration_ms"] as? Int ?? 0,
                                costUSD: object["total_cost_usd"] as? Double ?? 0,
                                failure: failure)
        let denials = (object["permission_denials"] as? [[String: Any]] ?? []).map { denial in
            let input = denial["tool_input"] as? [String: Any] ?? [:]
            return Denial(toolName: denial["tool_name"] as? String ?? "A tool",
                          toolUseID: denial["tool_use_id"] as? String,
                          detail: (input["command"] ?? input["file_path"] ?? input["url"]) as? String)
        }
        return .turnEnded(result, denials: denials)
    }

    // MARK: - Denials

    /// The failure text for tool calls that Claude Code refused without a card.
    /// The first line is the summary that a note row shows.
    public static func failure(for denials: [Denial]) -> String? {
        guard !denials.isEmpty else { return nil }
        var tools: [String] = []
        var lines: [String] = []
        for denial in denials {
            let line = "• " + String((denial.detail.map { "\(denial.toolName): \($0)" } ?? denial.toolName).prefix(lineLimit))
            if !tools.contains(denial.toolName) { tools.append(denial.toolName) }
            if !lines.contains(line) { lines.append(line) }
        }
        return "Needs permission for \(tools.joined(separator: ", ")).\n"
            + lines.joined(separator: "\n")
            + "\nAllow the tools in the folder's .claude/settings.json, or choose another permission mode in Settings > Claude."
    }

    // MARK: - Paths

    /// The path of `path` inside `folder`, or nil for a path outside it.
    public static func relativePath(_ path: String, in folder: URL) -> String? {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path
        let absolute = path.hasPrefix("/") ? URL(fileURLWithPath: path) : folder.appendingPathComponent(path)
        let file = absolute.resolvingSymlinksInPath().standardizedFileURL.path
        guard file.hasPrefix(root + "/") else { return nil }
        return String(file.dropFirst(root.count + 1))
    }
}
