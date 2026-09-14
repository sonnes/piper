import Foundation
import PiperCore

/// Finds every skill that Claude Code can reach from the Wiki folder.
///
/// A skill body runs to thousands of lines, so the scan reads a bounded prefix
/// of each `SKILL.md` and parses the frontmatter out of that.
public enum SkillIndex {
    // MARK: - Functions

    /// Returns the skills of both scopes, deduplicated by name and sorted by name.
    ///
    /// A Wiki skill and a personal skill with one name collide. The Wiki one
    /// wins, which is the order that Claude Code uses.
    public static func all(
        wikiRoot: URL,
        homeRoot: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [WikiSkill] {
        var byName: [String: WikiSkill] = [:]
        // The Wiki scope comes last, so it replaces a personal skill of the same name.
        for scope in [CommandScope.personal, .wiki] {
            let directory = scope.claudeDirectory(wikiRoot: wikiRoot, homeRoot: homeRoot)
            for skill in skills(inClaudeDirectory: directory, scope: scope) {
                byName[skill.name] = skill
            }
        }
        return byName.values.sorted { $0.name < $1.name }
    }

    /// Returns the skills of one `.claude` directory.
    static func skills(inClaudeDirectory directory: URL, scope: CommandScope) -> [WikiSkill] {
        // A reader can symlink `.claude/skills` at a dotfiles folder. The URL
        // form of `contentsOfDirectory` fails with ENOTDIR on a symlink, so
        // resolve the link first. This is a configuration folder, not vault
        // content, so following the link is correct here.
        let folder = directory.appendingPathComponent("skills").resolvingSymlinksInPath()
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        return folders.compactMap { url in
            let file = url.appendingPathComponent("SKILL.md")
            guard let frontmatter = FrontmatterReader.read(file) else { return nil }
            let declared = (frontmatter.string("name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return WikiSkill(
                name: declared.isEmpty ? url.lastPathComponent : declared,
                summary: Frontmatter.firstSentence(frontmatter.string("description") ?? ""),
                scope: scope
            )
        }
    }
}
