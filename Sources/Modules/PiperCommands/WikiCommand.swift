import Foundation

/// One slash command that Claude Code can reach from the Wiki folder.
///
/// Piper does not carry a copy. The commands live in the bundle, beside the
/// concepts they operate on, so a Wiki that adds a command gets it in the menu.
public struct WikiCommand: Identifiable, Hashable, Sendable {
    /// The file name, without `.md`.
    public let name: String
    /// The `description` key of the frontmatter.
    public let summary: String
    /// The `argument-hint` key of the frontmatter. Empty when the command takes no arguments.
    public let argumentHint: String
    /// Where the command comes from.
    public let scope: CommandScope

    public var id: String { name }
    public var takesArguments: Bool { !argumentHint.isEmpty }

    // MARK: - Life Cycle

    public init(name: String, summary: String, argumentHint: String, scope: CommandScope) {
        self.name = name
        self.summary = summary
        self.argumentHint = argumentHint
        self.scope = scope
    }
}
