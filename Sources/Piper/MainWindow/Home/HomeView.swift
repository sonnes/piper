import AppKit
import PiperCommands
import SwiftUI
import Vault

/// The page that the main window opens on.
///
/// One search field carries the whole page. `CommandParser` turns its text into
/// files, commands, skills, and actions, and the list under the field shows the
/// result. Below it, the most recently changed files appear as timeline cells.
struct HomeView: View {

    // MARK: Properties

    @Bindable var model: AppModel
    /// The text the browser toolbar left behind. Empty when the window opens here.
    var initialText = ""
    /// Opens a file. The window leaves the home page for the browser.
    let openFile: (String) -> Void
    /// Leaves the home page without opening a file.
    let showBrowser: () -> Void

    @State private var text = ""
    @State private var selection = 0
    @State private var commands: [WikiCommand] = []
    @State private var skills: [WikiSkill] = []
    @State private var candidates: [FileCandidate] = []
    @State private var runError: String?
    @State private var keyMonitor: Any?
    @FocusState private var focused: Bool

    /// The width of the search field and of the lists under it.
    private static let contentWidth: CGFloat = 560
    /// The width of the Recent list.
    private static let recentWidth: CGFloat = 660
    /// How many files the Recent list shows.
    private static let recentCount = 6
    /// A file younger than this carries the unread dot.
    private static let unreadAge: TimeInterval = 24 * 60 * 60

    private var parser: CommandParser {
        CommandParser(commands: commands, skills: skills, actions: actions)
    }

    private var suggestions: [CommandSuggestion] {
        parser.suggestions(for: text, files: candidates)
    }

    private var recent: [VaultFile] {
        Array(model.files.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(Self.recentCount))
    }

    /// The actions that `>` lists. Each one runs what the matching menu item runs.
    private var actions: [CommandAction] {
        [
            CommandAction(title: "New Capture", detail: "Open the capture panel", shortcut: "⌘1") { newCapture() },
            CommandAction(title: "Browse Files", detail: "Open the three-pane browser", shortcut: "⌘2") { browseFiles() },
            CommandAction(title: "Choose Wiki Folder…", detail: "Pick a different folder") { model.chooseWiki() },
            CommandAction(title: "Reveal in Finder", detail: "Show " + vaultPath) {
                NSWorkspace.shared.activateFileViewerSelecting([model.vault.root])
            },
            CommandAction(title: "Capture Clipboard", detail: "Save the clipboard as a note") { model.captureClipboard?() },
            CommandAction(title: "Settings…", detail: "Folder, shortcut, reading, style", shortcut: "⌘,") {
                model.route = "settings"
            }
        ]
    }

    private var vaultPath: String {
        (model.vault.root.path as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        let rows = suggestions
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    wordmark
                    searchField
                    if !rows.isEmpty {
                        HomeSuggestionList(suggestions: rows, selection: selection, run: run)
                            .frame(width: Self.contentWidth)
                            .padding(.top, 5)
                    }
                    if let runError {
                        Text(runError)
                            .font(PiperTheme.ui(11))
                            .foregroundStyle(PiperTheme.danger)
                            .frame(width: Self.contentWidth, alignment: .leading)
                            .padding(.top, 6)
                    }
                    buttons
                    if !recent.isEmpty { recentList }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 56)
                .padding(.bottom, 40)
            }
            .onChange(of: selection) { _, index in
                guard rows.indices.contains(index) else { return }
                proxy.scrollTo(rows[index].id, anchor: .bottom)
            }
        }
        .background(PiperTheme.page)
        .foregroundStyle(PiperTheme.ink)
        .onAppear {
            text = initialText
            focused = true
            installKeys()
            loadExtensions()
            loadCandidates()
        }
        .onDisappear(perform: removeKeys)
        .onChange(of: model.vault.root) { _, _ in loadExtensions() }
        .onChange(of: model.files) { _, _ in loadCandidates() }
        .onChange(of: text) { _, _ in
            selection = 0
            runError = nil
        }
    }
}

// MARK: - Parts

private extension HomeView {

    var wordmark: some View {
        VStack(spacing: 8) {
            if let mark = PiperTheme.mark {
                Image(nsImage: mark)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 42)
                    .accessibilityHidden(true)
            }
            Text("Piper")
                .font(PiperTheme.ui(34, weight: .semibold))
                .tracking(-0.6)
            Text(verbatim: "\(vaultPath) · \(model.files.count) \(model.files.count == 1 ? "file" : "files")")
                .font(PiperTheme.ui(12))
                .foregroundStyle(PiperTheme.secondary)
        }
        .padding(.bottom, 22)
    }

    var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(PiperTheme.ui(13))
                .foregroundStyle(PiperTheme.secondary)
            TextField("Search your wiki, or type / for commands", text: $text)
                .textFieldStyle(.plain)
                .font(PiperTheme.ui(14))
                .focused($focused)
                .onSubmit(runSelection)
                .accessibilityLabel("Search")
        }
        .padding(.horizontal, 14)
        .frame(width: Self.contentWidth, height: 36)
        .background(PiperTheme.page, in: Capsule())
        .overlay(Capsule().strokeBorder(focused ? PiperTheme.accent : PiperTheme.rule, lineWidth: 1))
    }

    var buttons: some View {
        HStack(spacing: 8) {
            button("New Capture", hint: "⌘1", action: newCapture)
            button("Commands & Skills", hint: "/") { fill("/") }
            button("Actions", hint: ">") { fill(">") }
            button("Browse Files", hint: "⌘2", action: browseFiles)
        }
        .padding(.top, 18)
    }

    func button(_ title: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Text(hint).foregroundStyle(PiperTheme.faint)
            }
        }
        .buttonStyle(PiperButtonStyle())
        .focusEffectDisabled()
        .accessibilityLabel(title)
    }

    var recentList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Recent")
                    .font(PiperTheme.ui(11, weight: .bold).smallCaps())
                    .tracking(0.3)
                    .foregroundStyle(PiperTheme.secondary)
                Spacer()
                Button("Show All", action: showBrowser)
                    .buttonStyle(.plain)
                    .font(PiperTheme.ui(11))
                    .foregroundStyle(PiperTheme.accent)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
            ForEach(recent) { file in
                Button { openFile(file.id) } label: {
                    TimelineCell(
                        file: file,
                        rootName: model.vault.root.lastPathComponent,
                        showsDot: Date().timeIntervalSince(file.modifiedAt) < Self.unreadAge
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: Self.recentWidth, alignment: .leading)
        .padding(.top, 36)
    }
}

// MARK: - Content

private extension HomeView {

    /// Reads the commands and the skills that this folder reaches.
    ///
    /// The scan reads two directories, so it runs off the main thread and the
    /// result lands back on it. It runs at appearance and when the folder
    /// changes, never on a keystroke.
    func loadExtensions() {
        let root = model.vault.root
        Task {
            let scan = await Task.detached {
                (CommandIndex.all(wikiRoot: root), SkillIndex.all(wikiRoot: root))
            }.value
            commands = scan.0
            skills = scan.1
        }
    }

    /// Turns the files of the model into the candidates that the parser reads.
    ///
    /// The parser reads no file, so the excerpt holds the whole body on one
    /// line. The parser searches that string, and a row shows its first part.
    func loadCandidates() {
        let root = model.vault.root
        candidates = model.files.map { file in
            FileCandidate(
                url: root.appendingPathComponent(file.relativePath),
                folder: file.folder,
                excerpt: file.body.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            )
        }
    }
}

// MARK: - Keyboard

private extension HomeView {

    /// Takes the arrow keys and Escape while the search field holds focus.
    ///
    /// A single-line text field answers the arrow keys itself, so a monitor in
    /// front of the responder chain is the only way to read them here. This is
    /// the pattern that the Wiki browser already uses for its own keys.
    func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard focused, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return event }
            switch event.keyCode {
            case 125: return move(1) ? nil : event
            case 126: return move(-1) ? nil : event
            case 53: return clear() ? nil : event
            default: return event
            }
        }
    }

    func removeKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Moves the selection, and reports whether it moved.
    func move(_ offset: Int) -> Bool {
        let count = suggestions.count
        guard count > 0 else { return false }
        selection = (selection + offset + count) % count
        return true
    }

    /// Empties the field, and reports whether it held text.
    func clear() -> Bool {
        guard !text.isEmpty else { return false }
        text = ""
        return true
    }

    func fill(_ prefix: String) {
        text = prefix
        selection = 0
        focused = true
    }
}

// MARK: - Running

private extension HomeView {

    func runSelection() {
        guard suggestions.indices.contains(selection) else { return }
        run(suggestions[selection])
    }

    /// Runs one row. The row carries what it means, so nothing here reads the title.
    func run(_ suggestion: CommandSuggestion) {
        switch suggestion.target {
        case .file(let file):
            openFile(file.path)
        case .command(let command, let arguments):
            start(.command(command), arguments: arguments)
        case .skill(let skill, let arguments):
            start(.skill(skill), arguments: arguments)
        case .action(let action):
            action.run()
        case .searchEverything(let query):
            model.wikiQuery = query
            browseFiles()
        }
        text = ""
    }

    /// Starts Claude Code and opens the transcript sheet over the browser.
    func start(_ job: WikiAgentJob, arguments: String) {
        runError = nil
        model.route = "commands"
        Task { runError = await model.runCommand(job, arguments: arguments) }
    }

    func newCapture() {
        model.openPanel?()
    }

    func browseFiles() {
        model.route = "wiki"
        showBrowser()
    }
}
