import AppKit
import SwiftUI
import Vault

/// Owns the main window and its three panes.
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
    private var listItem: NSSplitViewItem?
    /// The initial query for Home.
    private var homeSeed = ""
    /// Changes with every seed, so that the home page takes the new text.
    private var homeIdentity = UUID()
    private var appliedPaneWidths = false
    /// The last section that the sidebar selected. A new value scrolls the list.
    private var sectionScroll: SectionScroll?
    private var viewModeControl: NSSegmentedControl?
    private var doneItem: NSToolbarItem?

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
        NotificationCenter.default.addObserver(self, selector: #selector(vaultChanged),
                                               name: .vaultPathDidChange, object: model)

        // The title names what the sidebar selected, as in Mail. The subtitle
        // says where it lives.
        window.title = "Piper"
        window.titleVisibility = .visible
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
    /// The seed supplies the initial query.
    func showHome(seed: String = "") {
        homeSeed = seed
        homeIdentity = UUID()
        select(.home)
    }

    /// Records what the sidebar picked and redraws the panes for it.
    private func select(_ selection: SidebarSelection) {
        if case .folder = selection, selection != state.selection { model.wikiQuery = "" }
        if selection.showsCaptures != state.selection.showsCaptures || selection == .clipboard || state.selection == .clipboard {
            model.store.query = ""
            model.store.selection.removeAll()
        }
        switch selection {
        case .section(let name):
            if name != model.store.activeSection { model.store.chooseSection(name) }
            sectionScroll = SectionScroll(section: name)
        case .inbox:
            let section = model.store.sections.contains(SidebarOutline.inboxSection)
                ? SidebarOutline.inboxSection : model.store.sections.first
            if let section {
                if section != model.store.activeSection { model.store.chooseSection(section) }
                sectionScroll = SectionScroll(section: section)
            }
        default:
            break
        }
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
    /// the file list.
    func refreshPanes() {
        observeTitle()
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
        ).id(model.vault.root))

        switch state.selection {
        case .home:
            detailViewController.setContent(homeContent)
        case .inbox, .section, .clipboard:
            let clipboard = state.selection == .clipboard
            fileListViewController.setContent(CaptureView(
                model: model, embedded: true,
                content: clipboard ? .clipboard : .sections,
                scroll: clipboard ? nil : sectionScroll,
                acceptsKeyboard: { [weak self] window in
                    guard let self, state.selection.showsCaptures, window === self.window else { return false }
                    if window.firstResponder === fileListViewController { return true }
                    guard let responder = window.firstResponder as? NSView else { return false }
                    return responder.isDescendant(of: fileListViewController.view)
                },
                focusNotes: { [weak self] in
                    guard let self else { return }
                    window?.makeFirstResponder(fileListViewController)
                },
                selectCapture: { [weak self] id in
                    guard let self, state.selection.showsCaptures else { return }
                    fileListViewController.selectNote(id)
                }
            ))
            detailViewController.setContent(NoteDetailPane(model: model, id: clipboard ? nil : state.selectedNote).routeSheets(model))
        case .folder, .allFiles:
            let path: String? = state.selection == .allFiles ? nil : state.selection.folder
            fileListViewController.setContent(FileListView(model: model, folder: path) { [weak self] file in
                guard let self else { return }
                fileListViewController.selectFile(file.id)
            })
            detailViewController.setContent(DetailPane(model: model).routeSheets(model))
        }

        listItem?.isCollapsed = showsHome
        updateToolbarState()
    }

    /// Keeps the title current. The counts in the subtitle change with the
    /// notes and the files, so the title updates when the model does.
    private func observeTitle() {
        withObservationTracking {
            updateTitle()
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.observeTitle() }
        }
    }

    /// Names the sidebar selection in the title bar, with a count under it.
    private func updateTitle() {
        guard window != nil else { return }
        let store = model.store
        switch state.selection {
        case .home:
            setTitle("Home", (model.vault.root.path as NSString).abbreviatingWithTildeInPath)
        case .inbox:
            setTitle("Inbox", Self.count(store.notes.count, "note") + " in " + Self.count(store.sections.count, "section"))
        case .section(let name):
            setTitle(name, Self.count(store.notes.filter { $0.section == name }.count, "note"))
        case .clipboard:
            setTitle("Clipboard", Self.count(model.clipboard.entries.count, "copy", "copies") + " · not saved")
        case .allFiles:
            setTitle("All Files", fileCount(model.files))
        case .folder(let path):
            let name = path.isEmpty ? model.vault.root.lastPathComponent : (path as NSString).lastPathComponent
            setTitle(name, fileCount(model.files.filter { $0.folder == path }))
        }
    }

    private func setTitle(_ title: String, _ subtitle: String) {
        if window?.title != title { window?.title = title }
        if window?.subtitle != subtitle { window?.subtitle = subtitle }
    }

    private func fileCount(_ files: [VaultFile]) -> String {
        let unread = files.filter { model.isUnread($0) }.count
        let total = files.isEmpty ? "No files" : Self.count(files.count, "file")
        return unread > 0 ? total + " · \(unread) unread" : total
    }

    private static func count(_ value: Int, _ one: String, _ many: String? = nil) -> String {
        "\(value) " + (value == 1 ? one : many ?? one + "s")
    }

    /// Enables the toolbar controls that act on the current selection, and
    /// hides the ones that have no meaning there.
    private func updateToolbarState() {
        let showsFile = !state.selection.showsCaptures && !showsHome && model.currentDocument.map {
            FilePresentation.sourceText(for: $0) != nil
        } == true
        let showsFiles = !state.selection.showsCaptures && !showsHome
        let showsNotes = state.selection.showsCaptures && state.selection != .clipboard
        if #available(macOS 15.0, *), let items = window?.toolbar?.items {
            for item in items {
                if item.itemIdentifier == .viewMode { item.isHidden = !showsFiles }
                if item.itemIdentifier == .markDone { item.isHidden = !showsNotes }
            }
        }
        viewModeControl?.isEnabled = showsFile
        viewModeControl?.selectedSegment = model.showsFileSource ? 1 : 0
        let note = state.selectedNote.flatMap { id in model.store.notes.first { $0.id == id } }
        let canComplete = state.selection.showsCaptures && state.selection != .clipboard && note != nil
        doneItem?.isEnabled = canComplete
        doneItem?.image = NSImage(systemSymbolName: note?.isDone == true ? "checkmark.circle.fill" : "checkmark.circle",
                                  accessibilityDescription: nil)
        doneItem?.label = note?.isDone == true ? "Reopen" : "Mark as Done"
        doneItem?.toolTip = doneItem?.label
    }

    /// The Home page and its initial query.
    private var homeContent: some View {
        HomeView(
            model: model,
            initialText: homeSeed,
            openFile: { [weak self] path in self?.open(path) },
            showBrowser: { [weak self] in self?.showBrowser() },
            searchFiles: { [weak self] query in
                guard let self else { return }
                model.wikiQuery = query
                select(.allFiles)
            }
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

        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(list)
        splitViewController.addSplitViewItem(detailItem)
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
    static let navigate = NSToolbarItem.Identifier("navigate")
    static let capture = NSToolbarItem.Identifier("capture")
    static let viewMode = NSToolbarItem.Identifier("viewMode")
    static let markDone = NSToolbarItem.Identifier("markDone")
    static let more = NSToolbarItem.Identifier("more")
    static let readerSeparator = NSToolbarItem.Identifier("readerSeparator")
}

extension MainWindowController: NSToolbarDelegate {

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator,
         .flexibleSpace, .capture, .readerSeparator,
         .navigate, .flexibleSpace, .viewMode, .markDone, .more]
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
        case .navigate:
            return navigateItem()
        case .capture:
            return button(identifier, symbol: "square.and.pencil",
                          label: "New Capture · ⌘1", action: #selector(openCapture))
        case .viewMode:
            return viewModeItem()
        case .markDone:
            let item = button(identifier, symbol: "checkmark.circle", label: "Mark as Done", action: #selector(toggleDone))
            item.autovalidates = false
            doneItem = item
            updateToolbarState()
            return item
        case .more:
            return moreItem()
        default:
            return nil
        }
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

    /// Preview and Source for a text file.
    private func viewModeItem() -> NSToolbarItem {
        let control = NSSegmentedControl(labels: ["Preview", "Source"], trackingMode: .selectOne,
                                         target: self, action: #selector(changeViewMode(_:)))
        control.controlSize = .regular
        control.selectedSegment = model.showsFileSource ? 1 : 0
        control.setToolTip("Show the formatted file", forSegment: 0)
        control.setToolTip("Show the text of the file", forSegment: 1)
        viewModeControl = control
        let item = NSToolbarItem(itemIdentifier: .viewMode)
        item.view = control
        item.label = "View"
        updateToolbarState()
        return item
    }

    /// Actions that apply to the whole window.
    private func moreItem() -> NSToolbarItem {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Section…", action: #selector(newSection), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Add Folder…", action: #selector(chooseFolder), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Reveal in Finder", action: #selector(revealFolder), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh", action: #selector(refreshVault), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
        let item = NSMenuToolbarItem(itemIdentifier: .more)
        item.isBordered = true
        item.showsIndicator = false
        item.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "More")
        item.label = "More"
        item.toolTip = "More"
        item.menu = menu
        return item
    }

    private func navigateItem() -> NSToolbarItem {
        let control = NSSegmentedControl(images: [
            NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back") ?? NSImage(),
            NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward") ?? NSImage()
        ], trackingMode: .momentary, target: self, action: #selector(navigate(_:)))
        control.segmentStyle = .separated
        let item = NSToolbarItem(itemIdentifier: .navigate)
        item.view = control
        item.label = "Back and Forward"
        return item
    }

    @objc private func openCapture() { model.openPanel?() }

    @objc private func openSettings() { model.openSettings?() }

    @objc private func refreshVault() { model.reload(); refreshPanes() }

    @objc private func chooseFolder() { model.chooseWiki() }

    @objc private func newSection() {
        guard let window else { return }
        let sheet = NSHostingController(rootView: NewSectionSheet(sections: model.store.sections) { [weak self, weak window] name in
            guard let self, model.store.chooseSection(name) else { return }
            if let sheet = window?.attachedSheet { window?.endSheet(sheet) }
            select(.section(model.store.activeSection))
        })
        window.contentViewController?.presentAsSheet(sheet)
    }

    @objc private func toggleDone() {
        guard let id = state.selectedNote else { return }
        model.store.toggleDone(id)
        updateToolbarState()
    }

    @objc private func changeViewMode(_ sender: NSSegmentedControl) {
        model.showsFileSource = sender.selectedSegment == 1
        refreshPanes()
    }

    @objc private func vaultChanged() {
        state.resetForVault()
        state.save()
        homeSeed = ""
        homeIdentity = UUID()
        refreshPanes()
    }

    @objc private func revealFolder() { NSWorkspace.shared.open(model.vault.root) }

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
            NoSelection()
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

    func fileListViewController(_ controller: FileListViewController, didSelectNote id: UUID?) {
        state.selectedNote = id
        state.save()
        detailViewController.setContent(NoteDetailPane(model: model, id: id).routeSheets(model))
        updateToolbarState()
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
                let source = FilePresentation.sourceText(for: document, markdown: model.wikiEdit?.markdown)
                if model.showsFileSource, let source {
                    PlainTextPreview(text: source)
                } else if FilePresentation(document) != .markdown {
                    FilePreview(model: model, document: document)
                } else {
                    VStack(spacing: 0) {
                        DetailHeader(file: document, hasChanges: model.wikiEdit?.hasChanges ?? false)
                        WikiEditor(model: model, document: document, fontSize: readerSize,
                                   fontName: readerFont.font(size: readerSize).fontName, paper: paper)
                    }
                    .background(paper)
                    .preferredColorScheme(readerAppearance.colorScheme)
                }
            } else {
                NoSelection()
            }
        }
        .onChange(of: model.currentDocument?.id, initial: true) { _, _ in
            model.markCurrentDocumentRead()
        }
    }

    private var paper: Color {
        Color(nsColor: readerTheme.background(dark: (readerAppearance.colorScheme ?? colorScheme) == .dark))
    }
}
