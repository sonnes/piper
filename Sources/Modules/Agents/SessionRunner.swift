import CapturesDatabase
import Foundation
import Observation
import PiperCore

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

/// Runs agent sessions in folders and keeps every session.
///
/// A session has one agent process, behind an `AgentConnection`: Claude Code
/// through its stream-json bridge, or a command that speaks ACP. The process
/// stays open between turns. After a stop, a failure, or a restart of Piper,
/// the next message starts a new process that resumes the session.
@MainActor @Observable
public final class SessionRunner {

    // MARK: - Properties

    /// Every session, newest first.
    public private(set) var sessions: [AgentSession] = []
    /// The `claude` executable. A Claude Code turn fails when it is nil.
    public var executable: URL?
    /// The mode of a Claude Code session that has no mode of its own.
    public var permissionMode = PermissionMode.auto
    /// The model of a Claude Code session that has none of its own, for
    /// example `sonnet`. Nil leaves the choice to Claude Code.
    public var model: String?
    /// The agents that speak ACP, which the reader added.
    public var agents: [AgentDefinition] = []
    /// The ACP agents that offer no read-only mode, by id. Such an agent
    /// cannot answer in the margin. Piper learns this when a session opens.
    public private(set) var agentsWithoutReadOnlyMode: Set<String> = []
    /// Processes start through `zsh -l`, so the child gets the reader's PATH. Tests turn it off.
    public var usesLoginShell = true
    /// The time a turn can run. The time a card waits for the reader does not count.
    public var turnTimeout: TimeInterval = 10 * 60
    /// The number of turns that run at the same time.
    public var concurrency = 2
    /// The number of sessions the database keeps.
    public static let storedSessionLimit = 500
    static let quitMessage = "Piper quit before the turn finished."
    static let stopMessage = "Stopped."
    static let replyPrefix = "The reader did not use the card and wrote this instead:\n\n"
    private static let saveDelay = Duration.milliseconds(250)
    private static let previewLimit = 400

    private struct Message {
        let text: String
        let context: [String]
    }

    @ObservationIgnored private let database: Database?
    @ObservationIgnored private let report: (Error) -> Void
    @ObservationIgnored private var connections: [UUID: AgentConnection] = [:]
    /// The messages that wait for the next turn of a session.
    @ObservationIgnored private var queued: [UUID: [Message]] = [:]
    @ObservationIgnored private var turnTimers: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var turnStarts: [UUID: Date] = [:]
    @ObservationIgnored private var saves: [UUID: Task<Void, Never>] = [:]
    /// Why Piper ended a turn, for the result block.
    @ObservationIgnored private var stopReasons: [UUID: String] = [:]
    /// The cost so far that each agent reported, and the cost at the end of the last turn.
    @ObservationIgnored private var costs: [UUID: (now: Double, atTurnStart: Double)] = [:]
    /// The sessions whose model or mode changed while a process ran. The next turn starts a new process.
    @ObservationIgnored private var relaunches: Set<UUID> = []

    public var activeCount: Int { sessions.filter(\.isActive).count }
    public var attentionCount: Int { sessions.filter { $0.state == .needsYou }.count }

    // MARK: - Initialization

    /// Loads the stored sessions. A session that was active when Piper quit
    /// becomes idle, with a result block that says so.
    public init(database: Database?, report: @escaping (Error) -> Void = { _ in }) {
        self.database = database
        self.report = report
        guard let database else { return }
        do {
            let decoder = JSONDecoder()
            sessions = try database.loadSessions()
                .compactMap { try? decoder.decode(AgentSession.Snapshot.self, from: $0) }
                .map(AgentSession.init)
                .sorted { $0.createdAt > $1.createdAt }
            for session in sessions where session.isActive {
                endTurn(session, TurnResult(failure: Self.quitMessage), state: .idle)
            }
            try database.keepNewestSessions(Self.storedSessionLimit)
        } catch { report(error) }
    }

    // MARK: - Reading

    public func session(_ id: UUID) -> AgentSession? { sessions.first { $0.id == id } }

    /// The newest session that a note started.
    public func latestSession(for noteID: UUID) -> AgentSession? { sessions.first { $0.noteID == noteID } }

    /// The sessions of a folder that the Sessions list shows, the most recently changed first.
    public func sessions(in folder: String) -> [AgentSession] {
        sessions.filter { $0.folder == folder && $0.purpose == .session }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// The folders that have sessions in the Sessions list, sorted by name.
    public func folders() -> [String] {
        Array(Set(sessions.filter { $0.purpose == .session }.map(\.folder))).sorted {
            URL(fileURLWithPath: $0).lastPathComponent.localizedStandardCompare(URL(fileURLWithPath: $1).lastPathComponent) == .orderedAscending
        }
    }

    /// The agent of a session. Nil for an agent that the reader removed.
    public func agent(of session: AgentSession) -> AgentDefinition? {
        session.agentID == AgentDefinition.claudeCodeID ? .claudeCode : agents.first { $0.id == session.agentID }
    }

    // MARK: - Sessions

    /// Makes an empty session. The database stores it after the first message.
    @discardableResult
    public func newSession(in folder: String, noteID: UUID? = nil, command: SlashCommand? = nil,
                           agentID: String = AgentDefinition.claudeCodeID,
                           purpose: AgentSession.Purpose = .session) -> AgentSession {
        let session = AgentSession(folder: folder, noteID: noteID, command: command, agentID: agentID, purpose: purpose)
        sessions.insert(session, at: 0)
        return session
    }

    /// Changes the agent of a session that has no message yet.
    public func setAgent(_ agentID: String, for session: AgentSession) {
        guard session.isNew, session.agentID != agentID else { return }
        session.agentID = agentID
        session.model = nil
        session.mode = nil
        session.modes = []
        session.configOptions = []
        session.currentMode = nil
        session.slashCommands = nil
    }

    /// Changes the model. A running agent takes it at once, or at its next process.
    public func setModel(_ model: String?, for session: AgentSession) {
        guard session.model != model else { return }
        session.model = model
        applyChoices(session)
    }

    /// Changes the mode. A running agent takes it at once, or at its next process.
    public func setMode(_ mode: String?, for session: AgentSession) {
        guard session.mode != mode else { return }
        session.mode = mode
        applyChoices(session)
    }

    /// Sends a message. The turn starts when a slot is free and the session
    /// has no turn that runs.
    ///
    /// Each context path goes after the text. A slash command takes the paths
    /// as its argument, and other text names them as context files.
    ///
    /// A message while a card waits answers the card: Piper denies the tool
    /// call. Claude Code reads the message as the reason in the same turn.
    /// Another agent gets the message as the next turn.
    public func send(_ text: String, context: [String] = [], to session: AgentSession) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if session.blocks.isEmpty { session.command = SlashCommand(text) }
        session.draft = ""
        let context = ["compact", "clear", "context", "usage"].contains(SlashCommand(text)?.name ?? "") ? [] : context
        session.append(.user(id: UUID().uuidString, text: text, context: context))
        session.unread = false
        let waiting = session.pendingRequests
        if !waiting.isEmpty, connections[session.id] != nil {
            let reply = Self.replyPrefix + Self.messageBody(text, context: context)
            for request in waiting { deny(request, message: reply, in: session) }
            if session.agentID == AgentDefinition.claudeCodeID { return }
        }
        queued[session.id, default: []].append(Message(text: text, context: context))
        if !session.isActive { session.state = .waiting }
        persist(session, now: true)
        startWaitingSessions()
    }

    /// Answers a pending request with one option of the agent.
    public func respond(_ request: PermissionRequest, with option: ACP.PermissionOption, message: String? = nil,
                        in session: AgentSession) {
        guard isPending(request, in: session) else { return }
        connections[session.id]?.respond(to: request, with: option, message: message)
        let decision: PermissionDecision = switch option.kind {
        case .allowOnce: .allowed
        case .allowAlways: .allowedAlways
        case .rejectOnce, .rejectAlways: .denied
        }
        session.update(TranscriptBlock.permission(request, decision: .pending).id) {
            $0 = request.isQuestion ? .question(request, answers: [:]) : .permission(request, decision: decision)
        }
        resume(session)
    }

    /// Allows a pending tool call. Always also keeps the choice: Claude Code
    /// writes an allow rule into the folder's `.claude/settings.local.json`.
    public func allow(_ request: PermissionRequest, always: Bool = false, in session: AgentSession) {
        let options = request.options ?? ClaudeCodeConnection.options(in: URL(fileURLWithPath: session.folder))
        let option = (always ? options.first { $0.kind == .allowAlways } : nil) ?? options.first { $0.kind == .allowOnce }
            ?? options.first { $0.kind.allows }
        guard let option else { return }
        respond(request, with: option, in: session)
    }

    /// Denies a pending tool call. Claude Code reads the message as the tool result.
    public func deny(_ request: PermissionRequest, message: String? = nil, in session: AgentSession) {
        let options = request.options ?? ClaudeCodeConnection.options(in: URL(fileURLWithPath: session.folder))
        let option = options.first { $0.kind == .rejectOnce } ?? options.first { !$0.kind.allows }
            ?? ACP.PermissionOption(id: "deny", name: "Deny", kind: .rejectOnce)
        respond(request, with: option, message: message, in: session)
    }

    /// Answers an `AskUserQuestion` call. The answers map each question to the
    /// labels of the chosen options, joined with commas.
    public func answer(_ request: PermissionRequest, answers: [String: String], in session: AgentSession) {
        guard isPending(request, in: session) else { return }
        connections[session.id]?.answer(request, answers: answers)
        session.update(TranscriptBlock.question(request, answers: nil).id) {
            $0 = .question(request, answers: answers)
        }
        resume(session)
    }

    /// Stops the turn of a session. The next message continues the session.
    public func stop(_ session: AgentSession) {
        guard session.isActive else { return }
        queued.removeValue(forKey: session.id)
        if session.state != .waiting, let connection = connections[session.id] {
            stopReasons[session.id] = Self.stopMessage
            connection.cancel()
        } else {
            endTurn(session, TurnResult(failure: Self.stopMessage), state: .idle)
            startWaitingSessions()
        }
    }

    /// Stops every turn and ends every idle process.
    public func stopAll() {
        for session in sessions where session.isActive { stop(session) }
        for session in sessions where !session.isActive {
            connections.removeValue(forKey: session.id)?.close()
        }
    }

    /// Stops a session and removes it from the list and the database.
    public func delete(_ session: AgentSession) {
        stop(session)
        connections.removeValue(forKey: session.id)?.terminate()
        stopReasons.removeValue(forKey: session.id)
        saves.removeValue(forKey: session.id)?.cancel()
        turnTimers.removeValue(forKey: session.id)?.cancel()
        turnStarts.removeValue(forKey: session.id)
        costs.removeValue(forKey: session.id)
        relaunches.remove(session.id)
        queued.removeValue(forKey: session.id)
        sessions.removeAll { $0.id == session.id }
        do { try database?.deleteSession(id: session.id) } catch { report(error) }
    }

    public func markRead(_ session: AgentSession) {
        guard session.unread else { return }
        session.unread = false
        persist(session)
    }

    // MARK: - Turns

    private func startWaitingSessions() {
        while sessions.filter({ $0.state == .running || $0.state == .needsYou }).count < concurrency,
              let session = sessions.last(where: { $0.state == .waiting }) {
            beginTurn(session)
        }
    }

    /// Starts a turn with every queued message. The messages go to the agent
    /// as one prompt, because an agent runs one prompt at a time.
    private func beginTurn(_ session: AgentSession) {
        let messages = queued.removeValue(forKey: session.id) ?? []
        if relaunches.remove(session.id) != nil { connections.removeValue(forKey: session.id)?.close() }
        guard connections[session.id] != nil || launch(session) else { return }
        session.state = .running
        turnStarts[session.id] = Date()
        if let now = costs[session.id]?.now { costs[session.id] = (now: now, atTurnStart: now) }
        if let message = Self.joined(messages) { connections[session.id]?.prompt(message.text, context: message.context) }
        startTurnTimer(for: session)
        persist(session, now: true)
    }

    /// Starts a process. A process that cannot start ends the turn with a failure.
    private func launch(_ session: AgentSession) -> Bool {
        let folder = URL(fileURLWithPath: session.folder, isDirectory: true)
        let connection: AgentConnection
        if session.agentID == AgentDefinition.claudeCodeID {
            guard let executable else {
                endTurn(session, TurnResult(failure: "Piper cannot find the claude command. Choose it in Settings > AI."),
                        state: .failed)
                return false
            }
            let config = SessionConfig(folder: folder, resumeToken: session.resumeToken,
                                       model: session.model ?? model, mode: session.mode ?? permissionMode.rawValue,
                                       purpose: session.purpose)
            connection = ClaudeCodeConnection(executable: executable, config: config, usesLoginShell: usesLoginShell,
                                              report: report)
        } else {
            guard let agent = agent(of: session) else {
                endTurn(session, TurnResult(failure: "Piper cannot find the agent of this session. Add it in Settings > AI."),
                        state: .failed)
                return false
            }
            let config = SessionConfig(folder: folder, resumeToken: session.resumeToken, model: session.model,
                                       mode: session.mode, purpose: session.purpose)
            connection = StdioAgentConnection(agent: agent, config: config, usesLoginShell: usesLoginShell)
        }
        let id = session.id
        do {
            try connection.start(event: { [weak self, weak connection] event in
                guard let self, let connection, self.connections[id] === connection else { return }
                self.receive(event, for: id)
            }, exit: { [weak self, weak connection] status, errors in
                guard let self, let connection else { return }
                self.exited(id, connection: connection, status: status, errors: errors)
            })
        } catch {
            endTurn(session, TurnResult(failure: "Cannot start the agent: \(error.localizedDescription)"), state: .failed)
            return false
        }
        connections[id] = connection
        return true
    }

    private func receive(_ event: AgentEvent, for id: UUID) {
        guard let session = session(id) else { return }
        switch event {
        case .ready(let setup):
            if session.agentID != AgentDefinition.claudeCodeID {
                if ACP.Mode.readOnly(in: setup.modes) == nil {
                    agentsWithoutReadOnlyMode.insert(session.agentID)
                } else {
                    agentsWithoutReadOnlyMode.remove(session.agentID)
                }
            }
            session.resumeToken = setup.sessionID
            session.modes = setup.modes
            session.configOptions = setup.configOptions
            session.currentMode = setup.currentMode
            persist(session, now: true)
        case .update(let update):
            apply(update, to: session)
        case .permission(let request):
            ask(request, in: session)
        case .turnEnded(let end):
            finish(session, end)
        case .modeRejected(let message):
            session.mode = nil
            persist(session, now: true)
            report(PiperError("The agent did not change the mode: \(message)"))
        case .modelRejected(let message):
            session.model = nil
            persist(session, now: true)
            report(PiperError("The agent did not change the model: \(message)"))
        }
    }

    private func apply(_ update: ACP.SessionUpdate, to session: AgentSession) {
        switch update {
        case .agentMessage(let text):
            guard !text.isEmpty else { return }
            if case .assistant(let blockID, let earlier)? = session.blocks.last {
                session.update(blockID) { $0 = .assistant(id: blockID, text: earlier + text) }
            } else {
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                session.append(.assistant(id: UUID().uuidString, text: text))
            }
            persist(session)
        case .toolCall(let call), .toolCallUpdate(let call):
            let folder = URL(fileURLWithPath: session.folder, isDirectory: true)
            let found = session.update(call.id) { block in
                guard case .toolCall(var existing) = block else { return }
                Self.merge(call, into: &existing, folder: folder)
                block = .toolCall(existing)
            }
            if !found {
                var new = ToolCall(id: call.id, name: call.name ?? call.title ?? "Tool call",
                                   detail: call.name == nil ? "" : call.title ?? "", kind: call.kind)
                Self.merge(call, into: &new, folder: folder)
                session.append(.toolCall(new))
            }
            persist(session)
        case .commands(let commands):
            session.slashCommands = commands.map(\.name).filter { SlashCommand.isName($0) }
            persist(session, now: true)
        case .currentMode(let mode):
            session.currentMode = mode
        case .configOptions(let options):
            session.configOptions = options
        case .usage(_, _, let cost):
            guard let cost else { return }
            costs[session.id] = (now: cost, atTurnStart: costs[session.id]?.atTurnStart ?? 0)
        case .agentThought, .userMessage, .plan, .other:
            return
        }
    }

    /// Copies what an update knows into a tool call. A path stays only for a
    /// call that writes a file inside the folder, relative to it.
    private static func merge(_ update: ACP.ToolCallUpdate, into call: inout ToolCall, folder: URL) {
        if let kind = update.kind { call.kind = kind }
        if let title = update.title {
            // A call that has no tool name shows its title as the name.
            if update.name == nil, call.detail.isEmpty { call.name = title } else { call.detail = title }
        }
        if let path = update.paths?.first, [.edit, .delete, .move].contains(call.toolKind) {
            call.path = SessionEvent.relativePath(path, in: folder)
        }
        if let diff = update.diffs?.first {
            call.diff = ToolCall.Diff(old: diff.oldText ?? "", new: diff.newText)
            if call.path == nil { call.path = SessionEvent.relativePath(diff.path, in: folder) }
        }
        if let text = update.text { call.resultPreview = String(text.prefix(previewLimit)) }
        switch update.status {
        case .completed?: call.isFinished = true
        case .failed?:
            call.isFinished = true
            call.isError = true
        default: break
        }
    }

    private func finish(_ session: AgentSession, _ end: TurnEnd) {
        let id = session.id
        let stopped = stopReasons.removeValue(forKey: id)
        var failure = end.failure
        if end.stopReason == .cancelled { failure = stopped ?? Self.stopMessage }
        let measured = turnStarts.removeValue(forKey: id).map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
        let cost = end.costUSD ?? costs[id].map { max(0, $0.now - $0.atTurnStart) } ?? 0
        let result = TurnResult(text: end.text ?? "", durationMs: end.durationMs ?? measured, costUSD: cost, failure: failure)
        let turn = session.blocks.reversed().prefix {
            if case .user = $0 { return false }
            return true
        }
        let hasText = turn.contains { if case .assistant = $0 { return true }; return false }
        if result.failure == nil, !result.text.isEmpty, !hasText {
            session.append(.assistant(id: UUID().uuidString, text: result.text))
        }
        let state: AgentSession.State = failure == nil || failure == Self.stopMessage ? .idle : .failed
        endTurn(session, result, state: state)
        if queued[id]?.isEmpty == false { session.state = .waiting }
        startWaitingSessions()
    }

    /// Shows a card. A margin session shows none: it allows a call that only
    /// reads, and denies any other.
    private func ask(_ request: PermissionRequest, in session: AgentSession) {
        if session.purpose == .margin {
            let options = request.options ?? ClaudeCodeConnection.options(in: URL(fileURLWithPath: session.folder))
            let readOnly = !request.isQuestion && (request.kind ?? ClaudeCodeConnection.kind(of: request.toolName)).isReadOnly
            let option = readOnly ? options.first { $0.kind == .allowOnce } : options.first { !$0.kind.allows }
            if let option { connections[session.id]?.respond(to: request, with: option, message: nil) }
            return
        }
        session.append(request.isQuestion ? .question(request, answers: nil) : .permission(request, decision: .pending))
        session.state = .needsYou
        session.unread = true
        turnTimers.removeValue(forKey: session.id)?.cancel()
        persist(session, now: true)
    }

    private func isPending(_ request: PermissionRequest, in session: AgentSession) -> Bool {
        session.pendingRequests.contains { $0.requestID == request.requestID }
    }

    /// Goes back to running after the last card of a turn has an answer.
    private func resume(_ session: AgentSession) {
        if session.state == .needsYou, session.pendingRequest == nil {
            session.state = .running
            startTurnTimer(for: session)
        }
        persist(session, now: true)
    }

    /// Gives a new model or mode to the agent. An agent that takes it only at
    /// start gets a new process at the next turn.
    private func applyChoices(_ session: AgentSession) {
        persist(session, now: true)
        guard let connection = connections[session.id],
              !connection.apply(model: session.model, mode: session.mode) else { return }
        if session.isActive {
            relaunches.insert(session.id)
        } else {
            connections.removeValue(forKey: session.id)?.close()
        }
    }

    private func exited(_ id: UUID, connection: AgentConnection, status: Int32, errors: String) {
        guard connections[id] === connection else { return }
        connections.removeValue(forKey: id)
        let reason = stopReasons.removeValue(forKey: id)
        turnStarts.removeValue(forKey: id)
        guard let session = session(id), session.isActive else { return }
        queued.removeValue(forKey: id)
        let detail = errors.trimmingCharacters(in: .whitespacesAndNewlines)
        let failure = reason ?? (detail.isEmpty ? "The agent exited with status \(status) and no result." : detail)
        endTurn(session, TurnResult(failure: failure), state: reason == Self.stopMessage ? .idle : .failed)
        startWaitingSessions()
    }

    /// Adds the result block. A card that still waits gets a denial, because
    /// its turn is over.
    private func endTurn(_ session: AgentSession, _ result: TurnResult, state: AgentSession.State) {
        for block in session.blocks {
            switch block {
            case .permission(let request, decision: .pending):
                session.update(block.id) { $0 = .permission(request, decision: .denied) }
            case .question(let request, answers: nil):
                session.update(block.id) { $0 = .question(request, answers: [:]) }
            default:
                continue
            }
        }
        turnTimers.removeValue(forKey: session.id)?.cancel()
        session.append(.result(id: UUID().uuidString, result))
        session.state = state
        session.unread = true
        persist(session, now: true)
    }

    // MARK: - Timers

    private func startTurnTimer(for session: AgentSession) {
        let id = session.id
        let limit = turnTimeout
        turnTimers[id]?.cancel()
        turnTimers[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard !Task.isCancelled, let self, let connection = self.connections[id] else { return }
            self.stopReasons[id] = "Stopped after "
                + Duration.seconds(limit).formatted(.units(allowed: [.minutes, .seconds], width: .wide)) + "."
            connection.terminate()
        }
    }

    // MARK: - Storage

    /// Stores a session. A change of state stores it at once. Text and tool
    /// calls wait a short time, so a fast stream writes less often.
    private func persist(_ session: AgentSession, now: Bool = false) {
        guard database != nil, !session.blocks.isEmpty else { return }
        saves.removeValue(forKey: session.id)?.cancel()
        guard !now else { return save(session) }
        saves[session.id] = Task { [weak self, weak session] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled, let self, let session else { return }
            self.saves.removeValue(forKey: session.id)
            self.save(session)
        }
    }

    private func save(_ session: AgentSession) {
        do {
            try database?.saveSession(id: session.id, folder: session.folder, updatedAt: session.updatedAt,
                                      data: JSONEncoder().encode(session.snapshot))
        } catch { report(error) }
    }

    // MARK: - Messages

    /// The queued messages of a turn as one message. The texts join with a
    /// blank line. The context paths join in order, each path once.
    private static func joined(_ messages: [Message]) -> Message? {
        guard messages.count > 1 else { return messages.first }
        var context: [String] = []
        for path in messages.flatMap(\.context) where !context.contains(path) { context.append(path) }
        return Message(text: messages.map(\.text).joined(separator: "\n\n"), context: context)
    }

    /// The text of a message with its context paths.
    nonisolated static func messageBody(_ text: String, context: [String]) -> String {
        guard !context.isEmpty else { return text }
        return text + (SlashCommand(text) != nil
            ? " " + context.joined(separator: " ")
            : "\n\n" + context.map { "Context file: " + $0 }.joined(separator: "\n"))
    }
}
