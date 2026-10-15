import Foundation

/// One tool call of a session, with its result when it arrives.
public struct ToolCall: Codable, Equatable, Sendable, Identifiable {

    /// The text that an Edit call replaces.
    public struct Diff: Codable, Equatable, Sendable {
        public let old: String
        public let new: String

        public init(old: String, new: String) {
            self.old = old
            self.new = new
        }
    }

    /// The `tool_use` id.
    public let id: String
    public var name: String
    /// One line from the input, for example the path or the command.
    public var detail: String
    /// The file that the call writes. The runner keeps only a path inside the
    /// folder, relative to it.
    public var path: String?
    public var diff: Diff?
    /// What the call does. Nil in a session that an older Piper stored.
    public var kind: ACP.ToolKind?
    public var isFinished = false
    public var isError = false
    /// The start of the tool result.
    public var resultPreview: String?

    /// The tool name and the detail, as one line.
    public var line: String { detail.isEmpty ? name : name + " " + detail }

    /// The kind of the call. A call from an older Piper takes the kind of its Claude Code tool.
    public var toolKind: ACP.ToolKind { kind ?? ClaudeCodeConnection.kind(of: name) }

    public init(id: String, name: String, detail: String, path: String? = nil, diff: Diff? = nil,
                kind: ACP.ToolKind? = nil) {
        self.id = id
        self.name = name
        self.detail = detail
        self.path = path
        self.diff = diff
        self.kind = kind
    }
}

/// A tool call that waits for the reader: a permission card or a question card.
public struct PermissionRequest: Codable, Equatable, Sendable {

    /// One question of an `AskUserQuestion` call.
    public struct Question: Codable, Equatable, Sendable {
        public struct Option: Codable, Equatable, Sendable {
            public let label: String
            public let description: String
        }

        public let question: String
        public let header: String
        public let options: [Option]
        public let multiSelect: Bool
    }

    public let requestID: String
    /// The tool name, or the title of the call when the agent gives no name.
    public let toolName: String
    public let input: JSONValue
    /// The short text that the agent gives, for example the file name.
    public let description: String?
    public let toolUseID: String?
    /// What the call does. Nil in a session that an older Piper stored.
    public var kind: ACP.ToolKind?
    /// The choices of the agent, in its order. Nil in a session that an older Piper stored.
    public var options: [ACP.PermissionOption]?
    /// The edits of the call, when the agent gives them. Nil for Claude Code,
    /// whose edits are in the input.
    public var diffs: [ACP.Diff]?

    /// The line that the card shows under the tool name.
    public var detail: String { SessionEvent.detail(of: input) }

    /// True when the call asks the reader questions instead of asking for permission.
    public var isQuestion: Bool { toolName == "AskUserQuestion" }

    /// The questions of an `AskUserQuestion` call.
    public var questions: [Question] {
        input["questions"]?.array.compactMap { value -> Question? in
            guard let question = value["question"]?.string else { return nil }
            let options = value["options"]?.array.compactMap { option -> Question.Option? in
                guard let label = option["label"]?.string else { return nil }
                return Question.Option(label: label, description: option["description"]?.string ?? "")
            } ?? []
            let multiSelect: Bool
            if case .bool(let value)? = value["multiSelect"] { multiSelect = value } else { multiSelect = false }
            return Question(question: question, header: value["header"]?.string ?? "",
                            options: options, multiSelect: multiSelect)
        } ?? []
    }

    public init(requestID: String, toolName: String, input: JSONValue, description: String? = nil, toolUseID: String? = nil,
                kind: ACP.ToolKind? = nil, options: [ACP.PermissionOption]? = nil, diffs: [ACP.Diff]? = nil) {
        self.requestID = requestID
        self.toolName = toolName
        self.input = input
        self.description = description
        self.toolUseID = toolUseID
        self.kind = kind
        self.options = options
        self.diffs = diffs
    }
}

/// What the reader chose on a permission card.
public enum PermissionDecision: String, Codable, Sendable {
    case pending
    case allowed
    /// Allowed, and Piper wrote an allow rule for the folder.
    case allowedAlways
    case denied
}

/// The end of one turn.
public struct TurnResult: Codable, Equatable, Sendable {
    /// The last message of the turn.
    public let text: String
    public let durationMs: Int
    public let costUSD: Double
    /// Why the turn failed. Nil for a turn that succeeded.
    public var failure: String?

    public var isError: Bool { failure != nil }

    public init(text: String = "", durationMs: Int = 0, costUSD: Double = 0, failure: String? = nil) {
        self.text = text
        self.durationMs = durationMs
        self.costUSD = costUSD
        self.failure = failure
    }
}

/// One item of a session transcript, oldest first.
public enum TranscriptBlock: Codable, Equatable, Sendable, Identifiable {
    /// A message from the reader, with the files attached as context.
    case user(id: String, text: String, context: [String])
    case assistant(id: String, text: String)
    case toolCall(ToolCall)
    case permission(PermissionRequest, decision: PermissionDecision)
    /// An `AskUserQuestion` call. The answers are nil until the reader answers.
    case question(PermissionRequest, answers: [String: String]?)
    case result(id: String, TurnResult)

    public var id: String {
        switch self {
        case .user(let id, _, _), .assistant(let id, _), .result(let id, _): return id
        case .toolCall(let call): return call.id
        case .permission(let request, _), .question(let request, _): return "request-" + request.requestID
        }
    }
}

extension ToolCall {

    /// The calls counted by kind, for example "3 reads, 2 edits, 1 command".
    public static func summary(of calls: [ToolCall]) -> String {
        let counts = Dictionary(grouping: calls, by: \.toolKind).mapValues(\.count)
        let order: [ACP.ToolKind] = [.execute, .edit, .delete, .move, .read, .search, .fetch, .think, .other, .switchMode]
        return order.compactMap { kind in counts[kind].map { phrase(kind, count: $0) } }.joined(separator: ", ")
    }

    private static func phrase(_ kind: ACP.ToolKind, count: Int) -> String {
        let (one, many): (String, String) = switch kind {
        case .read: ("read", "reads")
        case .edit: ("edit", "edits")
        case .delete: ("deletion", "deletions")
        case .move: ("move", "moves")
        case .search: ("search", "searches")
        case .execute: ("command", "commands")
        case .think: ("step", "steps")
        case .fetch: ("web page", "web pages")
        case .switchMode: ("mode change", "mode changes")
        case .other: ("tool call", "tool calls")
        }
        return "\(count) " + (count == 1 ? one : many)
    }
}
