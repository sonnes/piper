import Foundation

/// One row of the search bar.
///
/// The row carries what it means, in `target`. The caller reads the target and
/// acts. It does not parse the title again to find out what the row was.
public struct HomeSuggestion: Identifiable {
    /// The group that a row belongs to. The parser emits the groups in rank order.
    public enum Kind: String, CaseIterable, Hashable, Sendable {
        case file
        case fileText
        case action
        case fallback

        /// The heading above the group.
        public var groupTitle: String {
            switch self {
            case .file: return "Files"
            case .fileText: return "In File Text"
            case .action: return "Actions"
            case .fallback: return "No Match"
            }
        }

        /// The SF Symbol name for a row of this group.
        public var iconName: String {
            switch self {
            case .file: return "doc.text"
            case .fileText: return "text.magnifyingglass"
            case .action: return "gearshape"
            case .fallback: return "magnifyingglass"
            }
        }
    }

    /// What the caller does when the reader picks the row.
    public enum Target {
        case file(FileCandidate)
        case action(HomeAction)
        /// Search every file for this text.
        case searchEverything(String)
    }

    public let id: String
    public let title: String
    /// The second line of the row.
    public let detail: String
    public let iconName: String
    public let kind: Kind
    public let target: Target

    /// The tag a row shows at its trailing edge. Empty when the row shows none.
    public var tag: String {
        if case .action(let action) = target { return action.shortcut }
        return ""
    }

    // MARK: - Life Cycle

    public init(
        id: String,
        title: String,
        detail: String,
        kind: Kind,
        target: Target
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.iconName = kind.iconName
        self.kind = kind
        self.target = target
    }
}
