import PiperCore
import PiperCommands
import SwiftUI
import Vault

/// Picks a command or a skill, runs it, and shows the output as it arrives.
///
/// Claude Code reads two kinds of extension from a folder. The picker lists both,
/// in separate groups, because both are reachable from the same `claude` run.
struct WikiCommandView: View {
    @Bindable var model: AppModel
    @State private var jobs: [WikiAgentJob] = []
    @State private var selection: WikiAgentJob?
    @State private var arguments = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var agent: WikiAgent { model.agent }
    private var commands: [WikiAgentJob] { jobs.filter { if case .command = $0 { return true } else { return false } } }
    private var skills: [WikiAgentJob] { jobs.filter { if case .skill = $0 { return true } else { return false } } }

    private var summary: String {
        switch selection {
        case .command(let command): return command.summary
        case .skill(let skill): return skill.summary
        case nil: return ""
        }
    }

    private var argumentHint: String? {
        guard case .command(let command) = selection, command.takesArguments else { return nil }
        return command.argumentHint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Commands And Skills").font(PiperTheme.ui(13, weight: .semibold))
                Text("· \(model.vault.root.lastPathComponent)").font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary)
                Spacer()
                if agent.isRunning { ProgressView().controlSize(.small) }
            }
            if jobs.isEmpty {
                Text("This folder reaches no commands and no skills. Commands live in .claude/commands and skills live in .claude/skills, either inside this folder or in your home folder.")
                    .font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                picker
                if selection != nil {
                    Text(summary).font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let argumentHint {
                        PiperField(title: argumentHint, text: $arguments)
                    } else if case .skill = selection {
                        PiperField(title: "What the skill works on", text: $arguments, hint: "optional")
                    }
                }
            }
            transcript
            if let error {
                Text(error).font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.danger).textSelection(.enabled)
            }
            Text("Runs Claude Code in the Wiki folder. It edits files there and reaches the network.")
                .font(PiperTheme.ui(10.5)).foregroundStyle(PiperTheme.faint)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(PiperButtonStyle()).keyboardShortcut(.cancelAction).disabled(agent.isRunning)
                if agent.isRunning {
                    Button("Stop") { agent.cancel() }.buttonStyle(PiperButtonStyle())
                } else {
                    Button("Run") { start() }.buttonStyle(PiperButtonStyle(prominent: true)).disabled(selection == nil)
                }
            }
        }
        .padding(22).frame(width: 560, height: 520)
        .background(PiperTheme.page).foregroundStyle(PiperTheme.ink)
        .interactiveDismissDisabled(agent.isRunning)
        .onAppear(perform: load)
    }

    private var picker: some View {
        Picker("Command Or Skill", selection: $selection) {
            if !commands.isEmpty {
                Section("Commands") {
                    ForEach(commands) { job in row(job).tag(Optional(job)) }
                }
            }
            if !skills.isEmpty {
                Section("Skills") {
                    ForEach(skills) { job in row(job).tag(Optional(job)) }
                }
            }
        }
        .labelsHidden().pickerStyle(.menu).controlSize(.regular).fixedSize()
        .disabled(agent.isRunning)
        .accessibilityLabel("Command Or Skill")
        .onChange(of: selection) { _, _ in arguments = "" }
    }

    private func row(_ job: WikiAgentJob) -> some View {
        Text("/" + job.name + (job.scope.tag.isEmpty ? "" : " · " + job.scope.tag))
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(agent.transcript.isEmpty ? "No output yet." : agent.transcript)
                    .font(Font(PiperTheme.manuscript(size: 11))).lineSpacing(3)
                    .foregroundStyle(agent.transcript.isEmpty ? PiperTheme.secondary : PiperTheme.ink)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                Color.clear.frame(height: 1).id("end")
            }
            .onChange(of: agent.transcript) { _, _ in proxy.scrollTo("end") }
        }
        .frame(maxHeight: .infinity)
        .overlay(RoundedRectangle(cornerRadius: PiperTheme.radius).strokeBorder(PiperTheme.rule, lineWidth: 1))
    }

    private func load() {
        let root = model.vault.root
        jobs = CommandIndex.all(wikiRoot: root).map(WikiAgentJob.command)
            + SkillIndex.all(wikiRoot: root).map(WikiAgentJob.skill)
        if selection == nil || !jobs.contains(where: { $0 == selection }) { selection = jobs.first }
    }

    private func start() {
        guard let job = selection else { return }
        error = nil
        Task { error = await model.runCommand(job, arguments: arguments) }
    }
}
