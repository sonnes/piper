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
        tabs.addTab("Claude", symbol: "sparkles", size: NSSize(width: 560, height: 480),
                    content: ClaudeSettings(model: model))

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

/// The claude command, what a run may do, and the folders that take part.
private struct ClaudeSettings: View {
    @Bindable var model: AppModel
    private var agents: FolderAgents { model.agents }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack {
                        if agents.claudePath != nil {
                            Button("Find Automatically") { agents.claudePath = nil }
                        }
                        Button("Choose…", action: chooseExecutable)
                    }
                } label: {
                    Text("Claude Code")
                    Text(agents.runner.executable.map { ($0.path as NSString).abbreviatingWithTildeInPath }
                         ?? "Not found. Install Claude Code, or choose the claude command.")
                        .foregroundStyle(agents.runner.executable == nil ? PiperTheme.danger : PiperTheme.secondary)
                }
                Picker(selection: Binding(get: { agents.model }, set: { agents.model = $0 })) {
                    Text("Sonnet").tag("sonnet")
                    Text("Opus").tag("opus")
                    Text("Haiku").tag("haiku")
                    Text("Claude Code Default").tag("")
                } label: {
                    Text("Model")
                    Text("Claude Code Default uses the model in your Claude Code settings.")
                }
                Picker(selection: Binding(get: { agents.permissionMode }, set: { agents.permissionMode = $0 })) {
                    Text("Auto").tag(PermissionMode.auto)
                    Text("Edit Files Only").tag(PermissionMode.acceptEdits)
                    Text("Ask Every Time").tag(PermissionMode.ask)
                    Text("Allow Every Tool").tag(PermissionMode.bypassPermissions)
                } label: {
                    Text("Permissions")
                    switch agents.permissionMode {
                    case .auto: Text("Claude Code allows safe tools and asks about risky ones. Use Sonnet or Opus.")
                    case .acceptEdits: Text("Claude edits files without asking. Other tools show a card in the session.")
                    case .ask: Text("Each tool that the folder settings do not allow shows a card in the session.")
                    case .bypassPermissions: Text("A session can use any tool, including shell commands, without asking.")
                    }
                }
            } header: {
                Text("Command")
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
                Text("Send runs the skill for links or for text in the folder you used last. \(SendShortcut.glyphs) sends the clipboard.")
                    .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { agents.refresh(paths: model.wikiPaths) }
    }

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
    @AppStorage(AppDefaults.Key.readerSize) private var fontSize = 18.0
    @AppStorage(AppDefaults.Key.readerTheme) private var theme = WikiReadingTheme.paper
    @AppStorage(AppDefaults.Key.readerFont) private var font = WikiReadingFont.sans
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
                    Button("Reset to Defaults") { theme = .paper; font = .sans; fontSize = 18; appearance = .system }
                }
            }
        }
        .formStyle(.grouped)
    }
}
