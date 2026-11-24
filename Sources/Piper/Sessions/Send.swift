import AppKit
import Agents
import Captures
import PiperCore

/// Every action that sends a note, a clipboard text, or a typed command to a
/// skill of a folder.
@MainActor
final class Send {

    // MARK: - Properties

    /// The error of a send that finds no skill.
    static let noSkill = PiperError("No folder has a skill for this text. Choose one in Settings > AI.")

    private let store: CaptureStore
    private let agents: AgentSettings
    private let skills: SkillFolders
    private let open: (PaperItem) -> Void

    // MARK: - Initialization

    init(store: CaptureStore, agents: AgentSettings, skills: SkillFolders, open: @escaping (PaperItem) -> Void) {
        self.store = store
        self.agents = agents
        self.skills = skills
        self.open = open
    }

    // MARK: - Sending

    /// Opens a draft for a note with the chosen skill or its default skill.
    @discardableResult
    func note(_ note: Note, action: SkillFolders.Action? = nil) throws -> AgentSession {
        guard let action = action ?? skills.defaultAction(for: note.text) else { throw Self.noSkill }
        let command = SlashCommand(name: action.skill.name, arguments: note.text)
        skills.use(action.folder)
        return agents.openDraft(text: command.prompt, folder: action.folder.path, noteID: note.id, command: command)
    }

    /// Saves clipboard text to Inbox, then opens its draft. Returns nil for
    /// a text that the clipboard history no longer holds.
    @discardableResult
    func clip(_ entry: ClipboardEntry, from clipboard: ClipboardInbox, action: SkillFolders.Action? = nil) throws -> AgentSession? {
        guard let saved = try clipboard.save(entry.id) else { return nil }
        return try note(saved, action: action)
    }

    /// Saves the pasteboard text to Inbox, then opens its draft. A note
    /// whose draft is not sent yet shows that draft again.
    @discardableResult
    func pasteboard(_ pasteboard: NSPasteboard = .general) throws -> AgentSession {
        guard skills.defaultFolder != nil else { throw Self.noSkill }
        let text = try pasteboard.text()
        if let saved = store.notes.last(where: { $0.text == text }) {
            if let session = agents.runner.latestSession(for: saved.id), session.state != .failed {
                guard session.blocks.isEmpty else { throw PiperError("Already sent to \(session.folderName)") }
                open(.session(session.id))
                return session
            }
            return try note(saved)
        }
        return try note(store.add(text, section: Note.inbox, source: Note.clipboardSource))
    }

    /// Runs a command from the composer. The arguments become a note in the
    /// active section, so the run has a row. A chosen action picks the folder.
    /// Returns nil when no folder has the skill.
    @discardableResult
    func run(_ command: SlashCommand, action chosen: SkillFolders.Action? = nil) throws -> AgentSession? {
        guard let action = skills.action(for: command, chosen: chosen) else { return nil }
        let text = command.arguments.isEmpty ? command.prompt : command.arguments
        let saved = try store.add(text, section: store.activeSection)
        skills.use(action.folder)
        let session = agents.runner.newSession(in: action.folder.path, noteID: saved.id, command: command)
        agents.runner.send(command.prompt, to: session)
        return session
    }
}

extension NSPasteboard {
    /// The text of the pasteboard. Throws when it holds no text, or only white space.
    func text() throws -> String {
        guard let text = string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PiperError("The clipboard has no text")
        }
        return text
    }
}
