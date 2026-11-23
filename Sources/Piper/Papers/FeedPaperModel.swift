import AppKit
import Captures
import Feeds

/// One item that a reader paper shows.
enum PaperItem: Hashable {
    /// A capture, by its id. A link capture shows its Reader, Web, and Notes tabs.
    case note(UUID)
    /// A feed article, by its id.
    case article(String)
    /// The open file of `AppModel`. Only one file paper exists, because the editor page is shared.
    case file
    /// An agent session, by its id.
    case session(UUID)
    /// A new agent session in a folder, by the absolute path of the folder.
    case newSession(String)
}

/// What the rows of the feed paper show about the papers on the desk.
///
/// A row of an item that is open as a reader paper shows a dashed slot. A
/// row flashes when its paper goes back. The views of the feed paper find
/// this object in their environment. The capture panel has none.
@MainActor @Observable
final class DeskMarks {
    /// One flash of a row.
    struct Flash: Equatable {
        let item: PaperItem
        let id = UUID()
    }

    /// The items that are open as reader papers.
    var open: Set<PaperItem> = []
    /// The path of the file in the file paper, while the file paper is open.
    var openFile: String?
    /// The last item whose paper went back.
    var flash: Flash?
    /// True while the feed paper has the keyboard focus.
    var feedFocused = false
    /// The item of the reader paper with the keyboard focus.
    var focusedPaper: PaperItem?

    func isOpen(_ item: PaperItem) -> Bool { open.contains(item) }

    func isOpenFile(_ path: String) -> Bool { openFile == path && open.contains(.file) }

    func flashes(_ item: PaperItem) -> UUID? { flash?.item == item ? flash?.id : nil }
}

/// The state of the feed paper that its views read and change.
///
/// A tab click shows the index of the tab. A pick on the index shows the
/// scoped list. Escape, a click on the active tab, or Back to the List shows
/// the list again.
@MainActor @Observable
final class FeedPaperModel {

    // MARK: - Properties

    let model: AppModel
    var state: PaperDeskState {
        didSet { if state != oldValue { state.save(to: defaults) } }
    }
    /// True while the paper shows the index of the active tab in place of the list.
    var showsIndex = false {
        didSet { if showsIndex && !oldValue { indexCursor = currentEntry } }
    }
    /// The row of the index that Return picks. Up Arrow and Down Arrow move it.
    var indexCursor: IndexEntry?
    /// The open papers and the flash of a row.
    let marks = DeskMarks()
    /// A new value puts the cursor in the add field of the Inbox list.
    var composerRequest: UUID?
    /// The selected article of the list of a feed.
    var selectedArticle: String?
    /// The row under the cursor of the folder tree, by its absolute path, for each tab that shows a tree.
    var treeCursors: [PaperTab: String] = [:]
    /// The line under the title of the Folders tab after a pin, an unpin, or a click on the + tab.
    var treeMessage: String?
    /// Opens an item as a reader paper. `PaperDesk` sets it.
    @ObservationIgnored var open: (PaperItem) -> Void = { _ in }
    /// Puts the reader papers back in their cascade. `PaperDesk` sets it.
    @ObservationIgnored var tidy: () -> Void = {}
    /// The height of the paper as it shows, for the rule that shortens the pinned tabs.
    var paperHeight = AppDefaults.Papers.feedSize.height
    /// Makes the paper at least as tall as its column of tabs, when the
    /// screen has the room. `FeedPaperController` sets it.
    @ObservationIgnored var fitTabs: (CGFloat) -> Void = { _ in }
    /// The keys of the list that shows: Up Arrow, Down Arrow, and Return.
    /// A list of captures reads its keys itself and sets none.
    @ObservationIgnored var listKeys: ListKeys?
    @ObservationIgnored private let defaults: UserDefaults

    // MARK: - Initialization

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        state = PaperDeskState.restore(from: defaults)
    }

    // MARK: - API

    /// The tabs of the column, and the pinned folders that have no tab.
    var column: (tabs: [PaperTab], overflow: [String]) {
        PaperTab.column(pins: state.pinnedFolders, showsAgents: !model.agents.runner.folders().isEmpty)
    }

    /// The color of a tab.
    func color(of tab: PaperTab) -> TabColor {
        tab.color(pins: state.pinColors)
    }

    /// A click on a tab.
    ///
    /// A click on the active tab moves between its index and its list. A
    /// click on another tab shows its index, or the list or the tree of a tab
    /// without one.
    func choose(_ tab: PaperTab) {
        if tab == state.tab {
            showsIndex = tab.hasIndex && !showsIndex
            return
        }
        guard enter(tab) else { return }
        state.tab = tab
        setScope(state.defaultScope(for: tab, root: model.vault.root.path, sessionFolders: model.agents.runner.folders()))
        showsIndex = tab.hasIndex
    }

    /// A pick on the index: the paper shows the list of the scope.
    func pick(_ scope: PaperScope) {
        if case .inbox(nil) = scope { model.inboxFilters[""] = .all }
        setScope(scope)
        showsIndex = false
    }

    /// A pick of a Show row on the Inbox index: every section, with only notes or only links.
    func pickFilter(_ filter: InboxStream.Filter) {
        setScope(.inbox(section: nil))
        model.inboxFilters[""] = filter
        showsIndex = false
    }

    /// The filter of the list of every Inbox section.
    var inboxFilter: InboxStream.Filter { model.inboxFilter(for: nil) }

    // MARK: - Keyboard

    /// The keys of a list that is not a list of captures.
    struct ListKeys {
        let move: (Int) -> Void
        let open: () -> Void
        /// A letter key, such as S to star an article. Returns true when the list used it.
        var letter: (Character) -> Bool = { _ in false }
    }

    /// The rows of the index of the active tab that the keyboard can pick.
    var indexEntries: [IndexEntry] {
        IndexEntry.entries(tab: state.tab, sections: model.store.sections, feeds: model.feeds.feeds.map(\.id),
                           sessionFolders: model.agents.runner.folders())
    }

    /// The row of the index for the list that shows.
    var currentEntry: IndexEntry {
        IndexEntry.current(scope: state.scope, filter: inboxFilter)
    }

    /// Moves the cursor of the index by one row.
    func moveIndexCursor(_ delta: Int) {
        indexCursor = IndexEntry.move(indexCursor, by: delta, in: indexEntries)
    }

    /// Picks the row under the cursor of the index.
    func pickIndexCursor() {
        guard let indexCursor else { return }
        pick(indexCursor)
    }

    /// Picks a row of the index.
    func pick(_ entry: IndexEntry) {
        switch entry {
        case .scope(let scope): pick(scope)
        case .inboxFilter(let filter): pickFilter(filter)
        }
    }

    /// Shows the Folders tree with a hint, after a click on the + tab.
    func showPinHint() {
        if state.tab != .folders { choose(.folders) }
        treeMessage = "To pin a folder as a tab, select it and press P."
    }

    /// Shows the index of the active tab, after Left Arrow.
    func showIndex() {
        guard state.tab.hasIndex else { return }
        showsIndex = true
    }

    /// Shows the scope before or after the scope of the list, after `[` or `]`.
    func cycleScope(_ delta: Int) {
        guard let scope = IndexEntry.cycle(state.scope, by: delta, in: indexEntries) else { return }
        pick(scope)
    }

    /// A number key: 1 is the first tab of the column.
    func numberKey(_ number: Int) {
        let root = model.vault.root.path
        let folders = model.agents.runner.folders()
        let atDefault = state.scope == state.defaultScope(for: state.tab, root: root, sessionFolders: folders)
            && (state.tab != .inbox || inboxFilter == .all)
        switch NumberKey.action(number, tabs: column.tabs, active: state.tab, showsIndex: showsIndex,
                                atDefaultScope: atDefault) {
        case .toggleIndex: showsIndex.toggle()
        case .showTab(let tab):
            guard enter(tab) else { return }
            state.tab = tab
            if tab == .inbox { model.inboxFilters[""] = .all }
            setScope(state.defaultScope(for: tab, root: model.vault.root.path, sessionFolders: folders))
            showsIndex = false
        case .none: break
        }
    }

    /// Escape, or Back to the List.
    func showList() {
        showsIndex = false
    }

    /// Puts the cursor in the add field of the Inbox list.
    func newCapture() {
        if !state.scope.showsCaptures || state.scope == .clipboard || state.scope == .done {
            state.tab = .inbox
            setScope(.inbox(section: nil))
        }
        showsIndex = false
        model.store.query = ""
        model.store.selection.removeAll()
        composerRequest = UUID()
    }

    /// Pins a folder to the column of tabs, or removes its pin. The Folders
    /// tab says what changed.
    func togglePin(_ path: String) {
        let name = URL(fileURLWithPath: path).lastPathComponent
        let fixed = column.tabs.count - column.tabs.filter(\.isPinned).count
        switch state.togglePin(path, fixedTabs: fixed) {
        case .pinned: treeMessage = "\(name) has a tab."
        case .unpinned: treeMessage = "\(name) has no tab now."
        case .full:
            treeMessage = "The edge holds \(AppDefaults.Papers.tabLimit) tabs. Remove a tab, then pin \(name)."
        }
    }

    /// Sets the color of the active pinned folder tab.
    func setTabColor(_ color: TabColor) {
        guard case .pinned(let path) = state.tab else { return }
        state.setColor(color, of: path)
    }

    // MARK: - Folder Tree

    /// The rows of the tree that show: the whole tree on the Folders tab, or
    /// the folders and files in a pinned folder.
    var treeRows: [FolderTreeRow] {
        var top: String?
        if case .pinned(let path) = state.tab { top = path }
        return FolderTree.rows(paths: model.files.map(\.relativePath), folders: model.folders, roots: model.wikiPaths,
                               activeRoot: model.wikiPath, top: top, expanded: Set(state.expandedFolders))
    }

    /// The row under the cursor of the tree: the row that the reader moved
    /// to, or the first row.
    func treeCursor(in rows: [FolderTreeRow]) -> String? {
        if let cursor = treeCursors[state.tab], rows.contains(where: { $0.id == cursor }) { return cursor }
        return rows.first?.id
    }

    /// An arrow key or Return on the tree.
    func treeKey(_ key: FolderTreeKey) {
        let rows = treeRows
        perform(FolderTree.action(key, cursor: treeCursor(in: rows), rows: rows), in: rows)
    }

    /// A click on a row of the tree: a folder opens or closes, and a file opens as a file paper.
    func clickTreeRow(_ row: FolderTreeRow) {
        treeCursors[state.tab] = row.id
        perform(FolderTree.action(.enter, cursor: row.id, rows: [row]), in: [row])
    }

    /// Opens or closes a folder of the tree.
    func toggleFolder(_ row: FolderTreeRow) {
        perform(row.expanded ? .collapse(row.id) : .expand(row.id), in: [row])
    }

    /// P on the tree: pins the folder under the cursor, or removes its pin.
    func pinTreeCursor() {
        let rows = treeRows
        guard let cursor = treeCursor(in: rows), let row = rows.first(where: { $0.id == cursor }), row.isFolder else { return }
        togglePin(row.id)
    }

    private func perform(_ action: FolderTreeAction, in rows: [FolderTreeRow]) {
        switch action {
        case .select(let id):
            treeCursors[state.tab] = id
        case .expand(let id):
            if rows.first(where: { $0.id == id })?.isOtherRoot == true {
                model.changeWiki(to: URL(fileURLWithPath: id))
                guard model.wikiPath == id else { return }
            }
            setExpanded(id, true)
        case .collapse(let id):
            setExpanded(id, false)
        case .openFile(let id):
            guard let row = rows.first(where: { $0.id == id }) else { return }
            model.openDocument(row.path)
            open(.file)
        case .none:
            break
        }
    }

    private func setExpanded(_ id: String, _ open: Bool) {
        state.expandedFolders.removeAll { $0 == id }
        if open { state.expandedFolders.append(id) }
    }

    /// Forgets the scope of the previous folder after a change of the active folder.
    func vaultChanged() {
        state.resetForVault()
    }

    // MARK: - Private

    /// Shows a scope. A move between two lists of captures clears the search
    /// and the selection. The add field of an Inbox list adds to its section.
    private func setScope(_ scope: PaperScope) {
        let old = state.scope
        if old != scope {
            selectedArticle = nil
            listKeys = nil
            if old.showsCaptures != scope.showsCaptures || [old, scope].contains(.clipboard) || [old, scope].contains(.done) {
                model.store.query = ""
                model.store.selection.removeAll()
            }
        }
        state.scope = scope
        guard case .inbox(let section) = scope else { return }
        let store = model.store
        let target = section ?? (store.sections.contains(RowIcon.inboxSection) ? RowIcon.inboxSection : store.sections.first)
        if let target, target != store.activeSection { store.chooseSection(target) }
    }

    /// Prepares a tab before it shows. A pinned folder becomes part of the
    /// active folder and opens in the shared tree. The line of the Folders tab clears.
    private func enter(_ tab: PaperTab) -> Bool {
        treeMessage = nil
        guard case .pinned(let path) = tab else { return true }
        guard enterRoot(of: path) else { return false }
        if !state.expandedFolders.contains(path) { state.expandedFolders.append(path) }
        return true
    }

    /// Makes the folder that holds `path` the active folder. A path in no
    /// folder of the list stays where it is.
    private func enterRoot(of path: String) -> Bool {
        if PaperDeskState.relativePath(of: path, in: model.vault.root.path) != nil { return true }
        guard let root = model.wikiPaths.first(where: { PaperDeskState.relativePath(of: path, in: $0) != nil }) else { return false }
        model.changeWiki(to: URL(fileURLWithPath: root))
        return PaperDeskState.relativePath(of: path, in: model.vault.root.path) != nil
    }
}
