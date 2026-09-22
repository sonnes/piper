import AppKit
import PiperCore
import SwiftUI
import Vault

/// The home page with file search, local actions, and recent files.
struct HomeView: View {

    // MARK: Properties

    @Bindable var model: AppModel
    /// The initial query. Empty when the window opens here.
    var initialText = ""
    /// Opens a file. The window leaves the home page for the browser.
    let openFile: (String) -> Void
    /// Leaves the home page without opening a file.
    let showBrowser: () -> Void
    let searchFiles: (String) -> Void
    let newCapture: () -> Void

    @State private var text = ""
    @State private var selection = 0
    @State private var candidates: [FileCandidate] = []
    @State private var keyMonitor: Any?
    @FocusState private var focused: Bool

    /// The width of the search field and of the lists under it.
    private static let contentWidth: CGFloat = 480
    /// The width of the Recent list.
    private static let recentWidth: CGFloat = AppDefaults.Reader.columnWidth
    /// How many files the Recent list shows.
    private static let recentCount = 6

    private var parser: HomeSearch {
        HomeSearch(actions: actions)
    }

    private var suggestions: [HomeSuggestion] {
        parser.suggestions(for: text, files: candidates)
    }

    private var recent: [VaultFile] {
        Array(model.files.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(Self.recentCount))
    }

    /// The actions that `>` lists. Each one runs what the matching menu item runs.
    private var actions: [HomeAction] {
        [
            HomeAction(title: "New Capture", detail: "Write a note in Inbox", shortcut: "⌘N") { newCapture() },
            HomeAction(title: "Browse Files", detail: "Show the files of the folder", shortcut: "⌘2") { browseFiles() },
            HomeAction(title: "Add Folder…", detail: "Add a folder to the sidebar") { model.chooseWiki() },
            HomeAction(title: "Reveal in Finder", detail: "Show " + vaultPath) {
                NSWorkspace.shared.activateFileViewerSelecting([model.vault.root])
            },
            HomeAction(title: "Capture Clipboard", detail: "Save the clipboard as a note") { model.captureClipboard() },
            HomeAction(title: "Settings…", detail: "Folders, shortcut, and reading", shortcut: "⌘,") {
                model.openSettings?()
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
                    searchField
                    Text("Type > for actions")
                        .font(PiperTheme.ui(11))
                        .foregroundStyle(PiperTheme.faint)
                        .padding(.top, 8)
                    if !recent.isEmpty { recentList }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 64)
                .padding(.bottom, 40)
                .overlay(alignment: .top) {
                    if !rows.isEmpty {
                        HomeSuggestionList(suggestions: rows, selection: selection, run: run)
                            .frame(width: Self.contentWidth)
                            .padding(.top, 64 + 30 + 6)
                    }
                }
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
            loadCandidates()
        }
        .onDisappear(perform: removeKeys)
        .onChange(of: model.files) { _, _ in loadCandidates() }
        .onChange(of: text) { _, _ in
            selection = 0
        }
    }
}

// MARK: - Parts

private extension HomeView {

    var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(PiperTheme.faint)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(PiperTheme.ui(14))
                .focused($focused)
                .onSubmit(runSelection)
                .accessibilityLabel("Search files and actions")
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(PiperTheme.faint) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: Self.contentWidth, height: 30)
        .background(PiperTheme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(focused ? PiperTheme.focusRing : .clear, lineWidth: 3)
                .padding(-2)
        }
    }

    var recentList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("RECENT")
                    .font(PiperTheme.ui(11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(PiperTheme.secondary)
                Spacer()
                Button("Show All", action: showBrowser).buttonStyle(.text)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
            ForEach(recent) { file in
                Button { openFile(file.id) } label: {
                    TimelineCell(
                        file: file,
                        rootName: model.vault.root.lastPathComponent,
                        isUnread: model.isUnread(file)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: Self.recentWidth, alignment: .leading)
        .padding(.horizontal, AppDefaults.Reader.horizontalInset)
        .padding(.top, 44)
    }
}

// MARK: - Content

private extension HomeView {

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

}

// MARK: - Running

private extension HomeView {

    func runSelection() {
        guard suggestions.indices.contains(selection) else { return }
        run(suggestions[selection])
    }

    /// Runs one row. The row carries what it means, so nothing here reads the title.
    func run(_ suggestion: HomeSuggestion) {
        switch suggestion.target {
        case .file(let file):
            openFile(file.path)
        case .action(let action):
            action.run()
        case .searchEverything(let query):
            searchFiles(query)
        }
        text = ""
    }

    func browseFiles() {
        showBrowser()
    }
}
