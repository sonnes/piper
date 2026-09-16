import AppKit
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
        tabs.addTab("Capture", symbol: "text.cursor", size: NSSize(width: 560, height: 280),
                    content: CaptureSettings(model: model))
        tabs.addTab("Reading", symbol: "book", size: NSSize(width: 560, height: 300),
                    content: ReadingSettings())

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

/// The capture shortcut, Accessibility access, and the clipboard fallback.
private struct CaptureSettings: View {
    @Bindable var model: AppModel
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
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
