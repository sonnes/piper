import Foundation

/// One skill that Claude Code can reach from the Wiki folder.
///
/// A skill takes free text, not named arguments, so it carries no argument hint.
public struct WikiSkill: Identifiable, Hashable, Sendable {
    /// The `name` key of the frontmatter, or the folder name when that key is absent.
    public let name: String
    /// The first sentence of the `description` key.
    public let summary: String
    /// Where the skill comes from.
    public let scope: CommandScope

    public var id: String { name }

    // MARK: - Life Cycle

    public init(name: String, summary: String, scope: CommandScope) {
        self.name = name
        self.summary = summary
        self.scope = scope
    }
}
