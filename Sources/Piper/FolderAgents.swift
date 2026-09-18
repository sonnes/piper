import AppKit
import Agents
import Captures
import Observation
import PiperCore

/// The sidebar folders that offer Claude skills, and every action that sends a
/// note to one of them.
///
/// A folder takes part when it has at least one skill in `.claude/skills` and
/// the reader has not turned it off. The folder used last is the default, so a
/// Send button needs one click.
@MainActor @Observable
final class FolderAgents {

    /// A folder with its skills.
    struct Folder: Identifiable, Equatable {
        let path: String
        let skills: [FolderSkill]
        var id: String { path }
        var name: String { URL(fileURLWithPath: path).lastPathComponent }
    }

    /// One skill in one folder: a row of a Send menu or of the composer list.
    struct Action: Identifiable, Equatable {
        let folder: Folder
        let skill: FolderSkill
        var id: String { folder.path + "\n" + skill.name }
    }

    // MARK: - Properties

    /// The stored value that means "run nothing by default".
    static let noSkill = "-"

    let runner: SessionRunner
    /// Every sidebar folder with skills, including the folders that are off.
    private(set) var available: [Folder] = []
    @ObservationIgnored private let store: CaptureStore
    @ObservationIgnored private let preferences: UserDefaults

    private(set) var disabledPaths: Set<String> {
        didSet { preferences.set(disabledPaths.sorted(), forKey: AppDefaults.Key.agentDisabledFolders) }
    }
    private(set) var lastFolderPath: String? {
        didSet { preferences.set(lastFolderPath, forKey: AppDefaults.Key.agentLastFolder) }
    }
    /// The chosen skill for links and for text, keyed by `link|path` and `text|path`.
    private var defaultSkills: [String: String] {
        didSet { preferences.set(defaultSkills, forKey: AppDefaults.Key.agentDefaultSkills) }
    }
    /// The `claude` executable that the reader chose. Nil means Piper looks for it.
    var claudePath: String? {
        didSet {
            preferences.set(claudePath, forKey: AppDefaults.Key.claudePath)
            runner.executable = Self.executable(chosen: claudePath)
        }
    }
    /// The value of `--model`. An empty string leaves the choice to Claude Code.
    var model: String {
        didSet {
            preferences.set(model, forKey: AppDefaults.Key.claudeModel)
            runner.model = model
        }
    }
    var permissionMode: PermissionMode {
        didSet {
            preferences.set(permissionMode.rawValue, forKey: AppDefaults.Key.claudePermissionMode)
            runner.permissionMode = permissionMode
        }
    }

    /// The folders that take part.
    var folders: [Folder] { available.filter { !disabledPaths.contains($0.path) } }

    /// The folder that a Send button uses.
    var defaultFolder: Folder? { folders.first { $0.path == lastFolderPath } ?? folders.first }

    // MARK: - Initialization

    init(store: CaptureStore, preferences: UserDefaults = .standard) {
        self.store = store
        self.preferences = preferences
        disabledPaths = Set(preferences.stringArray(forKey: AppDefaults.Key.agentDisabledFolders) ?? [])
        lastFolderPath = preferences.string(forKey: AppDefaults.Key.agentLastFolder)
        defaultSkills = preferences.dictionary(forKey: AppDefaults.Key.agentDefaultSkills) as? [String: String] ?? [:]
        claudePath = preferences.string(forKey: AppDefaults.Key.claudePath)
        permissionMode = preferences.string(forKey: AppDefaults.Key.claudePermissionMode)
            .flatMap(PermissionMode.init(rawValue:)) ?? .auto
        model = preferences.string(forKey: AppDefaults.Key.claudeModel) ?? AppDefaults.Agents.model
        runner = SessionRunner(database: store.database) { [weak store] error in store?.report(error) }
        runner.executable = Self.executable(chosen: claudePath)
        runner.permissionMode = permissionMode
        runner.model = model
        runner.turnTimeout = AppDefaults.Agents.timeout
        runner.idleTimeout = AppDefaults.Sessions.idleTimeout
        runner.concurrency = AppDefaults.Agents.concurrency
    }

    // MARK: - Folders

    /// Reads the skills of each folder again. A skill file is small, so this is cheap.
    func refresh(paths: [String]) {
        let folders = paths.map { path -> Folder in
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
            return Folder(path: url.path, skills: FolderSkill.load(from: url))
        }
        let updated = folders.filter { !$0.skills.isEmpty }
        if updated != available { available = updated }
    }

    func isEnabled(_ folder: Folder) -> Bool { !disabledPaths.contains(folder.path) }

    func setEnabled(_ enabled: Bool, for folder: Folder) {
        if enabled { disabledPaths.remove(folder.path) } else { disabledPaths.insert(folder.path) }
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

    /// The folder and skill that a typed command names. The default folder wins
    /// when two folders have the same skill.
    func action(for command: SlashCommand) -> Action? {
        for folder in orderedFolders {
            if let skill = folder.skills.first(where: { $0.name == command.name }) {
                return Action(folder: folder, skill: skill)
            }
        }
        return nil
    }

    // MARK: - Sending

    /// Runs a skill on a note. Without an action, the note runs its default action.
    @discardableResult
    func send(_ note: Note, action: Action? = nil) -> AgentSession? {
        guard let action = action ?? defaultAction(for: note.text) else {
            store.report(PiperError("No folder has a skill for this note. Choose one in Settings > Claude."))
            return nil
        }
        let command = SlashCommand(name: action.skill.name, arguments: note.text)
        return start(command, in: action.folder, noteID: note.id)
    }

    /// Sends every selected note with its default action.
    @discardableResult
    func sendSelection(action: Action? = nil) -> Int {
        let notes = store.selectedNotes
        return notes.compactMap { send($0, action: action) }.count
    }

    /// Saves a clipboard text to Inbox, then sends the new note.
    @discardableResult
    func send(_ entry: ClipboardEntry, from clipboard: ClipboardInbox, action: Action? = nil) -> AgentSession? {
        guard clipboard.save(entry.id), let note = store.notes.last(where: { $0.text == entry.text }) else { return nil }
        return send(note, action: action)
    }

    /// Saves the text on the pasteboard to Inbox, then sends the new note.
    @discardableResult
    func sendPasteboard(_ pasteboard: NSPasteboard = .general) -> AgentSession? {
        guard defaultFolder != nil else {
            store.status = "No folder in the sidebar has Claude skills"
            return nil
        }
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            store.status = "The clipboard has no text"
            return nil
        }
        if let note = store.notes.last(where: { $0.text == text }) {
            if let session = latestSession(for: note), session.state != .failed {
                store.status = "Already sent to \(session.folderName)"
                return nil
            }
            return send(note)
        }
        guard store.add(text, source: "Clipboard", to: "Inbox", interpretSection: false),
              let note = store.notes.last else { return nil }
        return send(note)
    }

    /// Runs a command from the composer. The arguments become a note in the
    /// active section, so the run has a row. A chosen action picks the folder.
    /// Returns nil when no folder has the skill.
    @discardableResult
    func run(_ command: SlashCommand, action chosen: Action? = nil) -> AgentSession? {
        let chosen = chosen.flatMap { $0.skill.name == command.name && folders.contains($0.folder) ? $0 : nil }
        guard let action = chosen ?? action(for: command) else { return nil }
        let text = command.arguments.isEmpty ? command.prompt : command.arguments
        guard store.add(text, to: store.activeSection, interpretSection: false),
              let note = store.notes.last else { return nil }
        return start(command, in: action.folder, noteID: note.id)
    }

    func latestSession(for note: Note) -> AgentSession? { runner.latestSession(for: note.id) }

    // MARK: - Executable

    /// The chosen executable, or the first `claude` in the usual install places.
    static func executable(chosen: String?, home: String = NSHomeDirectory(),
                           isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> URL? {
        if let chosen, !chosen.isEmpty { return URL(fileURLWithPath: chosen) }
        let candidates = [
            home + "/.local/bin/claude",
            home + "/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ]
        return candidates.first(where: isExecutable).map { URL(fileURLWithPath: $0) }
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

    private func start(_ command: SlashCommand, in folder: Folder, noteID: UUID?) -> AgentSession {
        lastFolderPath = folder.path
        let session = runner.newSession(in: folder.path, noteID: noteID, command: command)
        runner.send(command.prompt, to: session)
        store.status = "Running /\(command.name) in \(folder.name)"
        return session
    }
}
