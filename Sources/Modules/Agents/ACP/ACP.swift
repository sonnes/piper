import Foundation

/// The Agent Client Protocol, version 1: the part that Piper sends and reads.
/// See https://agentclientprotocol.com/protocol/overview.
///
/// Each type reads itself from a `JSONValue`. Piper skips a field that it
/// does not use, and an unknown kind reads as `other`, so a newer agent still
/// works.
public enum ACP {

    public static let protocolVersion = 1

    // MARK: - Kinds

    /// What a tool call does. Piper folds a turn and decides an approval by it.
    public enum ToolKind: String, Codable, Sendable, CaseIterable {
        case read, edit, delete, move, search, execute, think, fetch
        case switchMode = "switch_mode"
        case other

        init(json: JSONValue?) {
            self = json?.string.flatMap(ToolKind.init(rawValue:)) ?? .other
        }

        /// True for a kind that reads and changes nothing.
        public var isReadOnly: Bool {
            switch self {
            case .read, .search, .fetch, .think: return true
            default: return false
            }
        }
    }

    public enum ToolStatus: String, Codable, Sendable {
        case pending
        case inProgress = "in_progress"
        case completed
        case failed
    }

    public enum StopReason: String, Codable, Sendable {
        case endTurn = "end_turn"
        case maxTokens = "max_tokens"
        case maxTurnRequests = "max_turn_requests"
        case refusal
        case cancelled
    }

    public enum PermissionKind: String, Codable, Sendable {
        case allowOnce = "allow_once"
        case allowAlways = "allow_always"
        case rejectOnce = "reject_once"
        case rejectAlways = "reject_always"

        public var allows: Bool { self == .allowOnce || self == .allowAlways }
    }

    // MARK: - Records

    /// One choice of a permission request, in the order of the agent.
    public struct PermissionOption: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let kind: PermissionKind

        public init(id: String, name: String, kind: PermissionKind) {
            self.id = id
            self.name = name
            self.kind = kind
        }

        init?(json: JSONValue) {
            guard let id = json["optionId"]?.string, let name = json["name"]?.string,
                  let kind = json["kind"]?.string.flatMap(PermissionKind.init(rawValue:)) else { return nil }
            self.init(id: id, name: name, kind: kind)
        }
    }

    /// A mode of a session, for example Plan.
    public struct Mode: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let description: String?

        public init(id: String, name: String, description: String? = nil) {
            self.id = id
            self.name = name
            self.description = description
        }

        init?(json: JSONValue) {
            guard let id = json["id"]?.string, let name = json["name"]?.string else { return nil }
            self.init(id: id, name: name, description: json["description"]?.string)
        }

        /// The names of a mode that changes no files, the best match first. Piper
        /// compares them with the id and the name of a mode, without case,
        /// spaces, hyphens, or underscores.
        private static let readOnlyNames = ["readonly", "plan", "ask"]

        /// The mode of a margin session: a mode that changes no files, such as
        /// Read Only, Plan, or Ask. Nil when the agent offers none.
        public static func readOnly(in modes: [Mode]) -> Mode? {
            func key(_ text: String) -> String {
                text.lowercased().filter { $0.isLetter || $0.isNumber }
            }
            for name in readOnlyNames {
                if let mode = modes.first(where: { key($0.id) == name || key($0.name) == name }) { return mode }
            }
            return nil
        }
    }

    /// A select option of a session, for example the model. Piper skips the
    /// boolean options.
    public struct ConfigOption: Codable, Equatable, Sendable, Identifiable {
        public struct Value: Codable, Equatable, Sendable, Identifiable {
            public let id: String
            public let name: String

            public init(id: String, name: String) {
                self.id = id
                self.name = name
            }
        }

        public let id: String
        public let name: String
        /// `model`, `mode`, `thought_level`, or another category.
        public let category: String?
        public var currentValue: String
        public let values: [Value]

        public init(id: String, name: String, category: String?, currentValue: String, values: [Value]) {
            self.id = id
            self.name = name
            self.category = category
            self.currentValue = currentValue
            self.values = values
        }

        init?(json: JSONValue) {
            guard json["type"]?.string == "select", let id = json["id"]?.string, let name = json["name"]?.string,
                  let current = json["currentValue"]?.string else { return nil }
            // The options are a flat list, or groups that each hold a list.
            let values = json["options"]?.array.flatMap { item -> [JSONValue] in
                item["group"] != nil ? item["options"]?.array ?? [] : [item]
            }.compactMap { value -> Value? in
                guard let id = value["value"]?.string, let name = value["name"]?.string else { return nil }
                return Value(id: id, name: name)
            } ?? []
            self.init(id: id, name: name, category: json["category"]?.string, currentValue: current, values: values)
        }
    }

    /// A slash command that the agent offers.
    public struct Command: Equatable, Sendable {
        public let name: String
        public let description: String
        public let hint: String?

        public init(name: String, description: String = "", hint: String? = nil) {
            self.name = name
            self.description = description
            self.hint = hint
        }
    }

    /// The text that an edit replaces in one file.
    public struct Diff: Codable, Equatable, Sendable {
        public let path: String
        public let oldText: String?
        public let newText: String

        public init(path: String, oldText: String?, newText: String) {
            self.path = path
            self.oldText = oldText
            self.newText = newText
        }
    }

    /// A tool call, or a change to one. Only the id is sure to be present.
    public struct ToolCallUpdate: Equatable, Sendable {
        public let id: String
        /// The tool name, for example `Write`. Not every agent gives it.
        public var name: String?
        /// A line that a person reads, for example the path or the command.
        public var title: String?
        public var kind: ToolKind?
        public var status: ToolStatus?
        public var paths: [String]?
        public var diffs: [Diff]?
        /// The text content of the call, for example the start of its result.
        public var text: String?
        public var rawInput: JSONValue?

        public init(id: String, name: String? = nil, title: String? = nil, kind: ToolKind? = nil,
                    status: ToolStatus? = nil, paths: [String]? = nil, diffs: [Diff]? = nil,
                    text: String? = nil, rawInput: JSONValue? = nil) {
            self.id = id
            self.name = name
            self.title = title
            self.kind = kind
            self.status = status
            self.paths = paths
            self.diffs = diffs
            self.text = text
            self.rawInput = rawInput
        }

        init?(json: JSONValue) {
            guard let id = json["toolCallId"]?.string else { return nil }
            self.init(id: id, name: json["name"]?.string, title: json["title"]?.string,
                      kind: json["kind"].map { ToolKind(json: $0) },
                      status: json["status"]?.string.flatMap(ToolStatus.init(rawValue:)),
                      paths: json["locations"].map { $0.array.compactMap { $0["path"]?.string } },
                      rawInput: json["rawInput"])
            guard let content = json["content"]?.array else { return }
            diffs = content.compactMap { item in
                guard item["type"]?.string == "diff", let path = item["path"]?.string,
                      let new = item["newText"]?.string else { return nil }
                return Diff(path: path, oldText: item["oldText"]?.string, newText: new)
            }
            let texts = content.compactMap { item -> String? in
                item["type"]?.string == "content" ? item["content"].flatMap(ACP.text(of:)) : nil
            }
            if !texts.isEmpty { text = texts.joined(separator: "\n") }
        }
    }

    /// One step of the plan of an agent.
    public struct PlanEntry: Equatable, Sendable {
        public let content: String
        /// `pending`, `in_progress`, or `completed`.
        public let status: String
    }

    /// The setup of a session, from `session/new`, `session/load`, or `session/resume`.
    public struct SessionSetup: Equatable, Sendable {
        public let sessionID: String
        public let currentMode: String?
        public let modes: [Mode]
        public let configOptions: [ConfigOption]

        public init(sessionID: String, currentMode: String? = nil, modes: [Mode] = [], configOptions: [ConfigOption] = []) {
            self.sessionID = sessionID
            self.currentMode = currentMode
            self.modes = modes
            self.configOptions = configOptions
        }

        /// The model option of an agent that still sends the older `models`
        /// list, which `session/set_model` changes. OpenCode does this.
        public static let legacyModelOptionID = "_models"

        init(sessionID: String, json: JSONValue) {
            var options = json["configOptions"]?.array.compactMap(ConfigOption.init(json:)) ?? []
            if !options.contains(where: { $0.category == "model" }), let models = json["models"],
               let current = models["currentModelId"]?.string {
                let values = models["availableModels"]?.array.compactMap { model -> ConfigOption.Value? in
                    guard let id = model["modelId"]?.string else { return nil }
                    return ConfigOption.Value(id: id, name: model["name"]?.string ?? id)
                } ?? []
                options.append(ConfigOption(id: Self.legacyModelOptionID, name: "Model", category: "model",
                                            currentValue: current, values: values))
            }
            self.init(sessionID: sessionID,
                      currentMode: json["modes"]?["currentModeId"]?.string,
                      modes: json["modes"]?["availableModes"]?.array.compactMap(Mode.init(json:)) ?? [],
                      configOptions: options)
        }
    }

    /// What `initialize` returns about an agent.
    public struct AgentInfo: Equatable, Sendable {
        public let name: String?
        public let version: String?
        public let loadsSessions: Bool
        public let resumesSessions: Bool

        init(json: JSONValue) {
            let info = json["agentInfo"]
            name = info?["title"]?.string ?? info?["name"]?.string
            version = info?["version"]?.string
            let capabilities = json["agentCapabilities"]
            loadsSessions = capabilities?["loadSession"] == .bool(true)
            resumesSessions = capabilities?["sessionCapabilities"]?["resume"].map { $0 != .null } ?? false
        }
    }

    // MARK: - Session Updates

    /// One `session/update` notification.
    public enum SessionUpdate: Equatable, Sendable {
        /// A part of a message from the agent. Parts in a row make one message.
        case agentMessage(String)
        case agentThought(String)
        case userMessage(String)
        case toolCall(ToolCallUpdate)
        case toolCallUpdate(ToolCallUpdate)
        case plan([PlanEntry])
        case commands([Command])
        case currentMode(String)
        case configOptions([ConfigOption])
        /// The context use of the session, and its cost so far when the agent knows it.
        case usage(used: Int, size: Int, costUSD: Double?)
        case other

        init(json: JSONValue) {
            switch json["sessionUpdate"]?.string {
            case "agent_message_chunk": self = .agentMessage(json["content"].flatMap(ACP.text(of:)) ?? "")
            case "agent_thought_chunk": self = .agentThought(json["content"].flatMap(ACP.text(of:)) ?? "")
            case "user_message_chunk": self = .userMessage(json["content"].flatMap(ACP.text(of:)) ?? "")
            case "tool_call": self = ToolCallUpdate(json: json).map(SessionUpdate.toolCall) ?? .other
            case "tool_call_update": self = ToolCallUpdate(json: json).map(SessionUpdate.toolCallUpdate) ?? .other
            case "plan":
                self = .plan(json["entries"]?.array.compactMap { entry in
                    guard let content = entry["content"]?.string else { return nil }
                    return PlanEntry(content: content, status: entry["status"]?.string ?? "pending")
                } ?? [])
            case "available_commands_update":
                self = .commands(json["availableCommands"]?.array.compactMap { command in
                    guard let name = command["name"]?.string else { return nil }
                    return Command(name: name, description: command["description"]?.string ?? "",
                                   hint: command["input"]?["hint"]?.string)
                } ?? [])
            case "current_mode_update": self = json["currentModeId"]?.string.map(SessionUpdate.currentMode) ?? .other
            case "config_option_update":
                self = .configOptions(json["configOptions"]?.array.compactMap(ConfigOption.init(json:)) ?? [])
            case "usage_update":
                self = .usage(used: json["used"]?.int ?? 0, size: json["size"]?.int ?? 0,
                              costUSD: json["cost"]?["currency"]?.string == "USD" ? json["cost"]?["amount"]?.double : nil)
            default: self = .other
            }
        }
    }

    // MARK: - Content

    /// The text of a content block. Other kinds of block have none.
    static func text(of block: JSONValue) -> String? {
        switch block["type"]?.string {
        case "text": return block["text"]?.string
        case "resource_link": return block["uri"]?.string
        default: return nil
        }
    }
}
