import Foundation

/// An agent that Piper can run: Claude Code, or a command that speaks ACP on
/// standard input and output.
public struct AgentDefinition: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// How Piper talks to an agent.
    public enum Kind: String, Codable, Sendable {
        /// Claude Code, through its stream-json mode.
        case claudeCode
        /// A command that speaks ACP.
        case acp

        public var connectionType: AgentConnection.Type {
            switch self {
            case .claudeCode: return ClaudeCodeConnection.self
            case .acp: return StdioAgentConnection.self
            }
        }
    }

    public static let claudeCodeID = "claude-code"

    public let id: String
    public let kind: Kind
    public var name: String
    /// The executable, as a path or a name to find on the PATH of the login shell.
    public var command: String
    public var arguments: [String]
    /// The model of a session that has none of its own. Nil leaves the choice to the agent.
    public var model: String?
    /// The mode of a session that has none of its own. Nil leaves the choice to the agent.
    public var mode: String?

    private enum CodingKeys: String, CodingKey {
        case id, kind, name, command, arguments, model, mode
    }

    public init(id: String = UUID().uuidString, kind: Kind = .acp, name: String, command: String,
                arguments: [String] = [], model: String? = nil, mode: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.command = command
        self.arguments = arguments
        self.model = model
        self.mode = mode
    }

    /// An agent that an older Piper stored has no kind, and speaks ACP.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .acp
        name = try container.decode(String.self, forKey: .name)
        command = try container.decode(String.self, forKey: .command)
        arguments = try container.decode([String].self, forKey: .arguments)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
    }
}

/// The agent, the model, and the mode of a session. `SessionRunner.config`
/// fills the model and the mode that the reader left open.
public struct AgentConfig: Equatable, Sendable {
    public var agentID: String
    /// Nil leaves the choice to the agent. An empty string asks Claude Code for its own default.
    public var model: String?
    /// The id of a mode of the agent. Nil leaves the choice to the agent.
    public var mode: String?

    public init(agentID: String, model: String? = nil, mode: String? = nil) {
        self.agentID = agentID
        self.model = model
        self.mode = mode
    }
}

/// What a session asks of its agent when the process starts.
public struct SessionConfig: Equatable, Sendable {
    public var folder: URL
    /// The ACP session id to load or resume. Nil starts a new session.
    public var resumeToken: String?
    public var model: String?
    public var mode: String?
    public var purpose: AgentSession.Purpose
}

public struct TurnEnd: Equatable, Sendable {
    public var stopReason: ACP.StopReason
    /// Why the turn failed. Nil for a turn that succeeded.
    public var failure: String?
    /// The last message of the turn, when the agent gives it apart from the stream.
    public var text: String?
    public var durationMs: Int?
    public var costUSD: Double?

    public init(stopReason: ACP.StopReason = .endTurn, failure: String? = nil, text: String? = nil,
                durationMs: Int? = nil, costUSD: Double? = nil) {
        self.stopReason = stopReason
        self.failure = failure
        self.text = text
        self.durationMs = durationMs
        self.costUSD = costUSD
    }
}

/// What an agent tells the runner about its session.
public enum AgentEvent: Equatable, Sendable {
    /// The agent started, loaded, or resumed the session.
    case ready(ACP.SessionSetup)
    case update(ACP.SessionUpdate)
    /// A tool call waits for the reader.
    case permission(PermissionRequest)
    case turnEnded(TurnEnd)
    /// The agent did not change the mode. The message tells why.
    case modeRejected(String)
    /// The agent did not change the model. The message tells why.
    case modelRejected(String)
}

/// One running agent process for one Piper session.
///
/// The runner calls `prompt` right after `start`. A connection that needs a
/// handshake first keeps the prompt until the session is ready.
@MainActor
public protocol AgentConnection: AnyObject {
    /// The slash commands that the agent runs itself and that take no context items.
    nonisolated static var localCommands: Set<String> { get }
    /// True when the agent reads the message of a denial as the reason, in the
    /// same turn. Otherwise a message that answers a card goes as the next turn.
    nonisolated static var readsDenialMessage: Bool { get }
    /// True when the agent asks questions that `answer` replies to. The runner
    /// calls `answer` only for such an agent.
    nonisolated static var answersQuestions: Bool { get }
    /// True when the agent keeps an Always choice as a rule in the folder
    /// settings. Another agent keeps it itself.
    nonisolated static var keepsAlwaysAsRule: Bool { get }
    /// The models that Piper offers before the agent reports its own.
    nonisolated static var models: [ACP.ConfigOption.Value] { get }
    /// The modes that Piper offers before the agent reports its own.
    nonisolated static var modes: [ACP.Mode] { get }
    /// The model of a margin answer when the reader chose none. Empty leaves
    /// the choice to the agent.
    nonisolated static var defaultMarginModel: String { get }
    /// True when a margin session of the agent can run read-only, given what
    /// the agent offers when its session opens.
    nonisolated static func hasReadOnlyMode(_ setup: ACP.SessionSetup) -> Bool
    /// The blocks of a stored session, with the fields that an older Piper did not store.
    nonisolated static func restored(_ blocks: [TranscriptBlock], in folder: URL) -> [TranscriptBlock]

    /// Makes the connection. It throws when the agent cannot run, such as when its command is missing.
    init(agent: AgentDefinition, config: SessionConfig, usesLoginShell: Bool, report: @escaping (Error) -> Void) throws

    /// Starts the process. `event` gets each event on the main actor. `exit`
    /// gets the exit status and the start of standard error, after the last event.
    func start(event: @escaping @MainActor (AgentEvent) -> Void,
               exit: @escaping @MainActor (Int32, String) -> Void) throws
    func prompt(_ text: String, context: [ContextItem])
    /// Answers a permission request. The message goes to the agent as the
    /// reason for a denial, when the agent reads one.
    func respond(to request: PermissionRequest, with option: ACP.PermissionOption, message: String?)
    /// Answers a question card with the chosen labels of each question.
    func answer(_ request: PermissionRequest, answers: [String: String])
    /// Stops the current turn. The connection ends the turn with `cancelled`,
    /// or the process exits.
    func cancel()
    /// Changes the mode or the model. False means that the change takes a new
    /// process, so the runner closes this one.
    func apply(model: String?, mode: String?) -> Bool
    /// Ends the process after the current turn.
    func close()
    func terminate()
}
