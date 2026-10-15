import Foundation

/// Runs an agent that speaks ACP on standard input and output, for example
/// `gemini --experimental-acp` or `opencode acp`.
///
/// The connection starts the process, sends `initialize`, then opens the
/// session: `session/load` or `session/resume` for a known session id, when
/// the agent offers it, and `session/new` otherwise. A prompt waits until the
/// session is open. Piper offers no file system and no terminal, so the agent
/// uses its own tools.
///
/// A margin session runs in a mode of the agent that changes no files. If the
/// agent offers no such mode, the turn fails and no prompt goes to the agent.
@MainActor
public final class StdioAgentConnection: AgentConnection {

    // MARK: - Properties

    public private(set) var info: ACP.AgentInfo?
    /// The ACP session id, after the session opens.
    public private(set) var sessionID: String?

    private let process: AgentProcess
    private let config: SessionConfig
    private let agentName: String
    private var event: (@MainActor (AgentEvent) -> Void)?
    private var nextID = 1
    /// What to do with the response to each request that Piper sent.
    private var handlers: [Int: (Result<JSONValue, PromptFailure>) -> Void] = [:]
    /// The prompts that wait for the session to open.
    private var queued: [String] = []
    /// True after the session opens, and after a margin session is in its read-only mode.
    private var isOpen = false
    /// The JSON-RPC ids of the permission requests that wait for the reader.
    private var requestIDs: [String: JSONValue] = [:]
    /// True while `session/load` replays the history, which Piper already has.
    private var isLoading = false
    private var isCancelling = false
    /// The id of the model option of the session, after it opens.
    private var modelOptionID: String?

    private struct PromptFailure: Error {
        let message: String
    }

    // MARK: - Initialization

    public init(agent: AgentDefinition, config: SessionConfig, usesLoginShell: Bool) {
        self.config = config
        agentName = agent.name
        process = AgentProcess(command: agent.command, arguments: agent.arguments,
                               folder: config.folder, usesLoginShell: usesLoginShell)
    }

    // MARK: - AgentConnection

    public func start(event: @escaping @MainActor (AgentEvent) -> Void,
                      exit: @escaping @MainActor (Int32, String) -> Void) throws {
        self.event = event
        try process.start(line: { [weak self] line in self?.receive(line) }, exit: exit)
        call("initialize", Self.initializeParams) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                info = ACP.AgentInfo(json: value)
                openSession()
            case .failure(let failure):
                fail("The agent did not start: \(failure.message)")
            }
        }
    }

    public func prompt(_ text: String, context: [String]) {
        let body = SessionRunner.messageBody(text, context: context)
        guard isOpen else { return queued.append(body) }
        sendPrompt(body)
    }

    public func respond(to request: PermissionRequest, with option: ACP.PermissionOption, message: String?) {
        guard let id = requestIDs.removeValue(forKey: request.requestID) else { return }
        write(.response(id: id, result: .object(["outcome": .object(["outcome": .string("selected"),
                                                                       "optionId": .string(option.id)])])))
    }

    /// An agent over ACP asks no questions, so there is nothing to answer.
    public func answer(_ request: PermissionRequest, answers: [String: String]) {}

    /// Sends `session/cancel`. The agent ends the turn with `cancelled`. Each
    /// request that waits gets the outcome `cancelled`, as the protocol asks.
    public func cancel() {
        guard let sessionID else { return process.terminate() }
        isCancelling = true
        for id in requestIDs.values {
            write(.response(id: id, result: .object(["outcome": .object(["outcome": .string("cancelled")])])))
        }
        requestIDs.removeAll()
        write(.notification(method: "session/cancel", params: .object(["sessionId": .string(sessionID)])))
    }

    /// Changes the model and the mode. A margin session keeps its read-only mode.
    public func apply(model: String?, mode: String?) -> Bool {
        guard sessionID != nil else { return false }
        if let mode, config.purpose != .margin { setMode(mode) }
        if let model { setModel(model) }
        return true
    }

    public func close() { process.closeInput() }
    public func terminate() { process.terminate() }

    // MARK: - Session

    /// The parameters of `initialize`. A health check in Settings sends them too.
    nonisolated static var initializeParams: JSONValue {
        .object(["protocolVersion": .number(Double(ACP.protocolVersion)),
                 "clientCapabilities": .object(["fs": .object(["readTextFile": .bool(false), "writeTextFile": .bool(false)]),
                                                "terminal": .bool(false)]),
                 "clientInfo": .object(["name": .string("piper"), "title": .string("Piper"),
                                        "version": .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")])])
    }

    private func openSession() {
        let folder = JSONValue.string(config.folder.path)
        if let token = config.resumeToken, let info, info.loadsSessions || info.resumesSessions {
            isLoading = info.loadsSessions
            let method = info.loadsSessions ? "session/load" : "session/resume"
            call(method, .object(["sessionId": .string(token), "cwd": folder, "mcpServers": .array([])])) { [weak self] result in
                guard let self else { return }
                isLoading = false
                switch result {
                case .success(let value): opened(ACP.SessionSetup(sessionID: token, json: value))
                case .failure: newSession()
                }
            }
        } else {
            newSession()
        }
    }

    private func newSession() {
        call("session/new", .object(["cwd": .string(config.folder.path), "mcpServers": .array([])])) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                guard let id = value["sessionId"]?.string else { return fail("The agent did not open a session.") }
                opened(ACP.SessionSetup(sessionID: id, json: value))
            case .failure(let failure):
                fail("The agent did not open a session: \(failure.message)")
            }
        }
    }

    private func opened(_ setup: ACP.SessionSetup) {
        sessionID = setup.sessionID
        let model = setup.configOptions.first { $0.category == "model" }
        modelOptionID = model?.id
        send(.ready(setup))
        if let model, let value = config.model, value != model.currentValue, model.values.contains(where: { $0.id == value }) {
            setModel(value)
        }
        if config.purpose == .margin { return openReadOnly(setup) }
        if let mode = config.mode, mode != setup.currentMode, setup.modes.contains(where: { $0.id == mode }) {
            setMode(mode)
        }
        sendQueuedPrompts()
    }

    /// Puts a margin session in its read-only mode before the first prompt.
    private func openReadOnly(_ setup: ACP.SessionSetup) {
        guard let mode = ACP.Mode.readOnly(in: setup.modes) else {
            return fail(Self.noReadOnlyMode(agentName))
        }
        guard mode.id != setup.currentMode else { return sendQueuedPrompts() }
        setMode(mode.id) { [weak self] failure in
            guard let self else { return }
            if let failure {
                fail("\(agentName) did not change to its \(mode.name) mode: \(failure)")
            } else {
                sendQueuedPrompts()
            }
        }
    }

    /// The failure of a margin turn on an agent that has no read-only mode.
    static func noReadOnlyMode(_ name: String) -> String {
        "\(name) has no read-only mode, so it cannot answer in the margin. The next answer uses Claude Code."
    }

    private func sendQueuedPrompts() {
        isOpen = true
        let prompts = queued
        queued.removeAll()
        prompts.forEach(sendPrompt)
    }

    /// Changes the mode. Without `done`, a refusal goes to the runner as an event.
    private func setMode(_ mode: String, done: ((String?) -> Void)? = nil) {
        guard let sessionID else { return }
        call("session/set_mode", .object(["sessionId": .string(sessionID), "modeId": .string(mode)])) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                send(.update(.currentMode(mode)))
                done?(nil)
            case .failure(let failure):
                if let done { done(failure.message) } else { send(.modeRejected(failure.message)) }
            }
        }
    }

    private func setModel(_ model: String) {
        guard let sessionID, let modelOptionID else { return }
        let rejected: (Result<JSONValue, PromptFailure>) -> Void = { [weak self] result in
            if case .failure(let failure) = result { self?.send(.modelRejected(failure.message)) }
        }
        if modelOptionID == ACP.SessionSetup.legacyModelOptionID {
            call("session/set_model", .object(["sessionId": .string(sessionID), "modelId": .string(model)]), then: rejected)
        } else {
            call("session/set_config_option", .object(["sessionId": .string(sessionID), "configId": .string(modelOptionID),
                                                       "value": .string(model)]), then: rejected)
        }
    }

    private func sendPrompt(_ body: String) {
        guard let sessionID else { return }
        isCancelling = false
        let params = JSONValue.object(["sessionId": .string(sessionID),
                                       "prompt": .array([.object(["type": .string("text"), "text": .string(body)])])])
        call("session/prompt", params) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                let reason = value["stopReason"]?.string.flatMap(ACP.StopReason.init(rawValue:)) ?? .endTurn
                send(.turnEnded(TurnEnd(stopReason: reason, failure: Self.failure(for: reason))))
            case .failure(let failure):
                send(.turnEnded(TurnEnd(stopReason: isCancelling ? .cancelled : .endTurn,
                                        failure: isCancelling ? nil : failure.message)))
            }
        }
    }

    /// The failure text for a stop reason that is not a normal end.
    static func failure(for reason: ACP.StopReason) -> String? {
        switch reason {
        case .endTurn, .cancelled: return nil
        case .maxTokens: return "The agent reached its token limit."
        case .maxTurnRequests: return "The agent reached its limit of requests in one turn."
        case .refusal: return "The agent refused to continue."
        }
    }

    /// Ends a turn that cannot start. The process ends too, so the next message starts again.
    private func fail(_ message: String) {
        queued.removeAll()
        send(.turnEnded(TurnEnd(failure: message)))
        process.terminate()
    }

    // MARK: - Reading

    private func receive(_ line: String) {
        switch JSONRPCMessage.parse(line) {
        case .response(let id, let result):
            guard let id = id.int else { return }
            handlers.removeValue(forKey: id)?(.success(result))
        case .error(let id, _, let message):
            guard let id = id.int else { return }
            handlers.removeValue(forKey: id)?(.failure(PromptFailure(message: message)))
        case .notification("session/update", let params):
            guard !isLoading, let update = params["update"] else { return }
            send(.update(ACP.SessionUpdate(json: update)))
        case .request(let id, "session/request_permission", let params):
            guard let call = params["toolCall"].flatMap(ACP.ToolCallUpdate.init(json:)) else {
                return write(.error(id: id, code: JSONRPCMessage.invalidParams,
                                    message: "The permission request has no tool call with a toolCallId."))
            }
            let key = Self.key(of: id)
            requestIDs[key] = id
            send(.permission(PermissionRequest(
                requestID: key, toolName: call.name ?? call.title ?? "Tool call", input: call.rawInput ?? .null,
                description: call.name == nil ? nil : call.title, toolUseID: call.id, kind: call.kind,
                options: params["options"]?.array.compactMap(ACP.PermissionOption.init(json:)) ?? [],
                diffs: call.diffs)))
        case .request(let id, _, _):
            write(.error(id: id, code: JSONRPCMessage.methodNotFound, message: "Piper does not offer this method."))
        case .notification, nil:
            return
        }
    }

    /// A string form of a JSON-RPC id, for the request id that Piper stores.
    private static func key(of id: JSONValue) -> String {
        if let string = id.string { return string }
        if let int = id.int { return String(int) }
        return JSONRPCMessage.response(id: id, result: .null).line
    }

    // MARK: - Writing

    private func call(_ method: String, _ params: JSONValue,
                      then handler: @escaping (Result<JSONValue, PromptFailure>) -> Void) {
        let id = nextID
        nextID += 1
        handlers[id] = handler
        write(.request(id: .number(Double(id)), method: method, params: params))
    }

    private func write(_ message: JSONRPCMessage) { process.write(message.line) }

    private func send(_ value: AgentEvent) { event?(value) }
}
