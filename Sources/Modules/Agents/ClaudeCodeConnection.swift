import Foundation
import PiperCore

/// Runs `claude -p` with stream-json in both directions, and turns its stream
/// into ACP events. Claude Code needs no adapter and no Node this way.
///
/// One process serves many turns. A change of model or mode takes a new
/// process, which resumes the session with `--resume`.
@MainActor
public final class ClaudeCodeConnection: AgentConnection {

    /// How much Claude Code does without a card, in menu order. The raw value is
    /// the value of `--permission-mode`, and the id of the mode in the mode menu.
    public enum PermissionMode: String, CaseIterable, Sendable {
        /// Claude Code allows or asks for each tool call by its risk.
        case auto
        /// Edits files without a card. Other tools show a card.
        case acceptEdits
        /// Every tool call that the folder settings do not allow shows a card.
        case ask = "manual"
        /// Reads and plans, and edits nothing.
        case plan
        /// Runs every tool without a card.
        case bypassPermissions

        /// The name in the mode menu.
        public var name: String {
            switch self {
            case .auto: return "Auto"
            case .acceptEdits: return "Edit Files Only"
            case .ask: return "Ask Every Time"
            case .plan: return "Plan"
            case .bypassPermissions: return "Allow Every Tool"
            }
        }

        /// One line about the mode, for a tooltip.
        public var detail: String {
            switch self {
            case .auto: return "Claude Code allows safe tools and asks about risky ones."
            case .acceptEdits: return "File edits run with no card. Other tools ask."
            case .ask: return "Each tool that the folder settings do not allow asks."
            case .plan: return "Claude Code reads and plans, and edits nothing."
            case .bypassPermissions: return "Any tool runs with no card, including shell commands."
            }
        }
    }

    // MARK: - Properties

    /// The tools of a margin session: they read files and the web, and they change nothing.
    nonisolated static let marginTools = "Read,Grep,Glob,WebSearch,WebFetch"
    static let denyMessage = "The reader denied this tool call in Piper."

    /// The modes that `--permission-mode` takes, in menu order.
    public nonisolated static let modes = PermissionMode.allCases.map {
        ACP.Mode(id: $0.rawValue, name: $0.name, description: $0.detail)
    }

    /// The model of a session when the reader chose none.
    public nonisolated static let defaultModel = "sonnet"
    /// The model of a margin answer when the reader chose none. It is fast and costs little.
    public nonisolated static let defaultMarginModel = "haiku"

    /// The values that `--model` takes. An empty value leaves the choice to Claude Code.
    public nonisolated static let models = [
        ACP.ConfigOption.Value(id: defaultModel, name: "Sonnet"),
        ACP.ConfigOption.Value(id: "opus", name: "Opus"),
        ACP.ConfigOption.Value(id: defaultMarginModel, name: "Haiku"),
        ACP.ConfigOption.Value(id: "", name: "Claude Code Default")
    ]

    /// The commands that Claude Code runs itself, on the conversation and not on files.
    public nonisolated static let localCommands: Set<String> = ["compact", "clear", "context", "usage"]
    public nonisolated static let readsDenialMessage = true
    public nonisolated static let answersQuestions = true

    /// The tool that asks the reader questions.
    private nonisolated static let questionTool = "AskUserQuestion"
    /// The tools whose input names a file that they write, with the key of the path.
    private nonisolated static let writers: [String: String] = [
        "Write": "file_path", "Edit": "file_path", "MultiEdit": "file_path", "NotebookEdit": "notebook_path"
    ]

    /// The rules that Always added in this launch of Piper, by folder. A
    /// process reads the settings file only when it starts.
    private static var allowRules: [String: Set<String>] = [:]

    private let process: AgentProcess
    private let folder: URL
    private let config: SessionConfig
    private let report: (Error) -> Void
    private var event: (@MainActor (AgentEvent) -> Void)?
    /// The tool calls that the reader denied in the current turn.
    private var deniedCalls: Set<String> = []
    /// True after a message of the current turn, so the next message starts a new paragraph.
    private var hasText = false

    // MARK: - Initialization

    /// The Claude Code agent. A nil executable means that Piper did not find `claude`.
    public nonisolated static func agent(executable: URL?, model: String? = nil,
                                         mode: PermissionMode = .auto) -> AgentDefinition {
        AgentDefinition(id: AgentDefinition.claudeCodeID, kind: .claudeCode, name: "Claude Code",
                        command: executable?.path ?? "", model: model, mode: mode.rawValue)
    }

    public init(agent: AgentDefinition, config: SessionConfig, usesLoginShell: Bool,
                report: @escaping (Error) -> Void) throws {
        guard !agent.command.isEmpty else {
            throw PiperError("Piper cannot find the claude command. Choose it in Settings > AI.")
        }
        self.folder = config.folder
        self.config = config
        self.report = report
        process = AgentProcess(command: agent.command, arguments: Self.arguments(for: config),
                               folder: config.folder, usesLoginShell: usesLoginShell)
    }

    nonisolated static func arguments(for config: SessionConfig) -> [String] {
        var arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                         "--permission-prompt-tool", "stdio"]
        if let mode = config.mode { arguments += ["--permission-mode", mode] }
        if let model = config.model, !model.isEmpty { arguments += ["--model", model] }
        // `--tools` limits only the built-in tools. `--strict-mcp-config` with no
        // `--mcp-config` also removes every MCP server, so no tool can write.
        if config.purpose == .margin {
            arguments += ["--tools", marginTools, "--allowedTools", marginTools, "--strict-mcp-config"]
        }
        if let resume = config.resumeToken { arguments += ["--resume", resume] }
        return arguments
    }

    // MARK: - AgentConnection

    /// The tools of a margin session read and change nothing in any mode.
    public nonisolated static func hasReadOnlyMode(_ setup: ACP.SessionSetup) -> Bool { true }

    public func start(event: @escaping @MainActor (AgentEvent) -> Void,
                      exit: @escaping @MainActor (Int32, String) -> Void) throws {
        self.event = event
        try process.start(line: { [weak self] line in self?.receive(line) }, exit: exit)
    }

    public func prompt(_ text: String, context: [ContextItem]) {
        hasText = false
        write { try Self.userLine(text, context: context) }
    }

    public func respond(to request: PermissionRequest, with option: ACP.PermissionOption, message: String?) {
        if option.kind.allows {
            if option.kind == .allowAlways, let rule = PermissionRule.rule(for: request) {
                do {
                    try PermissionRule.append(rule, to: folder)
                    Self.allowRules[folder.path, default: []].insert(rule)
                } catch { report(error) }
            }
            reply(to: request, ["behavior": "allow", "updatedInput": request.input.any])
        } else {
            reply(to: request, ["behavior": "deny", "message": message ?? Self.denyMessage])
            if let id = request.toolUseID { deniedCalls.insert(id) }
        }
    }

    public func answer(_ request: PermissionRequest, answers: [String: String]) {
        let input = request.input.setting("answers", to: .object(answers.mapValues(JSONValue.string)))
        reply(to: request, ["behavior": "allow", "updatedInput": input.any])
    }

    /// Ends the process. The next message starts a new one with `--resume`.
    public func cancel() { process.terminate() }

    public func apply(model: String?, mode: String?) -> Bool { false }
    public func close() { process.closeInput() }
    public func terminate() { process.terminate() }

    // MARK: - Messages

    /// One user message of the stream-json input.
    nonisolated static func userLine(_ text: String, context: [ContextItem]) throws -> String {
        let body = SessionRunner.messageBody(text, context: context)
        return try line(["type": "user", "message": ["role": "user", "content": [["type": "text", "text": body]]]])
    }

    nonisolated static func line(_ object: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw PiperError("Piper cannot write the message for Claude Code.")
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    /// The default choices of a permission card of Claude Code.
    nonisolated static func options(in folder: URL) -> [ACP.PermissionOption] {
        [ACP.PermissionOption(id: "allow", name: "Allow Once", kind: .allowOnce),
         ACP.PermissionOption(id: "always", name: "Always in \(folder.lastPathComponent)", kind: .allowAlways),
         ACP.PermissionOption(id: "deny", name: "Deny", kind: .rejectOnce)]
    }

    nonisolated static func kind(of tool: String) -> ACP.ToolKind {
        switch tool {
        case "Read", "NotebookRead": return .read
        case "Glob", "Grep", "LS", "WebSearch", "ToolSearch": return .search
        case "Write", "Edit", "MultiEdit", "NotebookEdit": return .edit
        case "Bash", "BashOutput", "KillShell", "KillBash", "Monitor": return .execute
        case "WebFetch": return .fetch
        case "Task", "Agent", "TodoWrite": return .think
        case "ExitPlanMode", "EnterPlanMode": return .switchMode
        default: return .other
        }
    }

    /// The tool call of a `tool_use` block, in the fields that the runner reads.
    nonisolated static func update(id: String, name: String, input: JSONValue) -> ACP.ToolCallUpdate {
        ACP.ToolCallUpdate(id: id, name: name, title: SessionEvent.detail(of: input), kind: kind(of: name),
                           status: .pending, paths: path(of: name, input: input).map { [$0] },
                           diffs: edit(of: name, input: input).map { [$0] })
    }

    /// A request with the kind, the options, the question flag, and the edits
    /// that its tool name and its input give.
    nonisolated static func prepared(_ request: PermissionRequest, in folder: URL) -> PermissionRequest {
        var request = request
        if request.kind == .other { request.kind = kind(of: request.toolName) }
        if request.options.isEmpty { request.options = options(in: folder) }
        if request.toolName == questionTool { request.isQuestion = true }
        if request.diffs.isEmpty { request.diffs = edits(of: request.toolName, input: request.input) }
        return request
    }

    public nonisolated static func restored(_ blocks: [TranscriptBlock], in folder: URL) -> [TranscriptBlock] {
        blocks.map { block in
            switch block {
            case .toolCall(var call):
                if call.kind == .other { call.kind = kind(of: call.name) }
                return .toolCall(call)
            case .permission(let request, let decision):
                return .permission(prepared(request, in: folder), decision: decision)
            case .question(let request, let answers):
                return .question(prepared(request, in: folder), answers: answers)
            case .user, .assistant, .result:
                return block
            }
        }
    }

    private nonisolated static func path(of tool: String, input: JSONValue) -> String? {
        writers[tool].flatMap { input[$0]?.string }
    }

    /// The text that an Edit call replaces.
    private nonisolated static func edit(of tool: String, input: JSONValue) -> ACP.Diff? {
        guard tool == "Edit", let old = input["old_string"]?.string, let new = input["new_string"]?.string else { return nil }
        return ACP.Diff(path: path(of: tool, input: input) ?? "", oldText: old, newText: new)
    }

    /// The edits that a card shows: the text that an Edit replaces, or the content of a Write.
    private nonisolated static func edits(of tool: String, input: JSONValue) -> [ACP.Diff] {
        if let edit = edit(of: tool, input: input) { return [edit] }
        guard tool == "Write", let content = input["content"]?.string else { return [] }
        return [ACP.Diff(path: path(of: tool, input: input) ?? "", oldText: "", newText: content)]
    }

    // MARK: - Reading

    private func receive(_ line: String) {
        for item in SessionEvent.parse(line) {
            switch item {
            case .started(let id):
                let model = ACP.ConfigOption(id: "model", name: "Model", category: "model",
                                             currentValue: config.model ?? "", values: Self.models)
                send(.ready(ACP.SessionSetup(sessionID: id, currentMode: config.mode,
                                             modes: Self.modes, configOptions: [model])))
            case .commands(let names):
                send(.update(.commands(names.map { ACP.Command(name: $0) })))
            case .text(let text):
                send(.update(.agentMessage(hasText ? "\n\n" + text : text)))
                hasText = true
            case .toolCall(let id, let name, let input):
                hasText = false
                send(.update(.toolCall(Self.update(id: id, name: name, input: input))))
            case .toolResult(let id, let isError, let preview):
                send(.update(.toolCallUpdate(ACP.ToolCallUpdate(id: id, status: isError ? .failed : .completed,
                                                                text: preview))))
            case .permission(let request):
                ask(request)
            case .turnEnded(let result, let denials):
                let refused = denials.filter { $0.toolUseID.map { !deniedCalls.contains($0) } ?? true }
                deniedCalls.removeAll()
                send(.turnEnded(TurnEnd(stopReason: .endTurn,
                                        failure: result.failure ?? SessionEvent.failure(for: refused),
                                        text: result.text, durationMs: result.durationMs, costUSD: result.costUSD)))
            }
        }
    }

    /// Passes a request on, or allows it at once when an Always rule from this launch covers it.
    private func ask(_ request: PermissionRequest) {
        let request = Self.prepared(request, in: folder)
        if let rule = PermissionRule.rule(for: request), Self.allowRules[folder.path]?.contains(rule) == true {
            reply(to: request, ["behavior": "allow", "updatedInput": request.input.any])
            return
        }
        send(.permission(request))
    }

    private func reply(to request: PermissionRequest, _ response: [String: Any]) {
        let object: [String: Any] = ["type": "control_response",
                                     "response": ["subtype": "success", "request_id": request.requestID,
                                                  "response": response]]
        write { try Self.line(object) }
    }

    /// Writes one line of input. A line that cannot be written ends the turn
    /// and the process, because Claude Code would wait for it.
    private func write(_ line: () throws -> String) {
        do {
            process.write(try line())
        } catch {
            send(.turnEnded(TurnEnd(failure: error.localizedDescription)))
            process.terminate()
        }
    }

    private func send(_ value: AgentEvent) { event?(value) }
}
