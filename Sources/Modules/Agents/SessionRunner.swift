import CapturesDatabase
import Foundation
import Observation

/// How much Claude Code does without a card.
public enum PermissionMode: String, CaseIterable, Sendable {
    /// Claude Code allows or asks for each tool call by its risk.
    case auto
    /// Edits files without a card. Other tools show a card.
    case acceptEdits
    /// Every tool call that the folder settings do not allow shows a card.
    case ask = "manual"
    /// Runs every tool without a card.
    case bypassPermissions
}

/// Runs Claude Code sessions in folders and keeps every session.
///
/// A session has one `claude` process. The process reads messages and
/// permission replies on standard input and writes its JSON stream on standard
/// output. It stays open between turns. After a stop, a failure, or a restart
/// of Piper, the next message starts a new process with `--resume`.
@MainActor @Observable
public final class SessionRunner {

    // MARK: - Properties

    /// Every session, newest first.
    public private(set) var sessions: [AgentSession] = []
    /// The `claude` executable. A turn fails when it is nil.
    public var executable: URL?
    public var permissionMode = PermissionMode.auto
    /// The value of `--model`, for example `sonnet`. Nil leaves the choice to Claude Code.
    public var model: String?
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
    static let denyMessage = "The reader denied this tool call in Piper."
    static let replyPrefix = "The reader did not use the card and wrote this instead:\n\n"
    private static let saveDelay = Duration.milliseconds(250)

    @ObservationIgnored private let database: Database?
    @ObservationIgnored private let report: (Error) -> Void
    @ObservationIgnored private var processes: [UUID: ClaudeProcess] = [:]
    /// The message lines that wait for the next turn of a session.
    @ObservationIgnored private var queued: [UUID: [String]] = [:]
    @ObservationIgnored private var turnTimers: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var saves: [UUID: Task<Void, Never>] = [:]
    /// Why Piper ended a process, for the result block.
    @ObservationIgnored private var stopReasons: [UUID: String] = [:]
    /// The tool calls that the reader denied in the current turn.
    @ObservationIgnored private var deniedCalls: [UUID: Set<String>] = [:]
    /// The rules that Always added in this launch, by folder.
    @ObservationIgnored private var allowRules: [String: Set<String>] = [:]

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

    /// The sessions of a folder, the most recently changed first.
    public func sessions(in folder: String) -> [AgentSession] {
        sessions.filter { $0.folder == folder }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// The folders that have sessions, sorted by name.
    public func folders() -> [String] {
        Array(Set(sessions.map(\.folder))).sorted {
            URL(fileURLWithPath: $0).lastPathComponent.localizedStandardCompare(URL(fileURLWithPath: $1).lastPathComponent) == .orderedAscending
        }
    }

    // MARK: - Sessions

    /// Makes an empty session. The database stores it after the first message.
    @discardableResult
    public func newSession(in folder: String, noteID: UUID? = nil, command: SlashCommand? = nil) -> AgentSession {
        let session = AgentSession(folder: folder, noteID: noteID, command: command)
        sessions.insert(session, at: 0)
        return session
    }

    /// Sends a message. The turn starts when a slot is free and the session
    /// has no turn that runs.
    ///
    /// Each context path goes after the text. A slash command takes the paths
    /// as its argument, and other text names them as context files.
    ///
    /// A message while a card waits answers the card: Piper denies the tool
    /// call, and Claude reads the message as the reason in the same turn.
    public func send(_ text: String, context: [String] = [], to session: AgentSession) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        session.append(.user(id: UUID().uuidString, text: text, context: context))
        session.unread = false
        let waiting = pendingRequests(in: session)
        if !waiting.isEmpty, processes[session.id] != nil {
            let reply = Self.replyPrefix + Self.messageBody(text, context: context)
            for request in waiting { deny(request, message: reply, in: session) }
            return
        }
        queued[session.id, default: []].append(Self.userLine(text, context: context))
        if !session.isActive { session.state = .waiting }
        persist(session, now: true)
        startWaitingSessions()
    }

    /// Allows a pending tool call. Always also writes an allow rule into the
    /// folder's `.claude/settings.local.json`.
    public func allow(_ request: PermissionRequest, always: Bool = false, in session: AgentSession) {
        guard isPending(request, in: session) else { return }
        var decision = PermissionDecision.allowed
        if always, let rule = PermissionRule.rule(toolName: request.toolName, input: request.input) {
            do {
                try PermissionRule.append(rule, to: URL(fileURLWithPath: session.folder, isDirectory: true))
                allowRules[session.folder, default: []].insert(rule)
                decision = .allowedAlways
            } catch { report(error) }
        }
        reply(to: request, in: session, ["behavior": "allow", "updatedInput": request.input.any])
        session.update(TranscriptBlock.permission(request, decision: .pending).id) {
            $0 = .permission(request, decision: decision)
        }
        resume(session)
    }

    /// Denies a pending tool call. Claude reads the message as the tool result.
    public func deny(_ request: PermissionRequest, message: String? = nil, in session: AgentSession) {
        guard isPending(request, in: session) else { return }
        reply(to: request, in: session, ["behavior": "deny", "message": message ?? Self.denyMessage])
        if let id = request.toolUseID { deniedCalls[session.id, default: []].insert(id) }
        session.update(TranscriptBlock.permission(request, decision: .pending).id) {
            $0 = request.isQuestion ? .question(request, answers: [:]) : .permission(request, decision: .denied)
        }
        resume(session)
    }

    /// Answers an `AskUserQuestion` call. The answers map each question to the
    /// labels of the chosen options, joined with commas.
    public func answer(_ request: PermissionRequest, answers: [String: String], in session: AgentSession) {
        guard isPending(request, in: session) else { return }
        let input = request.input.setting("answers", to: .object(answers.mapValues(JSONValue.string)))
        reply(to: request, in: session, ["behavior": "allow", "updatedInput": input.any])
        session.update(TranscriptBlock.question(request, answers: nil).id) {
            $0 = .question(request, answers: answers)
        }
        resume(session)
    }

    /// Stops the turn of a session. The process ends, and the next message resumes it.
    public func stop(_ session: AgentSession) {
        guard session.isActive else { return }
        queued.removeValue(forKey: session.id)
        if session.state != .waiting, let process = processes[session.id] {
            stopReasons[session.id] = Self.stopMessage
            process.terminate()
        } else {
            endTurn(session, TurnResult(failure: Self.stopMessage), state: .idle)
            startWaitingSessions()
        }
    }

    /// Stops every turn and ends every idle process.
    public func stopAll() {
        for session in sessions where session.isActive { stop(session) }
        for session in sessions where !session.isActive {
            processes.removeValue(forKey: session.id)?.closeInput()
        }
    }

    /// Stops a session and removes it from the list and the database.
    public func delete(_ session: AgentSession) {
        stop(session)
        processes.removeValue(forKey: session.id)?.terminate()
        stopReasons.removeValue(forKey: session.id)
        saves.removeValue(forKey: session.id)?.cancel()
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

    private func beginTurn(_ session: AgentSession) {
        let lines = queued.removeValue(forKey: session.id) ?? []
        guard processes[session.id] != nil || launch(session) else { return }
        session.state = .running
        for line in lines { processes[session.id]?.write(line) }
        startTurnTimer(for: session)
        persist(session, now: true)
    }

    /// Starts a process. A process that cannot start ends the turn with a failure.
    private func launch(_ session: AgentSession) -> Bool {
        guard let executable else {
            endTurn(session, TurnResult(failure: "Piper cannot find the claude command. Choose it in Settings > Claude."), state: .failed)
            return false
        }
        var arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                         "--permission-prompt-tool", "stdio", "--permission-mode", permissionMode.rawValue]
        if let model, !model.isEmpty { arguments += ["--model", model] }
        if let resume = session.claudeSessionID { arguments += ["--resume", resume] }
        let folder = URL(fileURLWithPath: session.folder, isDirectory: true)
        let process = ClaudeProcess(executable: executable, arguments: arguments, folder: folder,
                                    usesLoginShell: usesLoginShell)
        let id = session.id
        do {
            try process.start(line: { [weak self, weak process] line in
                guard let self, let process, self.processes[id] === process else { return }
                self.receive(line, for: id)
            }, exit: { [weak self] status, errors in
                self?.exited(id, process: process, status: status, errors: errors)
            })
        } catch {
            endTurn(session, TurnResult(failure: "Cannot start claude: \(error.localizedDescription)"), state: .failed)
            return false
        }
        processes[id] = process
        return true
    }

    private func receive(_ line: String, for id: UUID) {
        guard let session = session(id) else { return }
        for event in SessionEvent.parse(line) {
            switch event {
            case .started(let claudeID):
                session.claudeSessionID = claudeID
                persist(session, now: true)
            case .text(let text):
                session.append(.assistant(id: UUID().uuidString, text: text))
                persist(session)
            case .toolCall(var call):
                let folder = URL(fileURLWithPath: session.folder, isDirectory: true)
                call.path = call.path.flatMap { SessionEvent.relativePath($0, in: folder) }
                session.append(.toolCall(call))
                persist(session)
            case .toolResult(let toolUseID, let isError, let preview):
                session.update(toolUseID) { block in
                    guard case .toolCall(var call) = block else { return }
                    call.isFinished = true
                    call.isError = isError
                    call.resultPreview = preview
                    block = .toolCall(call)
                }
                persist(session)
            case .permission(let request):
                ask(request, in: session)
            case .turnEnded(var result, let denials):
                let denied = deniedCalls.removeValue(forKey: id) ?? []
                let refused = denials.filter { $0.toolUseID.map { !denied.contains($0) } ?? true }
                if result.failure == nil { result.failure = SessionEvent.failure(for: refused) }
                endTurn(session, result, state: result.failure == nil ? .idle : .failed)
                if queued[id]?.isEmpty == false { session.state = .waiting }
                startWaitingSessions()
            }
        }
    }

    /// Shows a card, or answers at once when an Always rule from this launch covers the call.
    private func ask(_ request: PermissionRequest, in session: AgentSession) {
        if !request.isQuestion, let rule = PermissionRule.rule(toolName: request.toolName, input: request.input),
           allowRules[session.folder]?.contains(rule) == true {
            reply(to: request, in: session, ["behavior": "allow", "updatedInput": request.input.any])
            return
        }
        session.append(request.isQuestion ? .question(request, answers: nil) : .permission(request, decision: .pending))
        session.state = .needsYou
        session.unread = true
        turnTimers.removeValue(forKey: session.id)?.cancel()
        persist(session, now: true)
    }

    private func isPending(_ request: PermissionRequest, in session: AgentSession) -> Bool {
        pendingRequests(in: session).contains { $0.requestID == request.requestID }
    }

    /// The permission and question cards that wait for the reader.
    private func pendingRequests(in session: AgentSession) -> [PermissionRequest] {
        session.blocks.compactMap {
            switch $0 {
            case .permission(let request, decision: .pending), .question(let request, answers: nil): return request
            default: return nil
            }
        }
    }

    private func reply(to request: PermissionRequest, in session: AgentSession, _ response: [String: Any]) {
        let object: [String: Any] = ["type": "control_response",
                                     "response": ["subtype": "success", "request_id": request.requestID,
                                                  "response": response]]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
        processes[session.id]?.write(String(decoding: data, as: UTF8.self))
    }

    /// Goes back to running after the last card of a turn has an answer.
    private func resume(_ session: AgentSession) {
        if session.state == .needsYou, session.pendingRequest == nil {
            session.state = .running
            startTurnTimer(for: session)
        }
        persist(session, now: true)
    }

    private func exited(_ id: UUID, process: ClaudeProcess, status: Int32, errors: String) {
        guard processes[id] === process else { return }
        processes.removeValue(forKey: id)
        let reason = stopReasons.removeValue(forKey: id)
        guard let session = session(id), session.isActive else { return }
        queued.removeValue(forKey: id)
        let detail = errors.trimmingCharacters(in: .whitespacesAndNewlines)
        let failure = reason ?? (detail.isEmpty ? "claude exited with status \(status) and no result." : detail)
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
            guard !Task.isCancelled, let self, let process = self.processes[id] else { return }
            self.stopReasons[id] = "Stopped after "
                + Duration.seconds(limit).formatted(.units(allowed: [.minutes, .seconds], width: .wide)) + "."
            process.terminate()
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

    /// The text of a message with its context paths.
    nonisolated static func messageBody(_ text: String, context: [String]) -> String {
        guard !context.isEmpty else { return text }
        return text + (SlashCommand(text) != nil
            ? " " + context.joined(separator: " ")
            : "\n\n" + context.map { "Context file: " + $0 }.joined(separator: "\n"))
    }

    /// One user message of the stream-json input.
    nonisolated static func userLine(_ text: String, context: [String]) -> String {
        let body = messageBody(text, context: context)
        let object: [String: Any] = ["type": "user",
                                     "message": ["role": "user", "content": [["type": "text", "text": body]]]]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
