import Foundation

/// One row of the search bar.
///
/// The row carries what it means, in `target`. The caller reads the target and
/// acts. It does not parse the title again to find out what the row was.
public struct CommandSuggestion: Identifiable {
    /// The group that a row belongs to. The parser emits the groups in rank order.
    public enum Kind: String, CaseIterable, Hashable, Sendable {
        case file
        case fileText
        case command
        case skill
        case action
        case fallback

        /// The heading above the group.
        public var groupTitle: String {
            switch self {
            case .file: return "Files"
            case .fileText: return "In File Text"
            case .command: return "Commands"
            case .skill: return "Skills"
            case .action: return "Actions"
            case .fallback: return "No Match"
            }
        }

        /// The SF Symbol name for a row of this group.
        public var iconName: String {
            switch self {
            case .file: return "doc.text"
            case .fileText: return "text.magnifyingglass"
            case .command: return "chevron.right.square"
            case .skill: return "diamond"
            case .action: return "gearshape"
            case .fallback: return "magnifyingglass"
            }
        }
    }

    /// What the caller does when the reader picks the row.
    public enum Target {
        case command(WikiCommand, arguments: String)
        case skill(WikiSkill, arguments: String)
        case file(FileCandidate)
        case action(CommandAction)
        /// Search every file for this text.
        case searchEverything(String)
    }

    public let id: String
    public let title: String
    /// The second line of the row.
    public let detail: String
    public let iconName: String
    /// Where a command or a skill comes from. `nil` for a file, an action, and the fallback.
    public let scope: CommandScope?
    public let kind: Kind
    public let target: Target

    /// The tag a row shows at its trailing edge. Empty when the row shows none.
    public var tag: String {
        if case .action(let action) = target { return action.shortcut }
        return scope?.tag ?? ""
    }

    // MARK: - Life Cycle

    public init(
        id: String,
        title: String,
        detail: String,
        kind: Kind,
        scope: CommandScope? = nil,
        target: Target
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.iconName = kind.iconName
        self.scope = scope
        self.kind = kind
        self.target = target
    }
}
