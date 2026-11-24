import AppKit
import Agents
import Observation
import PiperCore

/// The agents that Piper runs, their settings, and the runner of every session.
///
/// Each setting is kept in the preferences. The settings of Claude Code also go
/// into its agent in the runner, which fills them in for a session that has none of its own.
@MainActor @Observable
final class AgentSettings {

    // MARK: - Properties

    let runner: SessionRunner
    @ObservationIgnored private let messages: Messages
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let open: (PaperItem) -> Void

    /// The `claude` executable that the reader chose. Nil means Piper looks for it.
    var claudePath: String? {
        didSet {
            preferences.set(claudePath, forKey: AppDefaults.Key.claudePath)
            executable = Self.executable(chosen: claudePath)
            refreshHealth()
        }
    }
    /// The `claude` executable that Claude Code sessions run. Nil when Piper finds none.
    var executable: URL? {
        didSet { updateClaudeCode() }
    }
    /// The model of a Claude Code session that has none of its own. An empty
    /// string leaves the choice to Claude Code.
    var model: String {
        didSet {
            preferences.set(model, forKey: AppDefaults.Key.claudeModel)
            updateClaudeCode()
        }
    }
    /// The mode of a Claude Code session that has none of its own.
    var permissionMode: ClaudeCodeConnection.PermissionMode {
        didSet {
            preferences.set(permissionMode.rawValue, forKey: AppDefaults.Key.claudePermissionMode)
            updateClaudeCode()
        }
    }
    /// The agents that speak ACP, which the reader added in Settings.
    var acpAgents: [AgentDefinition] { runner.agents.filter { $0.kind == .acp } }
    /// True when the stored agent list did not decode. Piper then keeps the
    /// stored list as it is, and an added agent lasts until Piper quits.
    @ObservationIgnored private var keepsStoredAgents = false
    /// The agent of a new session in the session pane.
    var sessionAgentID: String {
        didSet { preferences.set(sessionAgentID, forKey: AppDefaults.Key.sessionAgent) }
    }
    /// The agent that answers margin questions in the reader. `setMarginAgent` changes it.
    private(set) var marginAgentID: String {
        didSet { preferences.set(marginAgentID, forKey: AppDefaults.Key.marginAgent) }
    }
    /// The model of a margin answer. An empty string leaves the choice to the agent.
    var marginModel: String {
        didSet { preferences.set(marginModel, forKey: AppDefaults.Key.marginModel) }
    }
    /// The last health check of each agent, by id.
    private(set) var health: [String: AgentStatus] = [:]

    /// Claude Code, then the agents that the reader added.
    var allAgents: [AgentDefinition] { runner.agents }

    var claudeCode: AgentDefinition {
        ClaudeCodeConnection.agent(executable: executable, model: model, mode: permissionMode)
    }

    // MARK: - Initialization

    /// - Parameters:
    ///   - storage: The store of the sessions. Nil keeps them only until Piper quits.
    ///   - open: Opens a paper. A new draft opens the paper of its session.
    init(storage: SessionStorage?, messages: Messages, preferences: UserDefaults = .standard,
         open: @escaping (PaperItem) -> Void) {
        self.messages = messages
        self.open = open
        self.preferences = preferences
        let claudePath = preferences.string(forKey: AppDefaults.Key.claudePath)
        self.claudePath = claudePath
        executable = Self.executable(chosen: claudePath)
        model = preferences.string(forKey: AppDefaults.Key.claudeModel) ?? ClaudeCodeConnection.defaultModel
        permissionMode = preferences.string(forKey: AppDefaults.Key.claudePermissionMode)
            .flatMap(ClaudeCodeConnection.PermissionMode.init(rawValue:)) ?? .auto
        sessionAgentID = preferences.string(forKey: AppDefaults.Key.sessionAgent) ?? AgentDefinition.claudeCodeID
        marginAgentID = preferences.string(forKey: AppDefaults.Key.marginAgent) ?? AgentDefinition.claudeCodeID
        marginModel = preferences.string(forKey: AppDefaults.Key.marginModel) ?? ClaudeCodeConnection.defaultMarginModel
        runner = SessionRunner(storage: storage) { [weak messages] error in messages?.report(error) }
        var acpAgents: [AgentDefinition] = []
        if let data = preferences.data(forKey: AppDefaults.Key.acpAgents) {
            do {
                acpAgents = try JSONDecoder().decode([AgentDefinition].self, from: data)
            } catch {
                keepsStoredAgents = true
                messages.report(PiperError("Piper cannot read the stored list of agents, so it does not change it. \(error.localizedDescription)"))
            }
        }
        runner.agents = [claudeCode] + acpAgents
    }

    // MARK: - Agents

    /// The agent with an id. Nil for an agent that the reader removed.
    func agent(_ id: String) -> AgentDefinition? { allAgents.first { $0.id == id } }

    /// The kind of the agent with an id. A removed agent counts as an ACP agent.
    func kind(of id: String) -> AgentDefinition.Kind { agent(id)?.kind ?? .acp }

    /// The agents that can answer in the margin: Claude Code, and each ACP
    /// agent that is not known to lack a read-only mode.
    var marginAgents: [AgentDefinition] { allAgents.filter { canAnswerInMargin($0.id) } }

    /// The agent and the model of the next margin answer. A margin agent that
    /// cannot answer there gives way to Claude Code with its margin model.
    var marginChoice: AgentConfig {
        guard canAnswerInMargin(marginAgentID) else {
            return AgentConfig(agentID: AgentDefinition.claudeCodeID, model: ClaudeCodeConnection.defaultMarginModel)
        }
        return AgentConfig(agentID: marginAgentID, model: marginModel.isEmpty ? nil : marginModel)
    }

    /// Changes the margin agent. Claude Code starts with its margin model, and
    /// another agent with its own default model.
    func setMarginAgent(_ id: String) {
        marginAgentID = id
        marginModel = kind(of: id) == .claudeCode ? ClaudeCodeConnection.defaultMarginModel : ""
    }

    func canAnswerInMargin(_ id: String) -> Bool {
        agent(id) != nil && !runner.agentsWithoutReadOnlyMode.contains(id)
    }

    func addAgent(name: String, command: String, arguments: [String]) {
        let agent = AgentDefinition(name: name, command: command, arguments: arguments)
        setAgents(acpAgents + [agent])
        checkHealth(of: agent)
    }

    func removeAgent(_ agent: AgentDefinition) {
        setAgents(acpAgents.filter { $0.id != agent.id })
        health.removeValue(forKey: agent.id)
        if sessionAgentID == agent.id { sessionAgentID = AgentDefinition.claudeCodeID }
        if marginAgentID == agent.id { setMarginAgent(AgentDefinition.claudeCodeID) }
    }

    /// Checks every agent again, for Settings.
    func refreshHealth() {
        allAgents.forEach(checkHealth)
    }

    // MARK: - Sessions

    /// Makes a session for the session pane, with the chosen agent, model, and mode.
    /// A note ties the session to that note, so the session card shows it
    /// again when the note is open.
    func newSession(in folder: String, noteID: UUID? = nil, agentID: String? = nil, model: String? = nil, mode: String? = nil) -> AgentSession {
        let session = runner.newSession(in: folder, noteID: noteID, agentID: agentID ?? sessionAgentID)
        if let model { runner.setModel(model, for: session) }
        if let mode { runner.setMode(mode, for: session) }
        return session
    }

    /// Makes the hidden session that answers the margin questions of a capture,
    /// with `marginChoice`. A margin agent that cannot answer there changes back to Claude Code.
    func newMarginSession(in folder: String, noteID: UUID) -> AgentSession {
        let choice = marginChoice
        if choice.agentID != marginAgentID { setMarginAgent(choice.agentID) }
        let session = runner.newSession(in: folder, noteID: noteID, agentID: choice.agentID, purpose: .margin)
        if let model = choice.model { runner.setModel(model, for: session) }
        return session
    }

    /// Makes a session with a text in its message field, and shows it. The
    /// reader edits the text and sends it. A skill command runs in Claude
    /// Code, because the skills are Claude Code skills. Any other draft uses
    /// the agent of a new session.
    @discardableResult
    func openDraft(text: String, folder: String, noteID: UUID? = nil, command: SlashCommand? = nil) -> AgentSession {
        let session = command == nil
            ? newSession(in: folder, noteID: noteID)
            : runner.newSession(in: folder, noteID: noteID, command: command)
        session.draft = text
        open(.session(session.id))
        return session
    }

    // MARK: - Executable

    /// The chosen executable, or the first `claude` in the usual install places.
    static func executable(chosen: String?, home: String = NSHomeDirectory(),
                           isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> URL? {
        if let chosen, !chosen.isEmpty { return URL(fileURLWithPath: chosen) }
        let candidates = [
            home + "/.local/bin/claude",
            home + "/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ]
        return candidates.first(where: isExecutable).map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Private

    private func updateClaudeCode() {
        runner.agents = [claudeCode] + acpAgents
    }

    private func setAgents(_ agents: [AgentDefinition]) {
        runner.agents = [claudeCode] + agents
        guard !keepsStoredAgents else { return }
        do {
            preferences.set(try JSONEncoder().encode(agents), forKey: AppDefaults.Key.acpAgents)
        } catch { messages.report(error) }
    }

    private func checkHealth(of agent: AgentDefinition) {
        health[agent.id] = .checking
        let executable = executable
        Task {
            switch agent.kind {
            case .claudeCode: health[agent.id] = await AgentProbe.claudeCode(executable: executable)
            case .acp: health[agent.id] = await AgentProbe.acp(agent)
            }
        }
    }
}
