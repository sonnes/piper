import Agents
import AppKit
import SwiftUI

/// The message field of a session.
///
/// Return sends and Shift-Return inserts a new line. A `/` at the start lists
/// the skills of the folder, and an `@` lists the files of the folder.
struct SessionComposer: View {
    @Bindable var model: AppModel
    let session: AgentSession?
    let folder: String
    /// The files that the next message names, as absolute paths.
    let context: [String]
    let removeContext: () -> Void
    let send: (String) -> Void
    let stop: () -> Void

    @State private var text = ""
    @State private var focused = false
    @State private var completionIndex = 0
    @State private var keyMonitor: Any?

    private var agents: FolderAgents { model.agents }
    private var isActive: Bool { session?.isActive == true }
    private var folderName: String { URL(fileURLWithPath: folder).lastPathComponent }

    /// The skills of the folder whose names start with the typed name.
    private var skills: [FolderAgents.Action] {
        guard focused, let partial = SlashCommand.partialName(text),
              let owner = agents.available.first(where: { $0.path == folder }) else { return [] }
        return owner.skills
            .filter { $0.name.lowercased().hasPrefix(partial.lowercased()) }
            .prefix(AppDefaults.Agents.completionLimit)
            .map { FolderAgents.Action(folder: owner, skill: $0) }
    }

    /// The files of the folder whose paths hold the typed text. Only the
    /// folder open in the sidebar has a file list.
    private var files: [String] {
        guard focused, let partial = SessionComposerText.partialMention(text),
              folder == model.vault.root.path else { return [] }
        let needle = partial.lowercased()
        return Array(model.files.map(\.relativePath)
            .filter { needle.isEmpty || $0.lowercased().contains(needle) }
            .prefix(AppDefaults.Sessions.fileCompletionLimit))
    }

    private var completionCount: Int { skills.isEmpty ? files.count : skills.count }

    private var height: CGFloat {
        let metrics = AppDefaults.Composer.self
        return metrics.textInset.height * 2 + metrics.lineHeight * CGFloat(AppDefaults.Sessions.composerLines)
            + metrics.regionInset * 2
    }

    private var modeName: String {
        switch agents.permissionMode {
        case .auto: return "Auto"
        case .acceptEdits: return "Edit Files Only"
        case .ask: return "Ask Every Time"
        case .bypassPermissions: return "Allow Every Tool"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            completions
            if !context.isEmpty { contextChips }
            HStack(alignment: .bottom, spacing: 6) {
                CaptureEditor(text: $text, focused: $focused, placeholder: "Ask Claude in \(folderName)",
                              label: "Message to Claude",
                              help: "Return sends the message. Shift-Return inserts a new line.")
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
                Text(completionCount > 0 ? "Tab completes · ↑↓ choose" : "Return sends · / skills · @ files")
                Spacer(minLength: 4)
                Text((agents.model.isEmpty ? "Default model" : agents.model.capitalized) + " · " + modeName)
                    .help("Change the model and the permissions in Settings > Claude")
            }
            .font(PiperTheme.ui(11))
            .foregroundStyle(PiperTheme.faint)
            .lineLimit(1)
        }
        .padding(12)
        .onAppear(perform: installKeyMonitor)
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
        .onChange(of: text) { _, _ in completionIndex = 0 }
    }

    // MARK: Parts

    @ViewBuilder private var completions: some View {
        let index = min(completionIndex, max(completionCount - 1, 0))
        if !skills.isEmpty {
            SkillCompletions(actions: skills, selected: index) { choose(skill: $0) }
        } else if !files.isEmpty {
            FileCompletions(paths: files, selected: index) { choose(file: $0) }
        }
    }

    private var contextChips: some View {
        HStack(spacing: 6) {
            ForEach(context, id: \.self) { path in
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                    Text(URL(fileURLWithPath: path).lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Button(action: removeContext) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove context")
                }
                .font(PiperTheme.ui(11))
                .foregroundStyle(PiperTheme.secondary)
                .padding(.horizontal, 7).frame(height: 20)
                .background(PiperTheme.panel, in: Capsule())
                .help("The next message names \(path) as context")
            }
        }
    }

    // MARK: Actions

    private func submit() {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        send(message)
        text = ""
    }

    private func choose(skill action: FolderAgents.Action) {
        text = "/" + action.skill.name + " "
    }

    private func choose(file path: String) {
        text = SessionComposerText.replacingMention(in: text, with: path)
    }

    /// Removes what the reader typed for the list, so the list closes.
    private func dismissCompletions() {
        if !skills.isEmpty {
            text = ""
        } else if let at = text.lastIndex(of: "@") {
            text = String(text[..<at])
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard focused, let window = NSApp.keyWindow, window.attachedSheet == nil,
                  let textView = window.firstResponder as? NSTextView, !textView.hasMarkedText() else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let plain = flags.isDisjoint(with: [.shift, .command, .option, .control])
            if plain, completionCount > 0 {
                let current = min(completionIndex, completionCount - 1)
                switch event.keyCode {
                case 125: completionIndex = min(current + 1, completionCount - 1); return nil
                case 126: completionIndex = max(current - 1, 0); return nil
                case 48, 36:
                    if !skills.isEmpty { choose(skill: skills[current]) } else { choose(file: files[current]) }
                    return nil
                case 53: dismissCompletions(); return nil
                default: break
                }
            }
            if event.keyCode == 36, flags.isDisjoint(with: [.shift, .option, .control, .command]) {
                submit()
                return nil
            }
            return event
        }
    }
}

/// The files that match the `@` mention the reader is typing.
struct FileCompletions: View {
    let paths: [String]
    let selected: Int
    let choose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(paths.enumerated()), id: \.element) { index, path in
                let active = index == selected
                Button { choose(path) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                        Text(path).lineLimit(1).truncationMode(.head)
                        Spacer(minLength: 0)
                    }
                    .font(PiperTheme.ui(12))
                    .foregroundStyle(active ? Color.white : PiperTheme.ink)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(active ? PiperTheme.accent : .clear, in: RoundedRectangle(cornerRadius: PiperTheme.radius))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(6)
        .background(PiperTheme.card, in: RoundedRectangle(cornerRadius: PiperTheme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: PiperTheme.cardRadius).strokeBorder(PiperTheme.rule, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Files")
    }
}
