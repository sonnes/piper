import Foundation
@testable import PiperCommands

/// A temporary Wiki folder and a temporary home folder, with real `.claude` trees.
///
/// The tests write real files, because the indexes read the file system and a
/// stub would test the stub.
struct CommandFixtures {
    let root: URL

    var wikiRoot: URL { root.appendingPathComponent("Wiki") }
    var homeRoot: URL { root.appendingPathComponent("Home") }

    // MARK: - Life Cycle

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiperCommandsTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: wikiRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homeRoot, withIntermediateDirectories: true)
    }

    // MARK: - Functions

    /// Writes `.claude/commands/<name>.md` in `scope`.
    func writeCommand(_ name: String, scope: CommandScope, text: String) throws {
        let folder = claudeDirectory(scope).appendingPathComponent("commands")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text.write(to: folder.appendingPathComponent(name + ".md"), atomically: true, encoding: .utf8)
    }

    /// Writes `.claude/skills/<folder>/SKILL.md` in `scope`.
    func writeSkill(folder name: String, scope: CommandScope, text: String) throws {
        let folder = claudeDirectory(scope).appendingPathComponent("skills").appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text.write(to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    func claudeDirectory(_ scope: CommandScope) -> URL {
        scope.claudeDirectory(wikiRoot: wikiRoot, homeRoot: homeRoot)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
