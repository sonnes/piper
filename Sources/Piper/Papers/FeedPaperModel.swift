import AppKit
import Captures
import Feeds
import Stream

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
    /// A new value puts the cursor in the capture field of Today.
    var composerRequest: UUID?
    /// The selection, the search, and the verbs of Today.
    let today: TodayModel
    /// The address that Sources looks up when it opens, after a paste of a feed or site address.
    var sourcesAddress: String?
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
        today = TodayModel(model: model)
        state = PaperDeskState.restore(from: defaults)
        syncFolders()
        model.library.folderChanged = { [weak self] in self?.vaultChanged() }
    }

    // MARK: - API

    /// The tabs of the column: the fixed tabs, then one tab for each folder.
    var tabs: [PaperTab] {
        PaperTab.column(folders: model.library.wikiPaths, showsAgents: !model.agents.runner.folders().isEmpty)
    }

    /// The color of a tab.
    func color(of tab: PaperTab) -> TabColor {
        tab.color(folders: state.folderColors)
    }

    /// The number of files of a folder tab: the files of the active folder,
    /// or the count of the last scan of another folder.
    func fileCount(of path: String) -> Int {
        if path == model.library.wikiPath, !model.library.loading, !model.library.files.isEmpty { return model.library.files.count }
        return state.folderCounts[path] ?? 0
    }

    /// Gives each new folder a color, and keeps the tab of a folder on the
    /// active folder. The feed paper calls it when the folder list changes.
    func syncFolders() {
        state.assignColors(to: model.library.wikiPaths)
        if state.tab.isFolder, state.tab != .folder(model.library.wikiPath) { state.tab = .folder(model.library.wikiPath) }
    }

    /// Saves the number of files of the active folder after a scan.
    func recordFileCount() {
        guard !model.library.loading else { return }
        state.folderCounts[model.library.wikiPath] = model.library.files.count
    }

    /// The + tab: adds folders with the Add Folder panel, then shows the tab
    /// of the first new folder.
    func addFolder() {
        let before = model.library.wikiPaths
        model.library.chooseWiki()
        guard model.library.wikiPaths != before else { return }
        syncFolders()
        choose(.folder(model.library.wikiPath))
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
        setScope(state.defaultScope(for: tab, root: model.library.vault.root.path, sessionFolders: model.agents.runner.folders()))
        showsIndex = tab.hasIndex
    }

    /// A pick on the index: the paper shows the list of the scope.
    func pick(_ scope: PaperScope) {
        switch scope {
        case .feed, .sources: if !state.tab.isFolder { state.tab = .today }
        default: break
        }
        setScope(scope)
        showsIndex = false
    }

    /// A pick of a lens row on the Today index: everything, with one lens.
    func pickLens(_ lens: UnifiedStream.Lens) {
        if state.tab != .today { state.tab = .today }
        setScope(.today(section: nil))
        state.lens = lens
        showsIndex = false
    }

    /// Shows Sources. An address, from a paste of a feed or site address, goes in its add field.
    func showSources(address: String? = nil) {
        sourcesAddress = address
        pick(.sources)
    }

    // MARK: - Keyboard

    /// The keys of a list that is not a list of captures.
    struct ListKeys {
        let move: (Int) -> Void
        let open: () -> Void
        /// A letter key, such as K to keep an article. Returns true when the list used it.
        var letter: (Character) -> Bool = { _ in false }
    }

    /// The rows of the index of the active tab that the keyboard can pick.
    var indexEntries: [IndexEntry] {
        IndexEntry.entries(tab: state.tab, sections: model.store.sections, sessionFolders: model.agents.runner.folders())
    }

    /// The row of the index for the list that shows.
    var currentEntry: IndexEntry {
        IndexEntry.current(scope: state.scope, lens: state.lens)
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
        case .lens(let lens): pickLens(lens)
        }
    }

    /// Shows the index of the active tab, after Left Arrow.
    func showIndex() {
        guard state.tab.hasIndex else { return }
        showsIndex = true
    }

    /// Shows the row of the index before or after the list, after `[` or `]`.
    func cycleScope(_ delta: Int) {
        guard let entry = IndexEntry.cycle(currentEntry, by: delta, in: indexEntries) else { return }
        pick(entry)
    }

    /// Command and a number key: Command-1 is the first tab of the column.
    func numberKey(_ number: Int) {
        let root = model.library.vault.root.path
        let folders = model.agents.runner.folders()
        let atDefault = state.scope == state.defaultScope(for: state.tab, root: root, sessionFolders: folders)
        switch NumberKey.action(number, tabs: tabs, active: state.tab, showsIndex: showsIndex,
                                atDefaultScope: atDefault) {
        case .toggleIndex: showsIndex.toggle()
        case .showTab(let tab):
            guard enter(tab) else { return }
            state.tab = tab
            setScope(state.defaultScope(for: tab, root: model.library.vault.root.path, sessionFolders: folders))
            showsIndex = false
        case .none: break
        }
    }

    /// Escape, or Back to the List.
    func showList() {
        showsIndex = false
    }

    /// Puts the cursor in the capture field of Today.
    func newCapture() {
        if state.tab != .today || state.scope == .done || !state.scope.showsCaptures {
            state.tab = .today
            setScope(.today(section: nil))
        }
        showsIndex = false
        today.query = ""
        today.clearSelection()
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
        FolderTree.rows(paths: model.library.files.map(\.relativePath), folders: model.library.folders, root: model.library.wikiPath,
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
            model.files.openDocument(row.path)
            open(.file)
        case .none:
            break
        }
    }

    private func setExpanded(_ id: String, _ open: Bool) {
        state.expandedFolders.removeAll { $0 == id }
        if open { state.expandedFolders.append(id) }
    }

    // MARK: - Private

    /// Forgets the state of the previous folder after a change of the active
    /// folder. The tab of a folder moves to the new active folder.
    private func vaultChanged() {
        state.resetForVault(root: model.library.wikiPath)
    }

    /// Shows a scope. A move to another scope clears the search and the selection.
    private func setScope(_ scope: PaperScope) {
        let old = state.scope
        if old != scope {
            selectedArticle = nil
            listKeys = nil
            today.query = ""
            today.clearSelection()
        }
        state.scope = scope
    }

    /// Prepares a tab before it shows. The folder of a folder tab becomes the
    /// active folder, because Piper scans one folder at a time.
    private func enter(_ tab: PaperTab) -> Bool {
        guard case .folder(let path) = tab, path != model.library.wikiPath else { return true }
        model.library.changeWiki(to: path)
        return model.library.wikiPath == path
    }
}
