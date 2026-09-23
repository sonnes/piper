import AppKit
import Agents
import SwiftUI

// MARK: Status

/// The state of a session as a small capsule.
struct SessionStateChip: View {
    let session: AgentSession

    static func title(_ state: AgentSession.State) -> String {
        switch state {
        case .waiting: return "Waiting"
        case .running: return "Running"
        case .needsYou: return "Needs you"
        case .idle: return "Done"
        case .failed: return "Failed"
        }
    }

    static func color(_ state: AgentSession.State) -> Color {
        switch state {
        case .waiting: return PiperTheme.secondary
        case .running: return PiperTheme.accent
        case .needsYou: return PiperTheme.warning
        case .idle: return PiperTheme.success
        case .failed: return PiperTheme.danger
        }
    }

    var body: some View {
        let color = Self.color(session.state)
        HStack(spacing: 4) {
            switch session.state {
            case .running: ProgressView().controlSize(.mini)
            case .needsYou: Image(systemName: "hand.raised").font(.system(size: 9, weight: .bold))
            case .idle: Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
            case .failed: Image(systemName: "exclamationmark").font(.system(size: 9, weight: .bold))
            case .waiting: Image(systemName: "clock").font(.system(size: 9, weight: .semibold))
            }
            Text(Self.title(session.state))
        }
        .font(PiperTheme.ui(11, weight: .medium))
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
        .accessibilityLabel("\(SessionStateChip.title(session.state)): \(help)")
    }
}

/// The line under a note that names the folder and what the session did.
struct RunLine: View {
    let session: AgentSession

    private var name: String { session.command.map { "/" + $0.name } ?? session.title }

    private var detail: String {
        switch session.state {
        case .waiting, .running: return name + (session.lastStep.map { " · " + $0 } ?? "")
        case .needsYou: return name + " · waits for your answer"
        case .idle: return session.primaryFile ?? name
        case .failed: return session.failure?.components(separatedBy: .newlines).first ?? name
        }
    }

    var body: some View {
        Text(session.folderName + " · " + detail)
            .font(PiperTheme.ui(12))
            .foregroundStyle(session.state == .failed ? PiperTheme.danger : PiperTheme.secondary)
            .lineLimit(1).truncationMode(.middle)
    }
}

// MARK: Sending

/// The folders and their skills, as menu items. Each item runs one skill.
struct SendMenuItems: View {
    let agents: FolderAgents
    let send: (FolderAgents.Action) -> Void

    var body: some View {
        ForEach(agents.folders) { folder in
            Section(folder.name) {
                ForEach(folder.skills, id: \.name) { skill in
                    Button {
                        send(FolderAgents.Action(folder: folder, skill: skill))
                    } label: {
                        Text("/" + skill.name)
                        if !skill.summary.isEmpty { Text(skill.summary) }
                    }
                }
            }
        }
        if agents.folders.isEmpty {
            Text("No folder has Claude skills")
        }
    }
}

/// A button that sends with the default action, with a menu of every skill.
struct SendButton: View {
    let agents: FolderAgents
    let title: String
    let sendDefault: () -> Void
    let send: (FolderAgents.Action) -> Void

    var body: some View {
        Menu {
            SendMenuItems(agents: agents, send: send)
        } label: {
            Text(title)
        } primaryAction: {
            sendDefault()
        }
        .menuStyle(.borderedButton)
        .controlSize(.regular)
        .fixedSize()
        .help("Send with the default skill. Open the menu to choose another skill.")
    }
}

extension FolderAgents {
    /// "Send to Wiki" for the default folder.
    var sendTitle: String { defaultFolder.map { "Send to " + $0.name } ?? "Send" }
}

// MARK: Composer

/// The skills that match the command the reader is typing.
struct SkillCompletions: View {
    let actions: [FolderAgents.Action]
    let selected: Int
    var label = "Skills"
    let choose: (FolderAgents.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                if index == 0 || actions[index - 1].folder != action.folder {
                    Text(action.folder.name.uppercased())
                        .font(PiperTheme.ui(10.5, weight: .semibold)).tracking(0.4)
                        .foregroundStyle(PiperTheme.faint)
                        .padding(.horizontal, 8).padding(.top, index == 0 ? 4 : 8).padding(.bottom, 3)
                }
                row(action, active: index == selected)
            }
        }
        .padding(6)
        .background(PiperTheme.card, in: RoundedRectangle(cornerRadius: PiperTheme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: PiperTheme.cardRadius).strokeBorder(PiperTheme.rule, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func row(_ action: FolderAgents.Action, active: Bool) -> some View {
        Button { choose(action) } label: {
            HStack(spacing: 8) {
                Text("/" + action.skill.name)
                    .font(Font(PiperTheme.manuscript(size: 12.5)))
                    .fixedSize()
                Text(action.skill.summary)
                    .font(PiperTheme.ui(12))
                    .foregroundStyle(active ? Color.white.opacity(0.85) : PiperTheme.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let hint = action.skill.argumentHint {
                    Text(hint)
                        .font(Font(PiperTheme.manuscript(size: 11)))
                        .foregroundStyle(active ? Color.white.opacity(0.85) : PiperTheme.faint)
                        .lineLimit(1).fixedSize()
                }
            }
            .foregroundStyle(active ? Color.white : PiperTheme.ink)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(active ? PiperTheme.accent : .clear, in: RoundedRectangle(cornerRadius: PiperTheme.radius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
