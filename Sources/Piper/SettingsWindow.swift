import AppKit
import Agents
import ApplicationServices
import Combine
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
        tabs.addTab("General", symbol: "gearshape", size: NSSize(width: 560, height: 330),
                    content: GeneralSettings(model: model))
        tabs.addTab("Capture", symbol: "text.cursor", size: AppDefaults.Window.captureSettingsSize,
                    content: CaptureSettings(model: model))
        tabs.addTab("Reading", symbol: "book", size: NSSize(width: 560, height: 300),
                    content: ReadingSettings())
        tabs.addTab("AI", symbol: "sparkles", size: NSSize(width: 600, height: 640),
                    content: AISettings(model: model))

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: NSSize(width: 560, height: 330)),
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
        NSApp.activate(ignoringOtherApps: true)
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

/// The folders in the sidebar and the location of the note database.
private struct GeneralSettings: View {
    @Bindable var model: AppModel
    @State private var selection: String?

    var body: some View {
        Form {
            Section("Folders") {
                List(model.wikiPaths, id: \.self, selection: $selection) { path in
                    HStack(spacing: 8) {
                        Image(systemName: "folder").foregroundStyle(PiperTheme.accent)
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                        Spacer()
                        Text((path as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(PiperTheme.secondary).lineLimit(1).truncationMode(.head)
                    }
                    .font(PiperTheme.ui(13))
                }
                .frame(height: 96)
                .listStyle(.bordered(alternatesRowBackgrounds: false))
                HStack(spacing: 0) {
                    Button { model.chooseWiki() } label: { Image(systemName: "plus").frame(width: 20, height: 16) }
                        .help("Add Folder").accessibilityLabel("Add Folder")
                    Button {
                        if let selection { model.removeWikiFolder(selection) }
                        selection = nil
                    } label: { Image(systemName: "minus").frame(width: 20, height: 16) }
                        .disabled(selection == nil || model.wikiPaths.count < 2)
                        .help("Remove Folder. The folder stays on disk.").accessibilityLabel("Remove Folder")
                    Spacer()
                }
                .buttonStyle(.borderless)
            }
            Section("Local Data") {
                LabeledContent {
                    Button("Show in Finder") {
                        NSWorkspace.shared.open(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Piper"))
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

/// The capture panel, shortcut, Accessibility access, and clipboard fallback.
private struct CaptureSettings: View {
    @Bindable var model: AppModel
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Capture Window") {
                Toggle(isOn: $model.captureFloating) {
                    Text("Float Above Other Windows")
                    Text("Keeps the capture panel above other apps.")
                }
            }
            Section("Selection Capture") {
                Picker(selection: $model.captureShortcut) {
                    Text("⇧ ⇧ (Shift twice)").tag("Shift, Shift")
                    Text("⌃⌥Space").tag("Control-Option-Space")
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
                    Button("Capture Now") { model.store.captureClipboard() }
                } label: {
                    Text("Capture Clipboard")
                    Text("Use it when an app does not expose its selection.")
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in model.accessibilityEnabled = AXIsProcessTrusted() }
    }
}

/// The agents, their health, the defaults of a new session and of a margin
/// answer, and the folders whose skills Send runs.
private struct AISettings: View {
    @Bindable var model: AppModel
    @State private var adding: AgentDefinition?
    private var agents: FolderAgents { model.agents }

    var body: some View {
        Form {
            Section {
                AgentRow(agent: .claudeCode, status: agents.health[AgentDefinition.claudeCodeID]) {
                    HStack(spacing: 6) {
                        Text(agents.runner.executable.map { ($0.path as NSString).abbreviatingWithTildeInPath }
                             ?? "No claude command")
                            .foregroundStyle(agents.runner.executable == nil ? PiperTheme.danger : PiperTheme.secondary)
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
                                .foregroundStyle(PiperTheme.secondary)
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
                    .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
            }
            Section {
                Picker("New sessions", selection: Binding(get: { agents.sessionAgentID }, set: { agents.sessionAgentID = $0 })) {
                    ForEach(agents.allAgents) { Text($0.name).tag($0.id) }
                }
                Picker(selection: Binding(get: { agents.marginAgentID }, set: { id in
                    agents.marginAgentID = id
                    agents.marginModel = id == AgentDefinition.claudeCodeID ? AppDefaults.Agents.marginModel : ""
                })) {
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
                    .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
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
                    switch agents.permissionMode {
                    case .auto: Text("Claude Code allows safe tools and asks about risky ones. Use Sonnet or Opus.")
                    case .acceptEdits: Text("Claude edits files without asking. Other tools ask in the session.")
                    case .ask: Text("Each tool that the folder settings do not allow asks in the session.")
                    case .plan: Text("Claude Code reads and plans, and edits no files.")
                    case .bypassPermissions: Text("A session can use any tool, including shell commands, without asking.")
                    }
                }
            } header: {
                Text("Claude Code")
            } footer: {
                Text("Skill runs from Send use these. A session can choose another model or mode in its composer.")
                    .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
            }
            Section {
                if agents.available.isEmpty {
                    Text("No sidebar folder has skills in .claude/skills.")
                        .foregroundStyle(PiperTheme.secondary)
                }
                ForEach(agents.available) { folder in
                    FolderAgentRow(agents: agents, folder: folder)
                }
            } header: {
                Text("Folders")
            } footer: {
                Text("Send runs a Claude Code skill for links or for text in the folder you used last. \(SendShortcut.glyphs) sends the clipboard.")
                    .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            agents.refresh(paths: model.wikiPaths)
            agents.refreshHealth()
        }
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
        case .checking?, nil: return PiperTheme.faint
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                    .accessibilityLabel(status?.headline ?? "Not checked")
                AgentMark(agentID: agent.id)
                Text(agent.name).font(PiperTheme.ui(13, weight: .semibold))
                Text(status?.headline ?? "Not checked")
                    .foregroundStyle(PiperTheme.secondary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                if let version = status?.version {
                    Text(version).font(Font(PiperTheme.manuscript(size: 11))).foregroundStyle(PiperTheme.secondary)
                }
            }
            controls.font(PiperTheme.ui(12))
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
            Text("Add ACP Agent").font(PiperTheme.ui(15, weight: .semibold))
            Form {
                TextField("Name", text: $name)
                TextField("Command", text: $command, prompt: Text("A path, or a name on your PATH"))
                TextField("Arguments", text: $arguments, prompt: Text("Separated by spaces"))
            }
            Text("Piper starts the command in the folder of each session, through your login shell.")
                .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
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
private struct FolderAgentRow: View {
    let agents: FolderAgents
    let folder: FolderAgents.Folder

    var body: some View {
        Toggle(isOn: Binding(get: { agents.isEnabled(folder) }, set: { agents.setEnabled($0, for: folder) })) {
            Text(folder.name)
            Text("\(folder.skills.count) skills · " + (folder.path as NSString).abbreviatingWithTildeInPath)
        }
        if agents.isEnabled(folder) {
            skillPicker("Links run", forLink: true)
            skillPicker("Text runs", forLink: false)
        }
    }

    private func skillPicker(_ title: String, forLink: Bool) -> some View {
        Picker(title, selection: Binding(
            get: { agents.defaultSkill(forLink: forLink, in: folder)?.name ?? FolderAgents.noSkill },
            set: { agents.setDefaultSkill($0, forLink: forLink, in: folder) }
        )) {
            Text("Nothing").tag(FolderAgents.noSkill)
            ForEach(folder.skills, id: \.name) { skill in
                Text("/" + skill.name).tag(skill.name)
            }
        }
        .padding(.leading, 16)
    }
}

/// Font, size, paper, and appearance for Markdown files.
private struct ReadingSettings: View {
    @AppStorage(AppDefaults.Key.readerSize) private var fontSize = AppDefaults.Reader.defaultSize
    @AppStorage(AppDefaults.Key.readerTheme) private var theme = WikiReadingTheme.paper
    @AppStorage(AppDefaults.Key.readerFont) private var font = AppDefaults.Reader.defaultFont
    @AppStorage(AppDefaults.Key.readerAppearance) private var appearance = WikiReadingAppearance.system

    var body: some View {
        Form {
            Section {
                Picker("Font", selection: $font) {
                    Text("Mono").tag(WikiReadingFont.mono)
                    Text("Serif").tag(WikiReadingFont.serif)
                    Text("Sans").tag(WikiReadingFont.sans)
                }
                .pickerStyle(.segmented)
                LabeledContent("Size") {
                    HStack(spacing: 6) {
                        Text("\(Int(fontSize)) pt").monospacedDigit()
                        Stepper("Size", value: $fontSize, in: 13...24, step: 1).labelsHidden()
                    }
                }
                Picker("Paper", selection: $theme) {
                    ForEach(WikiReadingTheme.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Appearance", selection: $appearance) {
                    ForEach(WikiReadingAppearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Markdown Files")
            } footer: {
                HStack {
                    Text("These settings change how Piper shows a file. The file does not change.")
                        .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
                    Spacer()
                    Button("Reset to Defaults") { theme = .paper; font = AppDefaults.Reader.defaultFont; fontSize = AppDefaults.Reader.defaultSize; appearance = .system }
                }
            }
        }
        .formStyle(.grouped)
    }
}
