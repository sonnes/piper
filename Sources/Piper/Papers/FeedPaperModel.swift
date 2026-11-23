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
/// this object in their environment.
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
    /// The row under the cursor of the folder tree, by its absolute path, for each folder tab.
    var treeCursors: [PaperTab: String] = [:]
    /// Opens an item as a reader paper. `PaperDesk` sets it.
    @ObservationIgnored var open: (PaperItem) -> Void = { _ in }
    /// Puts the reader papers back in their cascade. `PaperDesk` sets it.
    @ObservationIgnored var tidy: () -> Void = {}
    /// The height of the paper as it shows, for the rule that shortens the folder tabs.
    var paperHeight = AppDefaults.Papers.feedSize.height
    /// The keys of the list that shows: Up Arrow, Down Arrow, and Return.
    /// A list of captures reads its keys itself and sets none.
    @ObservationIgnored var listKeys: ListKeys?
    @ObservationIgnored private let defaults: UserDefaults

    // MARK: - Initialization

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        state = PaperDeskState.restore(from: defaults)
        syncFolders()
    }

    // MARK: - API

    /// The tabs of the column: the fixed tabs, then one tab for each folder.
    var tabs: [PaperTab] {
        PaperTab.column(folders: model.wikiPaths, showsAgents: !model.agents.runner.folders().isEmpty)
    }

    /// The color of a tab.
    func color(of tab: PaperTab) -> TabColor {
        tab.color(folders: state.folderColors)
    }

    /// The number of files of a folder tab: the files of the active folder,
    /// or the count of the last scan of another folder.
    func fileCount(of path: String) -> Int {
        if path == model.wikiPath, !model.loading, !model.files.isEmpty { return model.files.count }
        return state.folderCounts[path] ?? 0
    }

    /// Gives each new folder a color, and keeps the tab of a folder on the
    /// active folder. The feed paper calls it when the folder list changes.
    func syncFolders() {
        state.assignColors(to: model.wikiPaths)
        if state.tab.isFolder, state.tab != .folder(model.wikiPath) { state.tab = .folder(model.wikiPath) }
    }

    /// Saves the number of files of the active folder after a scan.
    func recordFileCount() {
        guard !model.loading else { return }
        state.folderCounts[model.wikiPath] = model.files.count
    }

    /// The + tab: adds folders with the Add Folder panel, then shows the tab
    /// of the first new folder.
    func addFolder() {
        let before = model.wikiPaths
        model.chooseWiki()
        guard model.wikiPaths != before else { return }
        syncFolders()
        choose(.folder(model.wikiPath))
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
        switch NumberKey.action(number, tabs: tabs, active: state.tab, showsIndex: showsIndex,
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

    /// Sets the color of the active folder tab.
    func setTabColor(_ color: TabColor) {
        guard case .folder(let path) = state.tab else { return }
        state.folderColors[path] = color
    }

    // MARK: - Folder Tree

    /// The rows of the tree of the active folder that show.
    var treeRows: [FolderTreeRow] {
        FolderTree.rows(paths: model.files.map(\.relativePath), folders: model.folders, root: model.wikiPath,
                        expanded: Set(state.expandedFolders))
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

    private func perform(_ action: FolderTreeAction, in rows: [FolderTreeRow]) {
        switch action {
        case .select(let id):
            treeCursors[state.tab] = id
        case .expand(let id):
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

    /// Forgets the state of the previous folder after a change of the active
    /// folder. The tab of a folder moves to the new active folder.
    func vaultChanged() {
        state.resetForVault(root: model.wikiPath)
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

    /// Prepares a tab before it shows. The folder of a folder tab becomes the
    /// active folder, because Piper scans one folder at a time.
    private func enter(_ tab: PaperTab) -> Bool {
        guard case .folder(let path) = tab, path != model.wikiPath else { return true }
        model.changeWiki(to: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        return model.wikiPath == path
    }
}
