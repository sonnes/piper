import AppKit
import Agents
import SwiftUI

// MARK: Status

/// The label, the color, and the symbol of each state, for every view that shows a state.
extension AgentSession.State {
    var label: String {
        switch self {
        case .waiting: return "Waiting"
        case .running: return "Running"
        case .needsYou: return "Needs you"
        case .idle: return "Done"
        case .failed: return "Failed"
        }
    }

    var color: Color {
        switch self {
        case .waiting: return PiperTheme.paperMuted
        case .running: return PiperTheme.brand
        case .needsYou: return PiperTheme.warning
        case .idle: return PiperTheme.success
        case .failed: return PiperTheme.danger
        }
    }

    /// The SF Symbol of the state. Nil while the agent works, because a view
    /// then shows a spinner.
    var symbol: String? {
        switch self {
        case .waiting: return "clock"
        case .running: return nil
        case .needsYou: return "hand.raised"
        case .idle: return "checkmark"
        case .failed: return "exclamationmark"
        }
    }
}

/// The state of a session as a small capsule.
struct SessionStateChip: View {
    let session: AgentSession

    var body: some View {
        let color = session.state.color
        HStack(spacing: 4) {
            if let symbol = session.state.symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            } else {
                ProgressView().controlSize(.mini)
            }
            Text(session.blocks.isEmpty ? "Draft" : session.state.label)
        }
        .font(PiperTheme.paperUI(.body, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(color.opacity(0.13), in: Capsule())
        .fixedSize()
    }
}

/// The state of the last session of a note or a page, as a button.
///
/// A finished session opens the file it wrote. Any other session opens its
/// transcript, where the reader answers a card or reads why it failed.
struct RunBadge: View {
    let session: AgentSession
    let open: () -> Void

    private var help: String {
        let name = session.command.map { "/" + $0.name } ?? "The session"
        if session.blocks.isEmpty { return "Edit the draft in " + session.folderName }
        switch session.state {
        case .waiting: return "\(name) waits for another session to finish"
        case .running: return session.lastStep ?? "\(name) is running in \(session.folderName)"
        case .needsYou: return "\(name) waits for your answer in \(session.folderName)"
        case .idle: return session.primaryFile.map { "Open \($0)" } ?? "Show the session"
        case .failed: return session.failure ?? "The session failed"
        }
    }

    var body: some View {
        Button(action: open) {
            SessionStateChip(session: session).contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(help)
        .accessibilityLabel("\(session.blocks.isEmpty ? "Draft" : session.state.label): \(help)")
    }
}

// MARK: Sending

/// The folders and their skills, as menu items. Each item runs one skill.
struct SendMenuItems: View {
    let skills: SkillFolders
    let send: (SkillFolders.Action) -> Void

    var body: some View {
        ForEach(skills.folders) { folder in
            Section(folder.name) {
                ForEach(folder.skills, id: \.name) { skill in
                    Button {
                        send(SkillFolders.Action(folder: folder, skill: skill))
                    } label: {
                        Text("/" + skill.name)
                        if !skill.summary.isEmpty { Text(skill.summary) }
                    }
                }
            }
        }
        if skills.folders.isEmpty {
            Text("No folder has Claude skills")
        }
    }
}

// MARK: Composer

/// The skills that match the command the reader is typing.
struct SkillCompletions: View {
    let actions: [SkillFolders.Action]
    let selected: Int
    var label = "Skills"
    let choose: (SkillFolders.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                if index == 0 || actions[index - 1].folder != action.folder {
                    Text(action.folder.name.uppercased())
                        .font(PiperTheme.paperUI(.body, weight: .semibold)).tracking(0.4)
                        .foregroundStyle(PiperTheme.paperFaint)
                        .padding(.horizontal, 8).padding(.top, index == 0 ? 4 : 8).padding(.bottom, 3)
                }
                row(action, active: index == selected)
            }
        }
        .modifier(CompletionListChrome())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func row(_ action: SkillFolders.Action, active: Bool) -> some View {
        Button { choose(action) } label: {
            HStack(spacing: 8) {
                Text("/" + action.skill.name)
                    .font(Font(PiperTheme.manuscript(size: 12.5)))
                    .fixedSize()
                Text(action.skill.summary)
                    .font(PiperTheme.paperUI(.body))
                    .foregroundStyle(active ? Color.white.opacity(0.85) : PiperTheme.paperMuted)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let hint = action.skill.argumentHint {
                    Text(hint)
                        .font(Font(PiperTheme.manuscript(size: 11)))
                        .foregroundStyle(active ? Color.white.opacity(0.85) : PiperTheme.paperFaint)
                        .lineLimit(1).fixedSize()
                }
            }
            .foregroundStyle(active ? Color.white : PiperTheme.paperInk)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(active ? PiperTheme.brand : .clear, in: RoundedRectangle(cornerRadius: Metrics.rowRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

extension SkillCompletions {
    enum Metrics {
        static let rowRadius: CGFloat = 6
    }
}
