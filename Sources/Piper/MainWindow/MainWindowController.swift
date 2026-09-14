import AppKit
import SwiftUI
import Vault

/// Owns the main window: the home page and the three-pane browser.
///
/// The window holds an `NSSplitViewController` with one view controller per
/// pane. A pane never calls another pane. Each one reports upward through a
/// delegate protocol, and this controller decides what happens next.
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
    private let homeViewController = HomeViewController()
    private var inspectorItem: NSSplitViewItem?

    /// True while the window shows the home page rather than the browser.
    private var showsHome: Bool { window?.contentViewController === homeViewController }

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
        window.titlebarAppearsTransparent = true
        window.tabbingMode = .disallowed
        window.backgroundColor = PiperTheme.pageNS
        window.minSize = AppDefaults.Window.mainMinimumSize
        window.isReleasedWhenClosed = false

        buildSplitView()
        buildToolbar(for: window)
        window.contentViewController = splitViewController
        installHome()
        window.setContentSize(AppDefaults.Window.mainSize)

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

    /// Puts the home page back over the split view.
    func showHome() {
        guard !showsHome else { return }
        installHome()
        state.showsHome = true
        state.save()
    }

    /// Closes a sheet, so that a modal alert can appear over this window.
    func dismissAttachedSheet() {
        guard let window, let sheet = window.attachedSheet else { return }
        window.endSheet(sheet)
        sheet.orderOut(nil)
    }

    /// Redraws every pane from the current model.
    func refreshPanes() {
        sidebarViewController.setContent(SidebarPane(model: model) { [weak self] folder in
            guard let self else { return }
            sidebarViewController(sidebarViewController, didSelectFolder: folder)
        })
        fileListViewController.setContent(FileListView(model: model, folder: state.selectedFolder) { [weak self] file in
            guard let self else { return }
            fileListViewController(fileListViewController, didSelectFile: file.id)
        })
        detailViewController.setContent(DetailPane(model: model).routeSheets(model))
        inspectorViewController.setContent(InspectorPane(model: model))
        homeViewController.setContent(HomeView(model: model).routeSheets(model))
    }
}

// MARK: - Building the window

private extension MainWindowController {

    func buildSplitView() {
        sidebarViewController.delegate = self
        fileListViewController.delegate = self
        homeViewController.delegate = self

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.minimumThickness = AppDefaults.Sidebar.minimumThickness
        sidebarItem.canCollapse = true

        let listItem = NSSplitViewItem(contentListWithViewController: fileListViewController)
        listItem.minimumThickness = 240

        let detailItem = NSSplitViewItem(viewController: detailViewController)
        detailItem.minimumThickness = AppDefaults.Window.detailMinimumThickness

        let inspector = NSSplitViewItem(viewController: inspectorViewController)
        inspector.minimumThickness = 250
        inspector.maximumThickness = 320
        inspector.canCollapse = true
        inspector.isCollapsed = !AppDefaults.shared.inspectorVisible
        inspectorItem = inspector

        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(listItem)
        splitViewController.addSplitViewItem(detailItem)
        splitViewController.addSplitViewItem(inspector)
        refreshPanes()
    }

    /// Shows the home page in place of the split view.
    ///
    /// Piper opens on a home page, so the window swaps its
    /// content view controller. The split view controller stays alive, and the
    /// panes keep their state. A subview pinned over the split view would fight
    /// autolayout and collapse the window to the height of its content.
    func installHome() {
        guard !showsHome else { return }
        homeViewController.setContent(HomeView(model: model).routeSheets(model))
        swapContent(to: homeViewController)
    }

    func removeHome() {
        guard showsHome else { return }
        swapContent(to: splitViewController)
        state.showsHome = false
        state.save()
    }

    /// Replaces the content and keeps the window where the reader put it.
    private func swapContent(to controller: NSViewController) {
        guard let window else { return }
        let frame = window.frame
        window.contentViewController = controller
        window.setFrame(frame, display: true)
    }

    func buildToolbar(for window: NSWindow) {
        let toolbar = NSToolbar(identifier: "MainWindowToolbar")
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.displayMode = .iconOnly
        toolbar.delegate = self
        window.toolbar = toolbar
    }
}

// MARK: - Toolbar

extension NSToolbarItem.Identifier {
    static let home = NSToolbarItem.Identifier("home")
    static let navigate = NSToolbarItem.Identifier("navigate")
    static let commands = NSToolbarItem.Identifier("commands")
    static let inspector = NSToolbarItem.Identifier("inspector")
}

extension MainWindowController: NSToolbarDelegate {

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.home, .navigate, .flexibleSpace, .commands, .inspector]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.space]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case .home:
            return button(identifier, symbol: "house", label: "Home", action: #selector(goHome))
        case .navigate:
            return navigateItem()
        case .commands:
            return button(identifier, symbol: "terminal", label: "Commands And Skills", action: #selector(openCommands))
        case .inspector:
            return button(identifier, symbol: "sidebar.right", label: "Inspector", action: #selector(toggleInspector))
        default:
            return nil
        }
    }

    private func button(_ identifier: NSToolbarItem.Identifier,
                        symbol: String,
                        label: String,
                        action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.label = label
        item.toolTip = label
        item.target = self
        item.action = action
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

    func sidebarViewController(_ controller: SidebarViewController, didSelectFolder folder: String) {
        state.selectedFolder = folder
        state.save()
        removeHome()
        refreshPanes()
    }

    func sidebarViewControllerDidRequestHome(_ controller: SidebarViewController) {
        showHome()
    }
}

extension MainWindowController: FileListViewControllerDelegate {

    func fileListViewController(_ controller: FileListViewController, didSelectFile path: String) {
        state.selectedFile = path
        state.save()
        removeHome()
        model.openDocument(path)
        refreshPanes()
    }
}

extension MainWindowController: HomeViewControllerDelegate {

    func homeViewController(_ controller: HomeViewController, didOpenFile path: String) {
        state.selectedFile = path
        state.selectedFolder = (path as NSString).deletingLastPathComponent
        state.save()
        removeHome()
        model.openDocument(path)
        refreshPanes()
    }
}

// MARK: - Pane content

/// The sidebar pane. It owns the expansion set and the search focus, because
/// `SidebarView` is removed from the hierarchy when the reader hides it.
private struct SidebarPane: View {
    @Bindable var model: AppModel
    let selectFolder: (String) -> Void

    @State private var expanded: Set<String> = []
    @State private var seeded = false
    @FocusState private var searching: Bool

    var body: some View {
        SidebarView(model: model, expanded: $expanded, searching: $searching, selectFolder: selectFolder)
            .onAppear(perform: seed)
            .onChange(of: model.files.map(\.id)) { _, _ in seed() }
    }

    private func seed() {
        guard !seeded, !model.files.isEmpty else { return }
        expanded = SidebarView.folders(of: model.files)
        seeded = true
    }
}

/// The detail pane. It holds the reading preferences, which belong to the view.
private struct DetailPane: View {
    @Bindable var model: AppModel

    @AppStorage(AppDefaults.Key.readerSize) private var readerSize = 18.0
    @AppStorage(AppDefaults.Key.readerTheme) private var readerTheme = WikiReadingTheme.paper
    @AppStorage(AppDefaults.Key.readerFont) private var readerFont = WikiReadingFont.mono
    @AppStorage(AppDefaults.Key.readerAppearance) private var readerAppearance = WikiReadingAppearance.system
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let document = model.currentDocument {
            WikiEditor(model: model, document: document, fontSize: readerSize,
                       fontName: readerFont.font(size: readerSize).fontName, paper: paper)
        } else {
            ContentUnavailableView {
                Label("Open a File", systemImage: "doc.text")
            } description: {
                Text("Choose a file from the list, or search from the home page.")
            }
        }
    }

    private var paper: Color {
        Color(nsColor: readerTheme.background(dark: (readerAppearance.colorScheme ?? colorScheme) == .dark))
    }
}
