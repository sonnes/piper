import Agents
import AppKit
import SwiftUI

/// The message field of a session.
///
/// Return sends and Shift-Return inserts a new line. A `/` at the start lists
/// the commands of the session. An `@` lists the item on the screen, the files
/// of the folder, and the captures, and a choice goes with the next message.
struct SessionComposer: View {
    @Bindable var model: AppModel
    let session: AgentSession?
    let folder: String
    /// The item on the screen. It is blue while the next message takes it.
    let screen: ScreenContext?
    let screenItem: ScreenItem?
    let removeScreen: () -> Void
    let resendScreen: () -> Void
    /// Sends the text and its context. A new session takes the agent, model,
    /// and mode of the choice.
    let send: (String, [ContextItem], SessionChoice) -> Void
    let stop: () -> Void
    /// The agent, model, and mode of a session that does not exist yet.
    @Binding var choice: SessionChoice?

    @State private var newSessionText = ""
    private var text: String {
        get { session?.draft ?? newSessionText }
        nonmutating set {
            if let session { session.draft = newValue } else { newSessionText = newValue }
        }
    }
    @State private var focused = false
    @State private var completionIndex = 0
    /// The items that the reader added with `@` for the next message.
    @State private var mentions: [Mention] = []
    /// The files of a folder that the sidebar does not show.
    @State private var folderFiles: [String] = []

    private var agents: FolderAgents { model.agents }
    private var isActive: Bool { session?.isActive == true }
    private var folderName: String { URL(fileURLWithPath: folder).lastPathComponent }
    private var currentChoice: SessionChoice { choice ?? SessionChoice(agentID: agents.sessionAgentID) }
    /// Nil for an agent that the reader removed.
    private var agentName: String? { agents.agent(session?.agentID ?? currentChoice.agentID)?.name }

    /// The commands that the agent supports in this session.
    private var commands: [FolderAgents.Action] {
        guard focused, let partial = SlashCommand.partialName(text) else { return [] }
        let owner = agents.available.first { $0.path == folder }
            ?? FolderAgents.Folder(path: folder, skills: [])
        let names = session?.slashCommands ?? owner.skills.map(\.name)
        return Array(Set(names)).sorted()
            .filter { $0.lowercased().hasPrefix(partial.lowercased()) }
            .prefix(AppDefaults.Agents.completionLimit)
            .map { name in
                let skill = owner.skills.first { $0.name == name } ?? FolderSkill(name: name)
                return FolderAgents.Action(folder: owner, skill: skill)
            }
    }

    /// The choices of the `@` list for the typed text.
    private var mentionOptions: [MentionOption] {
        guard focused, let partial = SessionComposerText.partialMention(text) else { return [] }
        let files = folder == model.vault.root.path ? model.files.map(\.relativePath) : folderFiles
        return MentionOption.options(matching: partial, screen: screenItem, folder: folder, files: files,
                                     notes: model.store.notes)
    }

    private var completionCount: Int { commands.isEmpty ? mentionOptions.count : commands.count }

    /// The items that the next message takes, each once.
    private var nextContext: [ContextItem] {
        var items: [ContextItem] = []
        if let screen, screen.pending { items.append(screen.item) }
        for mention in mentions where !items.contains(mention.item) { items.append(mention.item) }
        return items
    }

    private var height: CGFloat {
        let metrics = AppDefaults.Composer.self
        return metrics.textInset.height * 2 + metrics.lineHeight * CGFloat(AppDefaults.Sessions.composerLines)
            + metrics.regionInset * 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            completions
            if screen != nil || !mentions.isEmpty { contextChips }
            HStack(alignment: .bottom, spacing: 6) {
                CaptureEditor(text: Binding(get: { text }, set: { text = $0 }), focused: $focused,
                              placeholder: agentName.map { "Ask \($0) in \(folderName)" }
                                  ?? "The agent was removed. Add it again in Settings > AI.",
                              label: agentName.map { "Message to \($0)" } ?? "Message",
                              help: "Return sends the message. Shift-Return inserts a new line.",
                              highlights: mentions.map { "@" + $0.token },
                              command: handle)
                    .frame(height: height)
                if isActive {
                    Button(action: stop) { Image(systemName: "stop.fill") }
                        .help("Stop the turn")
                        .accessibilityLabel("Stop")
                        .padding(.bottom, 8)
                } else {
                    Button(action: submit) { Image(systemName: "arrow.up") }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Send · Return")
                        .accessibilityLabel("Send")
                        .padding(.bottom, 8)
                }
            }
            .padding(.trailing, 8)
            .background(PiperTheme.card, in: RoundedRectangle(cornerRadius: PiperTheme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: PiperTheme.cardRadius).strokeBorder(PiperTheme.rule, lineWidth: 0.5))
            .background {
                RoundedRectangle(cornerRadius: PiperTheme.cardRadius + 3.5)
                    .fill(focused ? PiperTheme.focusRing : .clear)
                    .padding(-3.5)
            }
            HStack(spacing: 6) {
                AgentControls(agents: agents, session: session,
                              choice: Binding(get: { currentChoice }, set: { choice = $0 }),
                              openSettings: { model.openSettings?() })
                Spacer(minLength: 4)
                Text(completionCount > 0 ? (commands.isEmpty ? "Tab adds · ↑↓ choose" : "Tab completes · ↑↓ choose")
                                         : "/ commands · @ adds")
                    .font(PiperTheme.ui(.caption))
                    .foregroundStyle(PiperTheme.faint)
                    .layoutPriority(-1)
            }
            .lineLimit(1)
        }
        .padding(12)
        .onChange(of: session?.id, initial: true) { _, _ in
            focused = !text.isEmpty
            mentions = []
        }
        .onChange(of: text) { _, text in
            completionIndex = 0
            mentions.removeAll { !text.contains("@" + $0.token) }
        }
        .task(id: folder) {
            guard folder != model.vault.root.path else { return }
            let folder = folder
            folderFiles = await Task.detached { FolderFileList.paths(in: folder) }.value
        }
    }

    // MARK: Parts

    @ViewBuilder private var completions: some View {
        let index = min(completionIndex, max(completionCount - 1, 0))
        if !commands.isEmpty {
            SkillCompletions(actions: commands, selected: index, label: "Commands") { choose(skill: $0) }
        } else if !mentionOptions.isEmpty {
            MentionCompletions(options: mentionOptions, selected: index) { choose(mention: $0) }
        }
    }

    private var contextChips: some View {
        HStack(spacing: 6) {
            if let screen {
                ContextChip(item: screen.item, pending: screen.pending, remove: removeScreen, resend: resendScreen)
            }
            ForEach(mentions, id: \.item) { mention in
                if mention.item != screen?.item || screen?.pending == false {
                    ContextChip(item: mention.item, pending: true) { removeMention(mention) }
                }
            }
        }
    }

    // MARK: Actions

    private func submit() {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        send(message, nextContext, currentChoice)
        text = ""
        mentions = []
    }

    private func choose(skill action: FolderAgents.Action) {
        text = "/" + action.skill.name + " "
    }

    private func choose(mention option: MentionOption) {
        text = SessionComposerText.replacingMention(in: text, with: option.token)
        if !mentions.contains(where: { $0.item == option.item }) {
            mentions.append(Mention(item: option.item, token: option.token))
        }
    }

    /// Removes a mention and its text.
    private func removeMention(_ mention: Mention) {
        mentions.removeAll { $0 == mention }
        text = text.replacingOccurrences(of: "@" + mention.token + " ", with: "")
            .replacingOccurrences(of: "@" + mention.token, with: "")
    }

    /// Removes what the reader typed for the list, so the list closes.
    private func dismissCompletions() {
        if !commands.isEmpty {
            text = ""
        } else if let at = text.lastIndex(of: "@") {
            text = String(text[..<at])
        }
    }

    /// Handles the keys of the message field. Return sends and Shift-Return
    /// adds a new line. While a list shows, the arrows, Tab, Return, and
    /// Escape act on the list.
    private func handle(_ selector: Selector) -> Bool {
        let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
        if completionCount > 0 {
            let current = min(completionIndex, completionCount - 1)
            switch selector {
            case #selector(NSResponder.moveDown(_:)):
                completionIndex = min(current + 1, completionCount - 1)
                return true
            case #selector(NSResponder.moveUp(_:)):
                completionIndex = max(current - 1, 0)
                return true
            case #selector(NSResponder.insertTab(_:)) where !shift,
                 #selector(NSResponder.insertNewline(_:)) where !shift:
                if !commands.isEmpty { choose(skill: commands[current]) } else { choose(mention: mentionOptions[current]) }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                dismissCompletions()
                return true
            default:
                break
            }
        }
        guard selector == #selector(NSResponder.insertNewline(_:)), !shift else { return false }
        submit()
        return true
    }
}
