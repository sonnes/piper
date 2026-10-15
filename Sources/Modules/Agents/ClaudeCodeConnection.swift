import Foundation

/// Runs `claude -p` with stream-json in both directions, and turns its stream
/// into ACP events. Claude Code needs no adapter and no Node this way.
///
/// One process serves many turns. A change of model or mode takes a new
/// process, which resumes the session with `--resume`.
@MainActor
public final class ClaudeCodeConnection: AgentConnection {

    // MARK: - Properties

    /// The tools of a margin session: they read files and the web, and they change nothing.
    public nonisolated static let marginTools = "Read,Grep,Glob,WebSearch,WebFetch"
    static let denyMessage = "The reader denied this tool call in Piper."

    /// The modes that `--permission-mode` takes, in menu order.
    public nonisolated static let modes = PermissionMode.allCases.map {
        ACP.Mode(id: $0.rawValue, name: $0.name, description: $0.detail)
    }

    /// The values that `--model` takes. An empty value leaves the choice to Claude Code.
    public nonisolated static let models = [
        ACP.ConfigOption.Value(id: "sonnet", name: "Sonnet"),
        ACP.ConfigOption.Value(id: "opus", name: "Opus"),
        ACP.ConfigOption.Value(id: "haiku", name: "Haiku"),
        ACP.ConfigOption.Value(id: "", name: "Claude Code Default")
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

    public init(executable: URL, config: SessionConfig, usesLoginShell: Bool, report: @escaping (Error) -> Void) {
        self.folder = config.folder
        self.config = config
        self.report = report
        process = AgentProcess(command: executable.path, arguments: Self.arguments(for: config),
                               folder: config.folder, usesLoginShell: usesLoginShell)
    }

    /// The command line of a session.
    nonisolated static func arguments(for config: SessionConfig) -> [String] {
        var arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                         "--permission-prompt-tool", "stdio", "--permission-mode", config.mode ?? "auto"]
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

    public func start(event: @escaping @MainActor (AgentEvent) -> Void,
                      exit: @escaping @MainActor (Int32, String) -> Void) throws {
        self.event = event
        try process.start(line: { [weak self] line in self?.receive(line) }, exit: exit)
    }

    public func prompt(_ text: String, context: [String]) {
        hasText = false
        process.write(Self.userLine(text, context: context))
    }

    public func respond(to request: PermissionRequest, with option: ACP.PermissionOption, message: String?) {
        if option.kind.allows {
            if option.kind == .allowAlways, let rule = PermissionRule.rule(toolName: request.toolName, input: request.input) {
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
    nonisolated static func userLine(_ text: String, context: [String]) -> String {
        let body = SessionRunner.messageBody(text, context: context)
        let object: [String: Any] = ["type": "user",
                                     "message": ["role": "user", "content": [["type": "text", "text": body]]]]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// The default choices of a permission card of Claude Code.
    public nonisolated static func options(in folder: URL) -> [ACP.PermissionOption] {
        [ACP.PermissionOption(id: "allow", name: "Allow Once", kind: .allowOnce),
         ACP.PermissionOption(id: "always", name: "Always in \(folder.lastPathComponent)", kind: .allowAlways),
         ACP.PermissionOption(id: "deny", name: "Deny", kind: .rejectOnce)]
    }

    /// The ACP kind of a Claude Code tool.
    public nonisolated static func kind(of tool: String) -> ACP.ToolKind {
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

    // MARK: - Reading

    private func receive(_ line: String) {
        for item in SessionEvent.parse(line) {
            switch item {
            case .started(let id):
                let model = ACP.ConfigOption(id: "model", name: "Model", category: "model",
                                             currentValue: config.model ?? "", values: Self.models)
                send(.ready(ACP.SessionSetup(sessionID: id, currentMode: config.mode ?? "auto",
                                             modes: Self.modes, configOptions: [model])))
            case .commands(let names):
                send(.update(.commands(names.map { ACP.Command(name: $0) })))
            case .text(let text):
                send(.update(.agentMessage(hasText ? "\n\n" + text : text)))
                hasText = true
            case .toolCall(let call):
                hasText = false
                send(.update(.toolCall(ACP.ToolCallUpdate(
                    id: call.id, name: call.name, title: call.detail, kind: Self.kind(of: call.name), status: .pending,
                    paths: call.path.map { [$0] },
                    diffs: call.diff.map { [ACP.Diff(path: call.path ?? "", oldText: $0.old, newText: $0.new)] }))))
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
        if !request.isQuestion, let rule = PermissionRule.rule(toolName: request.toolName, input: request.input),
           Self.allowRules[folder.path]?.contains(rule) == true {
            reply(to: request, ["behavior": "allow", "updatedInput": request.input.any])
            return
        }
        var request = request
        request.kind = Self.kind(of: request.toolName)
        request.options = Self.options(in: folder)
        send(.permission(request))
    }

    private func reply(to request: PermissionRequest, _ response: [String: Any]) {
        let object: [String: Any] = ["type": "control_response",
                                     "response": ["subtype": "success", "request_id": request.requestID,
                                                  "response": response]]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
        process.write(String(decoding: data, as: UTF8.self))
    }

    private func send(_ value: AgentEvent) { event?(value) }
}
