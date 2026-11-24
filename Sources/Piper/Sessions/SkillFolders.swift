import Agents
import Captures
import Foundation
import Observation
import Vault

/// The folders of the Folders index that offer Claude skills, and the skill
/// that Send runs in each.
///
/// A folder takes part when it has at least one skill in `.claude/skills` and
/// the reader has not turned it off. The folder used last is the default, so a
/// Send button needs one click. A `VaultWatcher` on each folder reads the
/// skills again when a file below `.claude` changes.
@MainActor @Observable
final class SkillFolders {

    /// A folder with its skills.
    struct Folder: Identifiable, Equatable {
        let path: String
        let skills: [FolderSkill]
        var id: String { path }
        var name: String { URL(fileURLWithPath: path).lastPathComponent }
    }

    /// One skill in one folder: a row of a Send menu or of a completion list.
    struct Action: Identifiable, Equatable {
        let folder: Folder
        let skill: FolderSkill
        var id: String { folder.path + "\n" + skill.name }
    }

    // MARK: - Properties

    /// The stored value that means "run nothing by default".
    static let noSkill = "-"
    /// The number of skills that a completion list shows.
    static let completionLimit = 6

    /// The folders of the Folders index. `Library` sets them.
    var paths: [String] = [] {
        didSet {
            guard paths != oldValue else { return }
            watch()
            scan()
        }
    }
    /// Every folder of the Folders index with skills, including the folders that are off.
    private(set) var available: [Folder] = [] {
        didSet { foldersChanged?() }
    }
    /// Runs after `folders` changes.
    @ObservationIgnored var foldersChanged: (() -> Void)?
    @ObservationIgnored private var watchers: [VaultWatcher] = []
    @ObservationIgnored private let preferences: UserDefaults

    private(set) var disabledPaths: Set<String> {
        didSet {
            preferences.set(disabledPaths.sorted(), forKey: AppDefaults.Key.agentDisabledFolders)
            foldersChanged?()
        }
    }
    private(set) var lastFolderPath: String? {
        didSet { preferences.set(lastFolderPath, forKey: AppDefaults.Key.agentLastFolder) }
    }
    /// The chosen skill for links and for text, keyed by `link|path` and `text|path`.
    private var defaultSkills: [String: String] {
        didSet { preferences.set(defaultSkills, forKey: AppDefaults.Key.agentDefaultSkills) }
    }

    /// The folders that take part.
    var folders: [Folder] { available.filter { !disabledPaths.contains($0.path) } }

    /// The folder that a Send button uses.
    var defaultFolder: Folder? { folders.first { $0.path == lastFolderPath } ?? folders.first }

    // MARK: - Initialization

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        disabledPaths = Set(preferences.stringArray(forKey: AppDefaults.Key.agentDisabledFolders) ?? [])
        lastFolderPath = preferences.string(forKey: AppDefaults.Key.agentLastFolder)
        defaultSkills = preferences.dictionary(forKey: AppDefaults.Key.agentDefaultSkills) as? [String: String] ?? [:]
    }

    // MARK: - Folders

    func isEnabled(_ folder: Folder) -> Bool { !disabledPaths.contains(folder.path) }

    func setEnabled(_ enabled: Bool, for folder: Folder) {
        if enabled { disabledPaths.remove(folder.path) } else { disabledPaths.insert(folder.path) }
    }

    /// Makes a folder the default of the Send buttons.
    func use(_ folder: Folder) {
        lastFolderPath = folder.path
    }

    /// The skill that a link or a text note runs in a folder, or nil for none.
    func defaultSkill(forLink: Bool, in folder: Folder) -> FolderSkill? {
        let stored = defaultSkills[Self.key(forLink: forLink, folder)]
        if stored == Self.noSkill { return nil }
        return FolderSkill.preferred(in: folder.skills, forLink: forLink, stored: stored)
    }

    func setDefaultSkill(_ name: String, forLink: Bool, in folder: Folder) {
        defaultSkills[Self.key(forLink: forLink, folder)] = name
    }

    /// The action that a Send button runs for this text.
    func defaultAction(for text: String) -> Action? {
        guard let folder = defaultFolder,
              let skill = defaultSkill(forLink: Self.isLink(text), in: folder) else { return nil }
        return Action(folder: folder, skill: skill)
    }

    // MARK: - Commands

    /// The skills whose names start with `partial`. The default folder comes first.
    func completions(for partial: String) -> [Action] {
        orderedFolders.flatMap { folder in
            folder.skills
                .filter { $0.name.lowercased().hasPrefix(partial.lowercased()) }
                .map { Action(folder: folder, skill: $0) }
        }
    }

    /// The folder and skill that a typed command runs. A chosen action wins
    /// when it names the same skill in a folder that takes part. Else the
    /// default folder wins when two folders have the skill.
    func action(for command: SlashCommand, chosen: Action? = nil) -> Action? {
        if let chosen, chosen.skill.name == command.name, folders.contains(chosen.folder) { return chosen }
        for folder in orderedFolders {
            if let skill = folder.skills.first(where: { $0.name == command.name }) {
                return Action(folder: folder, skill: skill)
            }
        }
        return nil
    }

    static func isLink(_ text: String) -> Bool { CaptureLinks(text).standaloneURL != nil }

    // MARK: - Private

    private var orderedFolders: [Folder] {
        guard let first = defaultFolder else { return [] }
        return [first] + folders.filter { $0 != first }
    }

    private static func key(forLink: Bool, _ folder: Folder) -> String {
        (forLink ? "link|" : "text|") + folder.path
    }

    private func watch() {
        watchers.forEach { $0.stop() }
        watchers = paths.map { path in
            let watcher = VaultWatcher(vault: Vault(path: path), part: "/.claude") { [weak self] in self?.scan() }
            watcher.start()
            return watcher
        }
    }

    private func scan() {
        let updated = paths.map { path -> Folder in
            let root = Vault(path: path).root
            return Folder(path: root.path, skills: FolderSkill.load(from: root))
        }.filter { !$0.skills.isEmpty }
        if updated != available { available = updated }
    }
}
