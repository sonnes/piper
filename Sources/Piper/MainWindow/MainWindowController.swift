import AppKit
import SwiftUI
import Vault

/// Owns the main window and its four panes.
///
/// The window holds an `NSSplitViewController` with one view controller per
/// pane. A pane never calls another pane. Each one reports upward through a
/// delegate protocol, and this controller decides what happens next.
///
/// The sidebar selection decides what the other panes hold. The home page and
/// the capture inbox are rows of the sidebar, so the source list stays in place
/// whichever one the reader picks. The home page fills the panes to the right,
/// because a search field needs the width.
@MainActor
final class MainWindowController: NSWindowController {

    // MARK: - Properties

    private let model: AppModel
    private var state = MainWindowState.restore()

    private let splitViewController = NSSplitViewController()
    private let sidebarViewController = SidebarViewController()
    private let fileListViewController = FileListViewController()
    private let detailViewController = DetailViewController()
    private let inspectorViewController = DetailViewController()
    private var listItem: NSSplitViewItem?
    private var inspectorItem: NSSplitViewItem?
    /// The text the toolbar search field hands to the home page.
    private var homeSeed = ""
    /// Changes with every seed, so that the home page takes the new text.
    private var homeIdentity = UUID()
    private var appliedPaneWidths = false

    /// True while the panes to the right of the sidebar hold the home page.
    private var showsHome: Bool { state.selection == .home }

    // MARK: - Initialization

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: AppDefaults.Window.mainSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        // The capture panel is also called Piper. Two windows with one name make
        // the Window menu unreadable, so the main window carries the folder name.
        window.title = "Piper Wiki"
        // The toolbar holds the controls of both panes, and a title in front of
        // them pushes the first group out over the file list.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        window.backgroundColor = PiperTheme.pageNS
        window.minSize = AppDefaults.Window.mainMinimumSize
        window.isReleasedWhenClosed = false

        buildSplitView()
        buildToolbar(for: window)
        window.contentViewController = splitViewController
        window.setContentSize(AppDefaults.Window.mainSize)

        splitViewController.splitView.autosaveName = AppDefaults.WindowName.mainSplitView

        if !window.setFrameUsingName(NSWindow.FrameAutosaveName(AppDefaults.WindowName.mainWindow)) {
            window.center()
        }
        window.setFrameAutosaveName(NSWindow.FrameAutosaveName(AppDefaults.WindowName.mainWindow))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - API

    func show() {
        window?.title = "Piper Wiki — " + model.vault.root.lastPathComponent
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshPanes()
        model.reload()
    }

    /// Opens the panes at their default widths.
    ///
    /// A divider position needs a laid-out split view, so this runs when the
    /// browser first takes the window. A saved arrangement wins, because the
    /// reader dragged it.
    func applyDefaultPaneWidths() {
        guard !appliedPaneWidths else { return }
        appliedPaneWidths = true
        let key = "NSSplitView Subview Frames " + AppDefaults.WindowName.mainSplitView
        guard UserDefaults.standard.object(forKey: key) == nil else { return }
        let split = splitViewController.splitView
        split.layoutSubtreeIfNeeded()
        split.setPosition(state.sidebarWidth, ofDividerAt: 0)
        split.setPosition(state.sidebarWidth + state.listWidth, ofDividerAt: 1)
    }

    /// Takes the window off the screen. An unsaved change stays in the editor,
    /// because the window closes nothing.
    func hide() {
        window?.orderOut(nil)
    }

    /// Shows the files in place of the home page.
    func showBrowser() {
        guard showsHome else { return }
        select(.folder(state.selectedFolder))
    }

    /// Shows the home page in the panes beside the sidebar.
    ///
    /// The toolbar search field passes its text as the seed, so a command that
    /// starts in the browser finishes in the suggestion list of the home page.
    func showHome(seed: String = "") {
        homeSeed = seed
        homeIdentity = UUID()
        select(.home)
    }

    /// Records what the sidebar picked and redraws the panes for it.
    private func select(_ selection: SidebarSelection) {
        state.selection = selection
        state.selectedFile = model.selectedDocument
        state.save()
        applyDefaultPaneWidths()
        refreshPanes()
    }

    /// Closes a sheet, so that a modal alert can appear over this window.
    func dismissAttachedSheet() {
        guard let window, let sheet = window.attachedSheet else { return }
        window.endSheet(sheet)
        sheet.orderOut(nil)
    }

    /// Redraws every pane from the current selection and model.
    ///
    /// The home page needs the width of the window, so its selection collapses
    /// the file list. The inbox holds captures, which carry no file details, so
    /// it collapses the inspector.
    func refreshPanes() {
        sidebarViewController.setContent(SidebarPane(
            model: model,
            selection: state.selection,
            restored: state.expandedFolders.map(Set.init),
            select: { [weak self] selection in
                guard let self else { return }
                sidebarViewController.select(selection)
            },
            expansionChanged: { [weak self] folders in
                guard let self else { return }
                state.expandedFolders = folders.sorted()
                state.save()
            }
        ))

        switch state.selection {
        case .home:
            detailViewController.setContent(homeContent)
        case .inbox:
            fileListViewController.setContent(InboxListView(model: model, selected: state.selectedNote) { [weak self] note in
                guard let self else { return }
                fileListViewController.selectNote(note.id)
            })
            detailViewController.setContent(NoteDetailPane(model: model, id: state.selectedNote).routeSheets(model))
        case .folder(let path):
            fileListViewController.setContent(FileListView(model: model, folder: path) { [weak self] file in
                guard let self else { return }
                fileListViewController.selectFile(file.id)
            })
            detailViewController.setContent(DetailPane(model: model).routeSheets(model))
        }

        inspectorViewController.setContent(InspectorPane(model: model))
        listItem?.isCollapsed = showsHome
        inspectorItem?.isCollapsed = state.selection != .folder(state.selectedFolder)
            || !AppDefaults.shared.inspectorVisible
    }

    /// The home page, with the seed the toolbar search field left behind.
    private var homeContent: some View {
        HomeView(
            model: model,
            initialText: homeSeed,
            openFile: { [weak self] path in self?.open(path) },
            showBrowser: { [weak self] in self?.showBrowser() }
        )
        .id(homeIdentity)
        .routeSheets(model)
    }

    /// Opens a file and shows the folder that holds it.
    private func open(_ path: String) {
        state.selectedFile = path
        model.openDocument(path)
        select(.folder((path as NSString).deletingLastPathComponent))
    }
}

// MARK: - Building the window

private extension MainWindowController {

    func buildSplitView() {
        sidebarViewController.delegate = self
        fileListViewController.delegate = self

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.minimumThickness = AppDefaults.Sidebar.minimumThickness
        sidebarItem.canCollapse = true
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(260)

        let list = NSSplitViewItem(contentListWithViewController: fileListViewController)
        list.minimumThickness = 240
        list.holdingPriority = NSLayoutConstraint.Priority(255)
        if #available(macOS 26.0, *) { list.automaticallyAdjustsSafeAreaInsets = true }
        // The home page takes the width of the window, so its selection
        // collapses this pane instead of squeezing it.
        list.canCollapse = true
        listItem = list

        let detailItem = NSSplitViewItem(viewController: detailViewController)
        detailItem.minimumThickness = AppDefaults.Window.detailMinimumThickness

        let inspector = NSSplitViewItem(viewController: inspectorViewController)
        inspector.minimumThickness = 250
        inspector.maximumThickness = 320
        inspector.canCollapse = true
        inspector.isCollapsed = !AppDefaults.shared.inspectorVisible
        inspectorItem = inspector

        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(list)
        splitViewController.addSplitViewItem(detailItem)
        splitViewController.addSplitViewItem(inspector)
        refreshPanes()
    }

    func buildToolbar(for window: NSWindow) {
        let toolbar = NSToolbar(identifier: Toolbar.browser)
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        toolbar.delegate = self
        window.toolbar = toolbar
    }
}

// MARK: - Toolbar

/// The toolbar of the window.
enum Toolbar {
    static let browser = NSToolbar.Identifier("BrowserToolbar")
}

extension NSToolbarItem.Identifier {
    static let home = NSToolbarItem.Identifier("home")
    static let navigate = NSToolbarItem.Identifier("navigate")
    static let commands = NSToolbarItem.Identifier("commands")
    static let inspector = NSToolbarItem.Identifier("inspector")
    static let capture = NSToolbarItem.Identifier("capture")
    static let settings = NSToolbarItem.Identifier("settings")
    static let search = NSToolbarItem.Identifier("search")
    static let refresh = NSToolbarItem.Identifier("refresh")
    static let folder = NSToolbarItem.Identifier("folder")
    static let readerSeparator = NSToolbarItem.Identifier("readerSeparator")
}

extension MainWindowController: NSToolbarDelegate {

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toggleSidebar, .refresh, .sidebarTrackingSeparator,
                .home, .folder, .flexibleSpace, .readerSeparator,
                .navigate, .capture, .commands, .inspector, .flexibleSpace, .search]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.space]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case .readerSeparator:
            return NSTrackingSeparatorToolbarItem(identifier: identifier,
                                                  splitView: splitViewController.splitView, dividerIndex: 1)
        case .home:
            return button(identifier, symbol: "house", label: "Home", action: #selector(goHome))
        case .navigate:
            return navigateItem()
        case .commands:
            return button(identifier, symbol: "terminal", label: "Commands And Skills", action: #selector(openCommands))
        case .inspector:
            return button(identifier, symbol: "sidebar.right", label: "Inspector", action: #selector(toggleInspector))
        case .capture:
            return button(identifier, symbol: "square.and.pencil",
                          label: "Capture Panel · ⌘1", action: #selector(openCapture))
        case .settings:
            return button(identifier, symbol: "gearshape", label: "Settings", action: #selector(openSettings))
        case .search:
            return searchItem()
        case .refresh:
            return button(identifier, symbol: "arrow.clockwise", label: "Refresh", action: #selector(refreshVault))
        case .folder:
            return folderItem()
        default:
            return nil
        }
    }

    /// The search field of the browser toolbar.
    ///
    /// Plain text filters the file list. A leading `/` or `>` belongs to the command parser, so
    /// the window shows the home page and hands the text to its suggestion list.
    ///
    private func searchItem() -> NSToolbarItem {
        let field = NSSearchField()
        field.placeholderString = "Search"
        field.sendsWholeSearchString = false
        field.sendsSearchStringImmediately = true
        field.stringValue = model.wikiQuery
        field.target = self
        field.action = #selector(search(_:))
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let item = NSToolbarItem(itemIdentifier: .search)
        item.view = field
        item.label = "Search"
        item.toolTip = "Search; / for commands, > for actions"
        item.visibilityPriority = .high
        return item
    }

    private func button(_ identifier: NSToolbarItem.Identifier,
                        symbol: String,
                        label: String,
                        action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.isBordered = true
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.label = label
        item.toolTip = label
        item.target = self
        item.action = action
        return item
    }

    /// The Wiki folder menu.
    private func folderItem() -> NSToolbarItem {
        let menu = NSMenu()
        menu.addItem(withTitle: "Choose Wiki Folder…", action: #selector(chooseFolder), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Reveal Wiki in Finder", action: #selector(revealFolder), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
        let item = NSMenuToolbarItem(itemIdentifier: .folder)
        item.isBordered = true
        item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Wiki Folder")
        item.label = "Wiki Folder"
        item.toolTip = "Wiki Folder"
        item.menu = menu
        return item
    }

    private func navigateItem() -> NSToolbarItem {
        let control = NSSegmentedControl(images: [
            NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back") ?? NSImage(),
            NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward") ?? NSImage()
        ], trackingMode: .momentary, target: self, action: #selector(navigate(_:)))
        let item = NSToolbarItem(itemIdentifier: .navigate)
        item.view = control
        item.label = "Back and Forward"
        return item
    }

    @objc private func goHome() { showHome() }

    @objc private func openCommands() { model.route = "commands" }

    @objc private func openCapture() { model.openPanel?() }

    @objc private func openSettings() { model.route = "settings" }

    @objc private func refreshVault() { model.reload(); refreshPanes() }

    @objc private func chooseFolder() { model.chooseWiki() }

    @objc private func revealFolder() { NSWorkspace.shared.open(model.vault.root) }

    @objc private func search(_ sender: NSSearchField) {
        let text = sender.stringValue
        guard !text.hasPrefix("/"), !text.hasPrefix(">") else {
            sender.stringValue = ""
            model.wikiQuery = ""
            showHome(seed: text)
            return
        }
        model.wikiQuery = text
    }

    @objc private func toggleInspector() {
        guard let inspectorItem else { return }
        inspectorItem.isCollapsed.toggle()
        AppDefaults.shared.inspectorVisible = !inspectorItem.isCollapsed
    }

    @objc private func navigate(_ sender: NSSegmentedControl) {
        model.navigate(sender.selectedSegment == 0 ? -1 : 1)
        refreshPanes()
    }
}

/// The detail pane while the inbox is selected.
private struct NoteDetailPane: View {
    @Bindable var model: AppModel
    let id: UUID?

    var body: some View {
        if let id, let note = model.store.notes.first(where: { $0.id == id }) {
            NoteDetail(model: model, note: note)
                .id(note.id)
        } else {
            Text("No Selection")
                .font(PiperTheme.ui(18))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PiperTheme.page)
        }
    }
}

/// The right column: file details, outline, and backlinks.
private struct InspectorPane: View {
    @Bindable var model: AppModel

    var body: some View {
        if let document = model.currentDocument {
            WikiInspector(model: model, document: document, focus: {})
        } else {
            Color.clear
        }
    }
}

// MARK: - Pane delegates

extension MainWindowController: SidebarViewControllerDelegate {

    func sidebarViewController(_ controller: SidebarViewController, didSelect selection: SidebarSelection) {
        select(selection)
    }
}

extension MainWindowController: FileListViewControllerDelegate {

    func fileListViewController(_ controller: FileListViewController, didSelectFile path: String) {
        state.selectedFile = path
        state.save()
        model.openDocument(path)
        refreshPanes()
    }

    func fileListViewController(_ controller: FileListViewController, didSelectNote id: UUID) {
        state.selectedNote = id
        state.save()
        refreshPanes()
    }
}

// MARK: - Pane content

/// The sidebar pane. It owns the expansion set, because `SidebarView` is
/// removed from the hierarchy when the reader hides it.
///
/// The set comes back from the saved window state. A window that has not opened
/// before has none, so the sidebar opens every folder.
private struct SidebarPane: View {
    @Bindable var model: AppModel
    let selection: SidebarSelection
    let restored: Set<String>?
    let select: (SidebarSelection) -> Void
    let expansionChanged: (Set<String>) -> Void

    @State private var expanded: Set<String> = []
    @State private var seeded = false

    var body: some View {
        SidebarView(model: model, expanded: $expanded, selection: selection, select: select)
            .onAppear(perform: seed)
            .onChange(of: model.files.map(\.id)) { _, _ in seed() }
            .onChange(of: expanded) { _, folders in
                guard seeded else { return }
                expansionChanged(folders)
            }
    }

    private func seed() {
        guard !seeded, !model.files.isEmpty else { return }
        expanded = restored ?? SidebarView.folders(of: model.files, including: model.folders)
        seeded = true
    }
}

/// The detail pane. It holds the reading preferences, which belong to the view.
private struct DetailPane: View {
    @Bindable var model: AppModel

    @AppStorage(AppDefaults.Key.readerSize) private var readerSize = 18.0
    @AppStorage(AppDefaults.Key.readerTheme) private var readerTheme = WikiReadingTheme.paper
    @AppStorage(AppDefaults.Key.readerFont) private var readerFont = WikiReadingFont.sans
    @AppStorage(AppDefaults.Key.readerAppearance) private var readerAppearance = WikiReadingAppearance.system
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let document = model.currentDocument {
                if FilePresentation(document) != .markdown {
                    FilePreview(model: model, document: document)
                } else {
                    VStack(spacing: 0) {
                        DetailHeader(file: document, rootName: model.vault.root.lastPathComponent)
                        WikiEditor(model: model, document: document, fontSize: readerSize,
                                   fontName: readerFont.font(size: readerSize).fontName, paper: paper)
                        DetailStatusBar(path: path(of: document), words: words(of: document),
                                        hasChanges: model.wikiEdit?.hasChanges ?? false)
                    }
                    .background(paper)
                    .preferredColorScheme(readerAppearance.colorScheme)
                }
            } else {
                Text("No Selection")
                    .font(PiperTheme.ui(18))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PiperTheme.page)
            }
        }
        .onChange(of: model.currentDocument?.id, initial: true) { _, _ in
            model.markCurrentDocumentRead()
        }
    }

    private var paper: Color {
        Color(nsColor: readerTheme.background(dark: (readerAppearance.colorScheme ?? colorScheme) == .dark))
    }

    private func path(of document: VaultFile) -> String {
        let url = model.vault.root.appendingPathComponent(document.relativePath)
        return (url.path as NSString).abbreviatingWithTildeInPath
    }

    /// The length of what the reader sees. The editor text comes first, so the
    /// count follows a change before a save.
    private func words(of document: VaultFile) -> Int {
        let text = model.wikiEdit?.text ?? document.body
        return text.split(whereSeparator: \.isWhitespace).count
    }
}
