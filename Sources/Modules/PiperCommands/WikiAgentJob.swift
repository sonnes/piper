import Foundation

/// One thing that `WikiAgent` can run.
///
/// Claude Code reads a command and a skill in different ways, so Piper writes a
/// different prompt for each.
public enum WikiAgentJob: Identifiable, Hashable, Sendable {
    case command(WikiCommand)
    case skill(WikiSkill)

    // MARK: - Properties

    public var name: String {
        switch self {
        case .command(let command): return command.name
        case .skill(let skill): return skill.name
        }
    }

    public var scope: CommandScope {
        switch self {
        case .command(let command): return command.scope
        case .skill(let skill): return skill.scope
        }
    }

    /// The path, under the Wiki folder, that holds this kind of extension.
    public var directoryPath: String {
        switch self {
        case .command: return ".claude/commands"
        case .skill: return ".claude/skills"
        }
    }

    public var id: String {
        switch self {
        case .command: return "command:" + name
        case .skill: return "skill:" + name
        }
    }

    // MARK: - Functions

    /// The text that Piper sends to `claude --print`.
    ///
    /// A command is a slash command. A skill takes free text, so the prompt asks
    /// for the skill by name and then gives the arguments as a sentence.
    public func prompt(arguments: String) -> String {
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .command(let command):
            let head = "/" + command.name
            return trimmed.isEmpty ? head : head + " " + trimmed
        case .skill(let skill):
            let head = "Use the \(skill.name) skill."
            return trimmed.isEmpty ? head : head + " " + trimmed
        }
    }
}
