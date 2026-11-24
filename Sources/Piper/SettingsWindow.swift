import AppKit
import Agents
import Combine
import PiperCore
import SwiftUI

/// Owns the Settings window.
///
/// A toolbar tab controller holds one pane for each tab, as in the Settings
/// windows of the system applications. The window title follows the tab.
@MainActor
final class SettingsWindowController: NSWindowController {

    init(model: AppModel) {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTab("General", symbol: "gearshape", size: Metrics.generalSize,
                    content: GeneralSettings(model: model))
        tabs.addTab("Capture", symbol: "text.cursor", size: Metrics.captureSize,
                    content: CaptureSettings(model: model))
        tabs.addTab("Reading", symbol: "book", size: Metrics.readingSize,
                    content: ReadingPane())
        tabs.addTab("AI", symbol: "sparkles", size: Metrics.aiSize,
                    content: AISettings(model: model))
        tabs.addTab("Feeds", symbol: "dot.radiowaves.up.forward", size: Metrics.feedsSize,
                    content: FeedsSettings(scan: model.siteScan))

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Metrics.generalSize),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.contentViewController = tabs
        window.title = "General"
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        QA.activate()
    }
}

extension SettingsWindowController {
    /// The size of each tab of the window.
    enum Metrics {
        static let generalSize = NSSize(width: 560, height: 330)
        static let captureSize = NSSize(width: 560, height: 380)
        static let readingSize = NSSize(width: 560, height: 300)
        static let aiSize = NSSize(width: 600, height: 640)
        static let feedsSize = NSSize(width: 600, height: 560)
    }
}

/// Keeps the window title on the name of the selected tab.
private final class SettingsTabViewController: NSTabViewController {

    func addTab(_ title: String, symbol: String, size: NSSize, content: some View) {
        let hosting = NSHostingController(rootView: content.frame(width: size.width, height: size.height))
        hosting.preferredContentSize = size
        hosting.title = title
        let item = NSTabViewItem(viewController: hosting)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        addTabViewItem(item)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let label = tabViewItem?.label { view.window?.title = label }
    }
}

// MARK: - Panes

/// The folders on the Folders index and the location of the note database.
private struct GeneralSettings: View {
    @Bindable var model: AppModel
    @State private var selection: String?

    var body: some View {
        Form {
            Section("Folders") {
                List(model.library.wikiPaths, id: \.self, selection: $selection) { path in
                    HStack(spacing: 8) {
                        Image(systemName: "folder").foregroundStyle(PiperTheme.brand)
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                        Spacer()
                        Text((path as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(PiperTheme.paperMuted).lineLimit(1).truncationMode(.head)
                    }
                    .font(PiperTheme.paperUI(.body))
                }
                .frame(height: 96)
                .listStyle(.bordered(alternatesRowBackgrounds: false))
                HStack(spacing: 0) {
                    Button { model.library.chooseWiki() } label: { Image(systemName: "plus").frame(width: 20, height: 16) }
                        .help("Add Folder").accessibilityLabel("Add Folder")
                    Button {
                        if let selection { model.library.removeWikiFolder(selection) }
                        selection = nil
                    } label: { Image(systemName: "minus").frame(width: 20, height: 16) }
                        .disabled(selection == nil || model.library.wikiPaths.count < 2)
                        .help("Remove Folder. The folder stays on disk.").accessibilityLabel("Remove Folder")
                    Spacer()
                }
                .buttonStyle(.borderless)
            }
            Section("Local Data") {
                LabeledContent {
                    Button("Show in Finder") {
                        NSWorkspace.shared.open(DataFolder.url)
                    }
                } label: {
                    Text("Notes database")
                    Text("~/Library/Application Support/Piper")
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// The selection shortcut, Accessibility access, and clipboard fallback.
private struct CaptureSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Selection Capture") {
                Picker(selection: $model.captureShortcut) {
                    ForEach(CaptureShortcut.allCases, id: \.self) { shortcut in
                        Text(shortcut.title).tag(shortcut)
                    }
                } label: {
                    Text("Shortcut")
                    Text("Saves the selected text from the app in front.")
                }
                LabeledContent {
                    Button("Open System Settings…") { model.requestAccessibility() }
                } label: {
                    Text("Accessibility")
                    Text(model.accessibilityEnabled ? "Enabled. Piper can read a selection." : "Not enabled. Piper cannot read a selection.")
                }
            }
            Section("Clipboard") {
                LabeledContent {
                    Button("Capture Now") { model.captureClipboard() }
                } label: {
                    Text("Capture Clipboard")
                    Text("Use it when an app does not expose its selection.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// The agents, their health, the defaults of a new session and of a margin
/// answer, and the folders whose skills Send runs.
private struct AISettings: View {
    @Bindable var model: AppModel
    @State private var adding: AgentDefinition?
    private var agents: AgentSettings { model.agents }

    var body: some View {
        Form {
            Section {
                AgentRow(agent: .claudeCode, status: agents.health[AgentDefinition.claudeCodeID]) {
                    HStack(spacing: 6) {
                        Text(agents.runner.executable.map { ($0.path as NSString).abbreviatingWithTildeInPath }
                             ?? "No claude command")
                            .foregroundStyle(agents.runner.executable == nil ? PiperTheme.danger : PiperTheme.paperMuted)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        if agents.claudePath != nil {
                            Button("Find Automatically") { agents.claudePath = nil; agents.refreshHealth() }
                        }
                        Button("Choose…", action: chooseExecutable)
                    }
                }
                ForEach(agents.acpAgents) { agent in
                    AgentRow(agent: agent, status: agents.health[agent.id]) {
                        HStack(spacing: 6) {
                            Text(([agent.command] + agent.arguments).joined(separator: " "))
                                .font(Font(PiperTheme.manuscript(size: 11)))
                                .foregroundStyle(PiperTheme.paperMuted)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            Button("Remove") { agents.removeAgent(agent) }
                        }
                    }
                }
                HStack {
                    Menu("Add ACP Agent") {
                        ForEach(Self.presets, id: \.name) { preset in
                            Button(preset.name) { adding = preset }
                        }
                        Divider()
                        Button("Other…") { adding = AgentDefinition(name: "", command: "") }
                    }
                    .fixedSize()
                    Spacer()
                    Button("Check Again") { agents.refreshHealth() }
                }
            } header: {
                Text("Agents")
            } footer: {
                Text("An ACP agent is a command that speaks the Agent Client Protocol on standard input and output.")
                    .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted)
            }
            Section {
                Picker("New sessions", selection: Binding(get: { agents.sessionAgentID }, set: { agents.sessionAgentID = $0 })) {
                    ForEach(agents.allAgents) { Text($0.name).tag($0.id) }
                }
                Picker(selection: Binding(get: { agents.marginAgentID }, set: { agents.setMarginAgent($0) })) {
                    ForEach(agents.marginAgents) { Text($0.name).tag($0.id) }
                } label: {
                    Text("Margin answers")
                    Text("Answers in the reader margin can read files and the web, and change nothing. An ACP agent must offer a read-only mode, such as Plan.")
                }
                if agents.marginAgentID == AgentDefinition.claudeCodeID {
                    Picker("Margin model", selection: Binding(get: { agents.marginModel }, set: { agents.marginModel = $0 })) {
                        ForEach(ClaudeCodeConnection.models) { Text($0.name).tag($0.id) }
                    }
                }
            } header: {
                Text("Defaults")
            } footer: {
                Text("The composer of a session can change its agent before the first message, and its model and mode at any time.")
                    .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted)
            }
            Section {
                Picker(selection: Binding(get: { agents.model }, set: { agents.model = $0 })) {
                    ForEach(ClaudeCodeConnection.models) { Text($0.name).tag($0.id) }
                } label: {
                    Text("Model")
                    Text("Claude Code Default uses the model in your Claude Code settings.")
                }
                Picker(selection: Binding(get: { agents.permissionMode }, set: { agents.permissionMode = $0 })) {
                    ForEach(PermissionMode.allCases, id: \.self) { Text($0.name).tag($0) }
                } label: {
                    Text("Permissions")
                    Text(agents.permissionMode.detail)
                }
            } header: {
                Text("Claude Code")
            } footer: {
                Text("Skill runs from Send use these. A session can choose another model or mode in its composer.")
                    .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted)
            }
            Section {
                if model.skills.available.isEmpty {
                    Text("No folder on the Folders index has skills in .claude/skills.")
                        .foregroundStyle(PiperTheme.paperMuted)
                }
                ForEach(model.skills.available) { folder in
                    SkillFolderRow(skills: model.skills, folder: folder)
                }
            } header: {
                Text("Folders")
            } footer: {
                Text("Send runs a Claude Code skill for links or for text in the folder you used last. \(Command.sendClipboard.key?.glyph ?? "") sends the clipboard.")
                    .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted)
            }
        }
        .formStyle(.grouped)
        .onAppear { agents.refreshHealth() }
        .sheet(item: $adding) { draft in
            AddAgentSheet(draft: draft) { name, command, arguments in
                agents.addAgent(name: name, command: command, arguments: arguments)
                adding = nil
            } cancel: {
                adding = nil
            }
        }
    }

    /// Agents that speak ACP, with the command that starts each.
    static let presets = [
        AgentDefinition(name: "Gemini CLI", command: "gemini", arguments: ["--experimental-acp"]),
        AgentDefinition(name: "OpenCode", command: "opencode", arguments: ["acp"]),
        AgentDefinition(name: "Codex", command: "codex-acp")
    ]

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = true
        panel.showsHiddenFiles = true
        panel.message = "Choose the claude command."
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        agents.claudePath = url.path
        agents.refreshHealth()
    }
}

/// One agent: its health, its name, its version, and a line of controls.
private struct AgentRow<Controls: View>: View {
    let agent: AgentDefinition
    let status: AgentStatus?
    @ViewBuilder let controls: Controls

    private var color: Color {
        switch status?.health {
        case .ready?: return PiperTheme.success
        case .warning?: return PiperTheme.warning
        case .error?: return PiperTheme.danger
        case .checking?, nil: return PiperTheme.paperFaint
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                    .accessibilityLabel(status?.headline ?? "Not checked")
                AgentMark(agentID: agent.id)
                Text(agent.name).font(PiperTheme.paperUI(.body, weight: .semibold))
                Text(status?.headline ?? "Not checked")
                    .foregroundStyle(PiperTheme.paperMuted)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                if let version = status?.version {
                    Text(version).font(Font(PiperTheme.manuscript(size: 11))).foregroundStyle(PiperTheme.paperMuted)
                }
            }
            controls.font(PiperTheme.paperUI(.body))
        }
    }
}

/// The name, the command, and the arguments of a new ACP agent.
private struct AddAgentSheet: View {
    @State private var name: String
    @State private var command: String
    @State private var arguments: String
    let add: (String, String, [String]) -> Void
    let cancel: () -> Void

    init(draft: AgentDefinition, add: @escaping (String, String, [String]) -> Void, cancel: @escaping () -> Void) {
        _name = State(initialValue: draft.name)
        _command = State(initialValue: draft.command)
        _arguments = State(initialValue: draft.arguments.joined(separator: " "))
        self.add = add
        self.cancel = cancel
    }

    private var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !command.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add ACP Agent").font(PiperTheme.paperUI(.row, weight: .semibold))
            Form {
                TextField("Name", text: $name)
                TextField("Command", text: $command, prompt: Text("A path, or a name on your PATH"))
                TextField("Arguments", text: $arguments, prompt: Text("Separated by spaces"))
            }
            Text("Piper starts the command in the folder of each session, through your login shell.")
                .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Add") {
                    add(name.trimmingCharacters(in: .whitespaces), command.trimmingCharacters(in: .whitespaces),
                        arguments.split(whereSeparator: \.isWhitespace).map(String.init))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isComplete)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// One folder with skills: its switch and the skills that Send runs.
private struct SkillFolderRow: View {
    let skills: SkillFolders
    let folder: SkillFolders.Folder

    var body: some View {
        Toggle(isOn: Binding(get: { skills.isEnabled(folder) }, set: { skills.setEnabled($0, for: folder) })) {
            Text(folder.name)
            Text("\(folder.skills.count) skills · " + (folder.path as NSString).abbreviatingWithTildeInPath)
        }
        if skills.isEnabled(folder) {
            skillPicker("Links run", forLink: true)
            skillPicker("Text runs", forLink: false)
        }
    }

    private func skillPicker(_ title: String, forLink: Bool) -> some View {
        Picker(title, selection: Binding(
            get: { skills.defaultSkill(forLink: forLink, in: folder)?.name ?? SkillFolders.noSkill },
            set: { skills.setDefaultSkill($0, forLink: forLink, in: folder) }
        )) {
            Text("Nothing").tag(SkillFolders.noSkill)
            ForEach(folder.skills, id: \.name) { skill in
                Text("/" + skill.name).tag(skill.name)
            }
        }
        .padding(.leading, 16)
    }
}

/// Font, size, paper, and appearance for Markdown files.
private struct ReadingPane: View {
    private var reading = ReadingSettings()

    var body: some View {
        Form {
            Section {
                Picker("Font", selection: reading.$font) {
                    Text("Mono").tag(WikiReadingFont.mono)
                    Text("Serif").tag(WikiReadingFont.serif)
                    Text("Sans").tag(WikiReadingFont.sans)
                }
                .pickerStyle(.segmented)
                LabeledContent("Size") {
                    HStack(spacing: 6) {
                        Text("\(Int(reading.size)) pt").monospacedDigit()
                        Stepper("Size", value: reading.$size, in: 13...24, step: 1).labelsHidden()
                    }
                }
                Picker("Paper", selection: reading.$theme) {
                    ForEach(WikiReadingTheme.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Appearance", selection: reading.$appearance) {
                    ForEach(WikiReadingAppearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Markdown Files")
            } footer: {
                HStack {
                    Text("These settings change how Piper shows a file. The file does not change.")
                        .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted)
                    Spacer()
                    Button("Reset to Defaults") { reading.reset() }
                }
            }
        }
        .formStyle(.grouped)
    }
}
