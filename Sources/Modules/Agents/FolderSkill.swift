import Foundation
import PiperCore

/// One skill that a folder offers in `.claude/skills/<name>/SKILL.md`.
///
/// Piper reads the frontmatter of each file and runs the skill with
/// `claude -p "/<name> <arguments>"` in that folder. Piper holds no logic of its
/// own for any skill.
public struct FolderSkill: Hashable, Sendable {

    // MARK: - Properties

    public let name: String
    /// The `description` key of the frontmatter.
    public let description: String
    /// The `argument-hint` key of the frontmatter, for example `<url> [note]`.
    public let argumentHint: String?

    /// The first sentence of the description, for a menu or a list row.
    public var summary: String {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let end = text.range(of: ". ") else { return text }
        return String(text[..<end.lowerBound])
    }

    // MARK: - Initialization

    public init(name: String, description: String = "", argumentHint: String? = nil) {
        self.name = name
        self.description = description
        self.argumentHint = argumentHint
    }

    // MARK: - Loading

    /// Reads the skills of a folder, sorted by name.
    ///
    /// A folder without `.claude/skills` returns an empty list. A skill with
    /// `user-invocable: false` or a name that is not a slash command is skipped.
    public static func load(from folder: URL) -> [FolderSkill] {
        let directory = folder.appendingPathComponent(".claude/skills", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        let skills = entries.compactMap { entry -> FolderSkill? in
            let file = directory.appendingPathComponent(entry).appendingPathComponent("SKILL.md")
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            let frontmatter = Frontmatter.parse(text)
            if frontmatter.metadata["user-invocable"] as? Bool == false { return nil }
            let name = frontmatter.string("name") ?? entry
            guard SlashCommand.isName(name) else { return nil }
            return FolderSkill(name: name,
                               description: frontmatter.string("description") ?? "",
                               argumentHint: frontmatter.string("argument-hint"))
        }
        return skills.sorted { $0.name < $1.name }
    }

    /// The skill that a note runs when the reader chose none.
    ///
    /// A stored choice wins when the folder still has that skill. Otherwise a
    /// link runs `capture` and text runs `new`, when the folder has them.
    public static func preferred(in skills: [FolderSkill], forLink: Bool, stored: String?) -> FolderSkill? {
        if let stored, let skill = skills.first(where: { $0.name == stored }) { return skill }
        let name = forLink ? "capture" : "new"
        return skills.first { $0.name == name }
    }
}
