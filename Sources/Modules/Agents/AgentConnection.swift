import Foundation

/// An agent that Piper can run: Claude Code, or a command that speaks ACP on
/// standard input and output.
public struct AgentDefinition: Codable, Equatable, Hashable, Sendable, Identifiable {
    public static let claudeCodeID = "claude-code"
    public static let claudeCode = AgentDefinition(id: claudeCodeID, name: "Claude Code", command: "claude")

    public let id: String
    public var name: String
    /// The executable, as a path or a name to find on the PATH of the login shell.
    public var command: String
    public var arguments: [String]

    public var isClaudeCode: Bool { id == Self.claudeCodeID }

    public init(id: String = UUID().uuidString, name: String, command: String, arguments: [String] = []) {
        self.id = id
        self.name = name
        self.command = command
        self.arguments = arguments
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

/// The end of one turn.
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
    /// Starts the process. `event` gets each event on the main actor. `exit`
    /// gets the exit status and the start of standard error, after the last event.
    func start(event: @escaping @MainActor (AgentEvent) -> Void,
               exit: @escaping @MainActor (Int32, String) -> Void) throws
    /// Starts a turn with a message and the paths of its context files.
    func prompt(_ text: String, context: [String])
    /// Answers a permission request. The message goes to the agent as the
    /// reason for a denial, when the agent reads one.
    func respond(to request: PermissionRequest, with option: ACP.PermissionOption, message: String?)
    /// Answers an `AskUserQuestion` call of Claude Code.
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
