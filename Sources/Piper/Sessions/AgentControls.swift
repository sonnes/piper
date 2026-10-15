import Agents
import AppKit
import SwiftUI

/// The agent, the model, and the mode of the next message.
struct SessionChoice: Equatable {
    var agentID: String
    /// Nil uses the default of the agent. An empty string asks Claude Code for its own default.
    var model: String?
    var mode: String?
}

/// The mark of an agent: the Claude sparkle, or a hexagon for an ACP agent.
struct AgentMark: View {
    let agentID: String

    var body: some View {
        if agentID == AgentDefinition.claudeCodeID {
            Image(systemName: "asterisk").foregroundStyle(PiperTheme.claude)
        } else {
            Image(systemName: "hexagon").foregroundStyle(PiperTheme.acpAgent)
        }
    }
}

/// The menus in the composer footer: the agent, the model, and the mode.
///
/// A session that has a message keeps its agent. The model and the mode can
/// change at any time. The lists come from the agent once its process starts.
/// Before that, Claude Code has its own lists and another agent shows its name only.
struct AgentControls: View {
    let agents: FolderAgents
    let session: AgentSession?
    @Binding var choice: SessionChoice
    let openSettings: () -> Void

    private typealias Metrics = AppDefaults.Sessions

    private var runner: SessionRunner { agents.runner }
    private var agentID: String { session?.agentID ?? choice.agentID }
    /// Nil for an agent that the reader removed.
    private var agent: AgentDefinition? { agents.agent(agentID) }
    private var isClaudeCode: Bool { agentID == AgentDefinition.claudeCodeID }
    private var canChangeAgent: Bool { session?.isNew ?? true }

    private var modelOption: ACP.ConfigOption? { session?.configOptions.first { $0.category == "model" } }
    private var models: [ACP.ConfigOption.Value] { modelOption?.values ?? (isClaudeCode ? ClaudeCodeConnection.models : []) }
    private var model: String? {
        if let session { return session.model ?? modelOption?.currentValue ?? (isClaudeCode ? agents.model : nil) }
        return choice.model ?? (isClaudeCode ? agents.model : nil)
    }

    private var modes: [ACP.Mode] {
        if let session, !session.modes.isEmpty { return session.modes }
        return isClaudeCode ? ClaudeCodeConnection.modes : []
    }
    private var mode: String? {
        if let session { return session.mode ?? session.currentMode ?? (isClaudeCode ? agents.permissionMode.rawValue : nil) }
        return choice.mode ?? (isClaudeCode ? agents.permissionMode.rawValue : nil)
    }

    var body: some View {
        HStack(spacing: Metrics.footerMenuSpacing) {
            agentMenu
            if !models.isEmpty { modelMenu }
            if !modes.isEmpty { modeMenu }
        }
        .font(PiperTheme.ui(Metrics.footerFontSize))
    }

    // MARK: Menus

    private var agentMenu: some View {
        Menu {
            ForEach(agents.allAgents) { agent in
                Button { setAgent(agent.id) } label: {
                    if agent.id == agentID { Label(agent.name, systemImage: "checkmark") } else { Text(agent.name) }
                }
            }
            Divider()
            Button("Add an ACP Agent…", action: openSettings)
        } label: {
            HStack(spacing: Metrics.footerAgentSpacing) {
                if let agent {
                    AgentMark(agentID: agentID)
                    Text(agent.name)
                } else {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(PiperTheme.warning)
                    Text("Missing Agent")
                }
            }
        }
        .disabled(!canChangeAgent)
        .help(agentHelp)
        .accessibilityLabel("Agent")
        .modifier(FooterMenu())
    }

    private var modelMenu: some View {
        Menu {
            ForEach(models) { value in
                Button { setModel(value.id) } label: {
                    if value.id == model { Label(value.name, systemImage: "checkmark") } else { Text(value.name) }
                }
            }
        } label: {
            Text(models.first { $0.id == model }?.name ?? model ?? "Default Model")
        }
        .help("The model of the next turn")
        .accessibilityLabel("Model")
        .modifier(FooterMenu())
    }

    private var modeMenu: some View {
        Menu {
            ForEach(modes) { item in
                Button { setMode(item.id) } label: {
                    if item.id == mode { Label(item.name, systemImage: "checkmark") } else { Text(item.name) }
                }
                .help(item.description ?? "")
            }
        } label: {
            Text(modes.first { $0.id == mode }?.name ?? "Default Mode")
        }
        .help(modes.first { $0.id == mode }?.description ?? "How much the agent does without asking")
        .accessibilityLabel("Mode")
        .modifier(FooterMenu())
    }

    private var agentHelp: String {
        if agent == nil { return "This agent was removed. Add it again in Settings > AI." }
        return canChangeAgent ? "The agent of this session" : "A session keeps its agent after the first message"
    }

    // MARK: Actions

    private func setAgent(_ id: String) {
        if let session { runner.setAgent(id, for: session) } else { choice = SessionChoice(agentID: id) }
    }

    private func setModel(_ value: String) {
        if let session { runner.setModel(value, for: session) } else { choice.model = value }
    }

    private func setMode(_ value: String) {
        if let session { runner.setMode(value, for: session) } else { choice.mode = value }
    }
}

/// A small borderless menu in the footer of the composer.
private struct FooterMenu: ViewModifier {
    func body(content: Content) -> some View {
        content
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .foregroundStyle(PiperTheme.secondary)
    }
}

/// The request that waits for the reader, above the composer. The buttons are
/// the options of the agent, in its order.
struct ApprovalDrawer: View {
    let session: AgentSession
    let runner: SessionRunner

    private typealias Metrics = AppDefaults.Sessions

    var body: some View {
        let waiting = session.pendingRequests
        if let request = waiting.first {
            VStack(alignment: .leading, spacing: 8) {
                if request.isQuestion {
                    QuestionCard(request: request, answers: nil) { runner.answer(request, answers: $0, in: session) }
                } else {
                    approval(request, count: waiting.count)
                }
            }
            .padding(Metrics.requestPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PiperTheme.requestFill, in: RoundedRectangle(cornerRadius: Metrics.requestRadius))
            .overlay(RoundedRectangle(cornerRadius: Metrics.requestRadius).strokeBorder(PiperTheme.requestRing, lineWidth: 1))
            .padding(Metrics.requestMargin)
        }
    }

    private func approval(_ request: PermissionRequest, count: Int) -> some View {
        let options = request.options ?? ClaudeCodeConnection.options(in: URL(fileURLWithPath: session.folder))
        let detail = request.description ?? request.detail
        return VStack(alignment: .leading, spacing: Metrics.requestSpacing) {
            HStack(spacing: Metrics.requestButtonSpacing) {
                Text(Self.title(request)).font(PiperTheme.ui(13, weight: .semibold))
                if count > 1 {
                    Text("1 of \(count)").font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
                }
                Spacer(minLength: 4)
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(Font(PiperTheme.manuscript(size: Metrics.requestDetailFontSize)))
                    .foregroundStyle(PiperTheme.secondary)
                    .textSelection(.enabled)
                    .lineLimit(Metrics.requestDetailLineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(PermissionCard.diffs(of: request).enumerated()), id: \.offset) { _, item in
                DiffView(diff: item.diff) {
                    Text(item.title.isEmpty ? request.toolName + " " + detail : item.title)
                        .lineLimit(1).truncationMode(.middle)
                }
                .padding(.top, Metrics.requestSectionSpacing)
            }
            HStack(spacing: Metrics.requestButtonSpacing) {
                ForEach(options.filter { $0.kind == .allowOnce }) { option in
                    Button(option.name) { runner.respond(request, with: option, in: session) }
                        .buttonStyle(.borderedProminent)
                }
                ForEach(options.filter { $0.kind == .allowAlways }) { option in
                    Button(option.name) { runner.respond(request, with: option, in: session) }
                        .help(alwaysHelp(request))
                }
                ForEach(options.filter { !$0.kind.allows }) { option in
                    Button(option.name) { runner.respond(request, with: option, in: session) }
                        .help("To deny with a reason, type the reason in the message field and send it")
                }
                Spacer(minLength: 0)
            }
            .controlSize(.small)
            .padding(.top, Metrics.requestSectionSpacing)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The agent asks to use \(request.toolName)")
    }

    /// Claude Code keeps an Always choice as a rule in the folder settings. Another agent keeps it itself.
    private func alwaysHelp(_ request: PermissionRequest) -> String {
        guard session.agentID == AgentDefinition.claudeCodeID,
              let rule = PermissionRule.rule(toolName: request.toolName, input: request.input) else {
            return "Allows calls like this one from now on."
        }
        return "Adds \(rule) to .claude/settings.local.json in \(session.folderName)"
    }

    /// "Waiting for your approval: run a command", and so on, by the kind of the call.
    static func title(_ request: PermissionRequest) -> String {
        "Waiting for your approval: " + action(request)
    }

    private static func action(_ request: PermissionRequest) -> String {
        switch request.kind ?? ClaudeCodeConnection.kind(of: request.toolName) {
        case .execute: return "run a command"
        case .edit: return "change a file"
        case .delete: return "delete a file"
        case .move: return "move a file"
        case .read, .search: return "read files"
        case .fetch: return "open a web page"
        case .switchMode: return "change the mode"
        case .think, .other: return "use \(request.toolName)"
        }
    }
}
