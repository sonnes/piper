import AppKit
import PiperTree
import SwiftUI

/// AppKit owns row geometry, selection, disclosure, and keyboard navigation.
struct SidebarOutline: NSViewRepresentable {
    let model: AppModel
    let unreadCounts: [String: Int]
    let sections: [SidebarSection]
    /// The folders that have Claude sessions.
    let sessionFolders: [SidebarSessionFolder]
    @Binding var expanded: Set<String>
    let selection: SidebarSelection
    let select: (SidebarSelection) -> Void
    let newSection: () -> Void
    let editSection: (String) -> Void
    let deleteSection: (String) -> Void

    /// The entry of the expansion set that records a collapsed Inbox. No
    /// folder path starts with this character, so the two cannot collide.
    static let inboxCollapsedKey = "\u{1}inbox"
    /// The section that the Inbox row itself stands for.
    static let inboxSection = "Inbox"

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("source"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .default
        outline.intercellSpacing = .zero
        outline.indentationPerLevel = AppDefaults.Sidebar.indent
        outline.floatsGroupRows = false
        outline.allowsMultipleSelection = false
        outline.allowsEmptySelection = true
        outline.allowsColumnReordering = false
        outline.backgroundColor = .clear
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.setAccessibilityLabel("Sources")

        let menu = NSMenu()
        menu.delegate = context.coordinator
        outline.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        context.coordinator.outline = outline
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update()
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        var parent: SidebarOutline
        weak var outline: NSOutlineView?
        private var root = Node.root(representedObject: "root")
        private var paths: [String] = []
        private var folders: [String] = []
        private var wikiPath = ""
        private var wikiPaths: [String] = []
        private var unreadCounts: [String: Int] = [:]
        private var sections: [SidebarSection] = []
        private var sessionFolders: [SidebarSessionFolder] = []
        private var updating = false

        init(_ parent: SidebarOutline) {
            self.parent = parent
            super.init()
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(sidebarSizeChanged),
                                                                name: .appleSideBarDefaultIconSizeChanged, object: nil)
        }

        deinit { DistributedNotificationCenter.default().removeObserver(self) }

        @objc private func sidebarSizeChanged() {
            // AppKit applies the new row size after the notification arrives.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.outline?.reloadData()
                self?.update()
            }
        }

        func update() {
            guard let outline else { return }
            updating = true
            defer { updating = false }
            let newPaths = parent.model.files.map(\.relativePath)
            if wikiPaths != parent.model.wikiPaths || newPaths != paths || folders != parent.model.folders || wikiPath != parent.model.wikiPath || unreadCounts != parent.unreadCounts || sections != parent.sections || sessionFolders != parent.sessionFolders {
                paths = newPaths
                folders = parent.model.folders
                wikiPath = parent.model.wikiPath
                wikiPaths = parent.model.wikiPaths
                unreadCounts = parent.unreadCounts
                sections = parent.sections
                sessionFolders = parent.sessionFolders
                root = Node.root(representedObject: "root")
                let library = Node(representedObject: "Library", parent: root)
                library.isGroupItem = true
                let inbox = Node(representedObject: SidebarSelection.inbox, parent: library)
                // Inbox itself is the first section, so it needs no child row.
                inbox.children = sections.filter { $0.name != SidebarOutline.inboxSection }
                    .map { Node(representedObject: SidebarSelection.section($0.name), parent: inbox) }
                library.children = [
                    Node(representedObject: SidebarSelection.home, parent: library),
                    inbox,
                    Node(representedObject: SidebarSelection.clipboard, parent: library),
                    Node(representedObject: SidebarSelection.archived, parent: library)
                ]
                let folderGroup = Node(representedObject: "Folders", parent: root)
                folderGroup.isGroupItem = true
                let wiki = PathTreeBuilder.tree(paths: paths, folders: folders, includingFiles: false)
                wiki.parent = folderGroup
                folderGroup.children = wikiPaths.map { path in
                    if path == wikiPath { return wiki }
                    return Node(representedObject: URL(fileURLWithPath: path), parent: folderGroup)
                }
                if sessionFolders.isEmpty {
                    root.children = [library, folderGroup]
                } else {
                    let claude = Node(representedObject: "Claude", parent: root)
                    claude.isGroupItem = true
                    claude.children = sessionFolders.map {
                        Node(representedObject: SidebarSelection.sessions($0.path), parent: claude)
                    }
                    root.children = [library, claude, folderGroup]
                }
                outline.reloadData()
            }

            func restore(_ node: Node) {
                if node.isGroupItem {
                    outline.expandItem(node)
                } else if node.representedObject as? SidebarSelection == .inbox {
                    if parent.expanded.contains(SidebarOutline.inboxCollapsedKey) { outline.collapseItem(node) }
                    else { outline.expandItem(node) }
                } else if let item = node.representedObject as? PathItem, item.isFolder {
                    if item.path.isEmpty || parent.expanded.contains(item.path) { outline.expandItem(node) }
                    else { outline.collapseItem(node) }
                }
                node.children.forEach(restore)
            }
            root.children.forEach(restore)
            let node = root.descendantNode { node in
                if let selection = node.representedObject as? SidebarSelection { return selection == parent.selection }
                guard !node.isGroupItem, let item = node.representedObject as? PathItem, item.isFolder else { return false }
                return parent.selection == .folder(item.path)
            }
            let row = node.map { outline.row(forItem: $0) } ?? -1
            if outline.selectedRow != row {
                if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
                else { outline.deselectAll(nil) }
            }
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            ((item as? Node) ?? root).children.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            ((item as? Node) ?? root).children[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? Node)?.hasChildNodes == true
        }

        func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
            (item as? Node)?.isGroupItem == true
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            (item as? Node)?.isGroupItem == false
        }

        func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
            guard let node = item as? Node else { return false }
            return !node.isGroupItem && (node.representedObject as? PathItem)?.path != ""
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? Node else { return nil }
            if node.isGroupItem {
                let label = NSTextField(labelWithString: node.representedObject as? String ?? (wikiPath as NSString).abbreviatingWithTildeInPath)
                label.font = .systemFont(ofSize: AppDefaults.Sidebar.headerFontSize, weight: .semibold)
                label.textColor = .secondaryLabelColor
                label.lineBreakMode = .byTruncatingHead
                if node.representedObject as? String == "Folders" {
                    let button = addButton("Add Folder", action: #selector(addFolder))
                    let header = NSStackView(views: [label, button])
                    header.spacing = AppDefaults.Sidebar.actionSpacing
                    header.edgeInsets.right = AppDefaults.Sidebar.trailingInset
                    label.setContentHuggingPriority(.defaultLow, for: .horizontal)
                    return header
                }
                return label
            }
            let identifier = NSUserInterfaceItemIdentifier("sourceCell")
            let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? SidebarCell) ?? SidebarCell()
            cell.identifier = identifier
            cell.addButton = node.representedObject as? SidebarSelection == .inbox
                ? addButton("New Section", action: #selector(newSection)) : nil
            if let item = node.representedObject as? PathItem {
                cell.configure(title: item.path.isEmpty ? parent.model.vault.root.lastPathComponent : item.name,
                               symbol: "folder", count: unreadCounts[item.path, default: 0],
                               rowSizeStyle: outlineView.effectiveRowSizeStyle)
                cell.toolTip = item.path.isEmpty ? wikiPath : item.path
            } else if let url = node.representedObject as? URL {
                cell.configure(title: url.lastPathComponent, symbol: "folder", count: 0,
                               rowSizeStyle: outlineView.effectiveRowSizeStyle)
                cell.toolTip = url.path
            } else if let selection = node.representedObject as? SidebarSelection {
                let row: (title: String, symbol: String, count: Int)
                switch selection {
                case .home: row = ("Home", "house", 0)
                case .inbox: row = ("Inbox", "tray", sections.reduce(0) { $0 + $1.count })
                case .section(let name): row = (name, "tray", sections.first { $0.name == name }?.count ?? 0)
                case .archived: row = ("Archived", "archivebox", 0)
                case .clipboard: row = ("Clipboard", "clipboard", 0)
                case .sessions(let path):
                    row = (URL(fileURLWithPath: path).lastPathComponent, "text.bubble",
                           sessionFolders.first { $0.path == path }?.attention ?? 0)
                case .allFiles, .folder: row = ("", "folder", 0)
                }
                cell.configure(title: row.title, symbol: row.symbol, count: row.count,
                               rowSizeStyle: outlineView.effectiveRowSizeStyle)
                cell.toolTip = nil
            }
            return cell
        }

        private func addButton(_ title: String, action: Selector) -> NSButton {
            let button = NSButton(title: "", target: self, action: action)
            button.image = NSImage(systemSymbolName: "plus", accessibilityDescription: title)
            button.isBordered = false
            button.toolTip = title
            button.setAccessibilityLabel(title)
            button.widthAnchor.constraint(equalToConstant: AppDefaults.Sidebar.addButtonSize).isActive = true
            button.heightAnchor.constraint(equalToConstant: AppDefaults.Sidebar.addButtonSize).isActive = true
            return button
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let outline, let node = outline.item(atRow: outline.selectedRow) as? Node else { return }
            if let url = node.representedObject as? URL {
                parent.model.changeWiki(to: url)
                update()
            } else if let selection = node.representedObject as? SidebarSelection {
                parent.select(selection)
            } else if let item = node.representedObject as? PathItem {
                parent.select(.folder(item.path))
            }
        }

        func outlineViewItemDidExpand(_ notification: Notification) { recordExpansion(notification, expanded: true) }
        func outlineViewItemDidCollapse(_ notification: Notification) { recordExpansion(notification, expanded: false) }

        private func recordExpansion(_ notification: Notification, expanded: Bool) {
            guard !updating, let node = notification.userInfo?["NSObject"] as? Node, !node.isGroupItem else { return }
            if node.representedObject as? SidebarSelection == .inbox {
                if expanded { parent.expanded.remove(SidebarOutline.inboxCollapsedKey) }
                else { parent.expanded.insert(SidebarOutline.inboxCollapsedKey) }
                return
            }
            guard let item = node.representedObject as? PathItem else { return }
            if expanded { parent.expanded.insert(item.path) } else { parent.expanded.remove(item.path) }
        }

        // MARK: Context menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            menu.addItem(withTitle: "New Section…", action: #selector(newSection), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Add Folder…", action: #selector(addFolder), keyEquivalent: "").target = self
            if let selection = clickedNode?.representedObject as? SidebarSelection, case .section(let name) = selection {
                menu.addItem(.separator())
                let edit = menu.addItem(withTitle: "Edit Section…", action: #selector(editSection(_:)), keyEquivalent: "")
                edit.target = self
                edit.representedObject = name
                let delete = menu.addItem(withTitle: "Delete Section…", action: #selector(deleteSection(_:)), keyEquivalent: "")
                delete.target = self
                delete.representedObject = name
            }
            guard let node = clickedNode, folderURL(of: node) != nil else { return }
            menu.addItem(.separator())
            menu.addItem(withTitle: "Reveal in Finder", action: #selector(revealInFinder), keyEquivalent: "").target = self
            if let path = topLevelFolderPath(of: node), wikiPaths.count > 1 {
                let remove = menu.addItem(withTitle: "Remove Folder", action: #selector(removeFolder(_:)), keyEquivalent: "")
                remove.target = self
                remove.representedObject = path
            }
        }

        private var clickedNode: Node? {
            guard let outline else { return nil }
            return outline.item(atRow: outline.clickedRow) as? Node
        }

        private func folderURL(of node: Node) -> URL? {
            if let url = node.representedObject as? URL { return url }
            guard let item = node.representedObject as? PathItem else { return nil }
            return item.path.isEmpty ? parent.model.vault.root : try? parent.model.vault.containedURL(item.path)
        }

        /// The stored path of a folder that sits directly under the Folders header.
        private func topLevelFolderPath(of node: Node) -> String? {
            if let url = node.representedObject as? URL { return wikiPaths.first { URL(fileURLWithPath: $0) == url } }
            if let item = node.representedObject as? PathItem, item.path.isEmpty { return wikiPath }
            return nil
        }

        @objc private func newSection() { parent.newSection() }

        @objc private func editSection(_ sender: NSMenuItem) {
            guard let section = sender.representedObject as? String else { return }
            parent.editSection(section)
        }

        @objc private func deleteSection(_ sender: NSMenuItem) {
            guard let section = sender.representedObject as? String else { return }
            parent.deleteSection(section)
        }

        @objc private func addFolder() { parent.model.chooseWiki() }

        @objc private func revealInFinder() {
            guard let node = clickedNode, let url = folderURL(of: node) else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }

        @objc private func removeFolder(_ sender: NSMenuItem) {
            guard let path = sender.representedObject as? String else { return }
            parent.model.removeWikiFolder(path)
            update()
        }
    }
}

private final class SidebarCell: NSTableCellView {
    private let title = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let countLabel = NSTextField(labelWithString: "")
    private let actions = NSStackView()
    var addButton: NSButton? {
        didSet {
            oldValue?.removeFromSuperview()
            if let addButton { actions.addArrangedSubview(addButton) }
        }
    }
    private lazy var iconWidth = icon.widthAnchor.constraint(equalToConstant: AppDefaults.Sidebar.metrics(for: .medium).imageSize)
    private lazy var iconHeight = icon.heightAnchor.constraint(equalToConstant: AppDefaults.Sidebar.metrics(for: .medium).imageSize)

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateColors() }
    }

    init() {
        super.init(frame: .zero)
        title.lineBreakMode = .byTruncatingTail
        title.usesSingleLineMode = true
        title.maximumNumberOfLines = 1
        title.allowsDefaultTighteningForTruncation = false
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        countLabel.font = .monospacedDigitSystemFont(ofSize: AppDefaults.Sidebar.countFontSize, weight: .regular)
        icon.imageScaling = .scaleProportionallyUpOrDown
        actions.spacing = AppDefaults.Sidebar.actionSpacing
        actions.addArrangedSubview(countLabel)
        for view in [title, icon, actions] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            view.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconWidth,
            iconHeight,
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: AppDefaults.Sidebar.imageMarginRight),
            title.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -AppDefaults.Sidebar.countMarginLeft),
            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AppDefaults.Sidebar.trailingInset)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(title: String, symbol: String, count: Int, rowSizeStyle: NSTableView.RowSizeStyle) {
        let metrics = AppDefaults.Sidebar.metrics(for: rowSizeStyle)
        self.title.stringValue = title
        self.title.font = .systemFont(ofSize: metrics.fontSize)
        iconWidth.constant = metrics.imageSize
        iconHeight.constant = metrics.imageSize
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        countLabel.stringValue = count > 0 ? count.formatted() : ""
        countLabel.setAccessibilityLabel(count > 0 ? "\(count) unread" : nil)
        updateColors()
    }

    private func updateColors() {
        let emphasized = backgroundStyle == .emphasized
        title.textColor = emphasized ? .selectedControlTextColor : .labelColor
        countLabel.textColor = emphasized ? .selectedControlTextColor : .secondaryLabelColor
        icon.contentTintColor = emphasized ? .selectedControlTextColor : PiperTheme.accentNS
    }
}
