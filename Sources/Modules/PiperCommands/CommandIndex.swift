import Foundation
import PiperCore

/// Finds every command that Claude Code can reach from the Wiki folder.
///
/// The scan reads the frontmatter of each file and no more. A missing `.claude`
/// directory is the normal state of a new Wiki folder, so it gives an empty
/// list instead of an error.
public enum CommandIndex {
    // MARK: - Functions

    /// Returns the commands of both scopes, deduplicated by name and sorted by name.
    ///
    /// A Wiki command and a personal command with one name collide. The Wiki one
    /// wins, which is the order that Claude Code uses.
    public static func all(
        wikiRoot: URL,
        homeRoot: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [WikiCommand] {
        var byName: [String: WikiCommand] = [:]
        // The Wiki scope comes last, so it replaces a personal command of the same name.
        for scope in [CommandScope.personal, .wiki] {
            let directory = scope.claudeDirectory(wikiRoot: wikiRoot, homeRoot: homeRoot)
            for command in commands(inClaudeDirectory: directory, scope: scope) {
                byName[command.name] = command
            }
        }
        return byName.values.sorted { $0.name < $1.name }
    }

    /// Returns the commands of one `.claude` directory.
    static func commands(inClaudeDirectory directory: URL, scope: CommandScope) -> [WikiCommand] {
        // A reader can symlink `.claude/commands` at a dotfiles folder. The URL
        // form of `contentsOfDirectory` fails with ENOTDIR on a symlink, so
        // resolve the link first. This is a configuration folder, not vault
        // content, so following the link is correct here.
        let folder = directory.appendingPathComponent("commands").resolvingSymlinksInPath()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )) ?? []
        return files.filter { $0.pathExtension == "md" }.compactMap { url in
            guard let frontmatter = FrontmatterReader.read(url) else { return nil }
            return WikiCommand(
                name: url.deletingPathExtension().lastPathComponent,
                summary: frontmatter.string("description") ?? "",
                argumentHint: frontmatter.string("argument-hint") ?? "",
                scope: scope
            )
        }
    }
}
