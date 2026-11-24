import AppKit
import Captures
import Feeds
import Stream

/// One item that a reader paper shows.
enum PaperItem: Hashable {
    /// A capture, by its id. A link capture shows its Reader, Web, and Notes
    /// tabs, and `show` picks the place where its paper opens.
    case note(UUID, show: ReaderTarget? = nil)
    /// A feed article, by its id.
    case article(String)
    /// The open file of `FileEditor`. Only one file paper exists, because the editor page is shared.
    case file
    case session(UUID)
    /// A new agent session in a folder, by the absolute path of the folder.
    case newSession(String)
}

@MainActor
extension PaperItem {
    /// The link capture of a feed article, once the reader keeps the article
    /// or marks it. The capture holds the link of the article.
    static func keptNote(of article: Article, in store: CaptureStore) -> Note? {
        URL(string: article.url).flatMap(store.article(for:))
    }

    /// The capture that the paper of the item shows: a capture, or the link
    /// capture of a kept feed article.
    func note(in model: AppModel) -> Note? {
        switch self {
        case .note(let id, _):
            return model.store.notes.first { $0.id == id }
        case .article(let id):
            return model.feeds.article(id).flatMap { Self.keptNote(of: $0, in: model.store) }
        case .file, .session, .newSession:
            return nil
        }
    }

    /// The paper that the item opens. A kept feed article and its link
    /// capture are one paper.
    func identity(in model: AppModel) -> PaperItem {
        guard case .article = self, let note = note(in: model) else { return withoutTarget }
        return .note(note.id)
    }

    /// The place where the paper of a link capture opens.
    var target: ReaderTarget? {
        guard case .note(_, let target) = self else { return nil }
        return target
    }

    /// The item as the desk keeps it, without the place where its paper opens.
    var withoutTarget: PaperItem {
        guard case .note(let id, _) = self else { return self }
        return .note(id)
    }

    /// True when the paper of the item shows an article, which takes H and N.
    func isArticle(in model: AppModel) -> Bool {
        switch self {
        case .article: return true
        case .note: return note(in: model)?.isArticle == true
        case .file, .session, .newSession: return false
        }
    }
}

/// What the rows of the feed paper show about the papers on the desk.
///
/// A row of an item that is open as a reader paper shows a dashed slot. A
/// row flashes when its paper goes back. The views of the feed paper find
/// this object in their environment.
@MainActor @Observable
final class DeskMarks {
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
    var feedFocused = false
    var focusedPaper: PaperItem?
    /// The paper that an item opens. `PaperDesk` sets it to `PaperItem.identity(in:)`.
    @ObservationIgnored var identity: (PaperItem) -> PaperItem = { $0 }

    func isOpen(_ item: PaperItem) -> Bool {
        let paper = identity(item)
        return open.contains { identity($0) == paper }
    }

    func isOpenFile(_ path: String) -> Bool { openFile == path && open.contains(.file) }

    func flashes(_ item: PaperItem) -> UUID? {
        guard let flash, identity(flash.item) == identity(item) else { return nil }
        return flash.id
    }
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
    let marks = DeskMarks()
    /// A new value puts the cursor in the capture field of Today.
    var composerRequest: UUID?
    /// The selection, the search, and the verbs of Today.
    let today: TodayModel
    /// The address that Sources looks up when it opens, after a paste of a feed or site address.
    var sourcesAddress: String?
    /// A new value puts the cursor in the address field of Sources.
    var addressRequest: UUID?
    var selectedArticle: String?
    /// The row under the cursor of the folder tree, by its absolute path, for each folder tab.
    var treeCursors: [PaperTab: String] = [:]
    /// Puts the reader papers back in their cascade. `PaperDesk` sets it.
    @ObservationIgnored var tidy: () -> Void = {}
    /// The height of the paper as it shows, for the rule that shortens the folder tabs.
    var paperHeight = FeedPaperController.Metrics.feedSize.height
    /// The keys of the list that shows. The list sets them, and a move to another scope clears them.
    var listKeys: [PaperKey] = []
    @ObservationIgnored private let defaults: UserDefaults

    // MARK: - Initialization

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        today = TodayModel(model: model)
        state = PaperDeskState.restore(from: defaults)
        assignColors()
        followActiveFolder()
        model.library.folderChanged = { [weak self] in self?.followActiveFolder() }
    }

    // MARK: - API

    /// The tabs of the column: the fixed tabs, then one tab for each folder.
    var tabs: [PaperTab] {
        PaperTab.column(folders: model.library.wikiPaths, showsAgents: !model.agents.runner.folders().isEmpty)
    }

    func color(of tab: PaperTab) -> TabColor {
        tab.color(folders: state.folderColors)
    }

    /// The count on a tab: the open captures, the unread articles, the
    /// sessions that wait for the reader, or the files of a folder.
    func count(of tab: PaperTab) -> Int {
        switch tab {
        case .today: return today.counts().open
        case .feeds: return model.feeds.unreadCounts().values.reduce(0, +)
        case .agents: return model.agents.runner.folders().reduce(0) { $0 + waitingSessions(in: $1) }
        case .folder(let path): return fileCount(of: path)
        }
    }

    func waitingSessions(in folder: String) -> Int {
        model.agents.runner.sessions(in: folder).filter { $0.state == .needsYou }.count
    }

    /// The number of files of a folder tab: the files of the active folder,
    /// or the count of the last scan of another folder.
    func fileCount(of path: String) -> Int {
        if path == model.library.wikiPath, !model.library.loading, !model.library.files.isEmpty { return model.library.files.count }
        return state.folderCounts[path] ?? 0
    }

    /// Gives each new folder a color. The feed paper calls it when the folder list changes.
    func assignColors() {
        state.assignColors(to: model.library.wikiPaths)
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
        assignColors()
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

    /// A pick on the index: the paper shows the list of the scope. A capture
    /// scope shows on Today, and a feed scope shows on Feeds.
    func pick(_ scope: PaperScope) {
        switch scope {
        case .today, .done: state.tab = .today
        case .feed, .sources: state.tab = .feeds
        case .folder, .sessions: break
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

    /// Shows Sources on the Feeds tab. An address, from a paste of a feed or
    /// site address, goes in its add field.
    func showSources(address: String? = nil) {
        sourcesAddress = address
        pick(.sources)
    }

    /// Shows Sources with the cursor in its address field, for Add Feed.
    func addFeed() {
        showSources()
        addressRequest = UUID()
    }

    // MARK: - Keyboard

    /// The rows of the index of the active tab that the keyboard can pick.
    var indexEntries: [IndexEntry] {
        IndexEntry.entries(tab: state.tab, sections: model.store.sections, feeds: model.feeds.feeds.map(\.id),
                           sessionFolders: model.agents.runner.folders())
    }

    /// The row of the index for the list that shows.
    var currentEntry: IndexEntry {
        IndexEntry.current(scope: state.scope, lens: state.lens)
    }

    func moveIndexCursor(_ delta: Int) {
        indexCursor = indexEntries.step(from: indexCursor, by: delta)
    }

    func pickIndexCursor() {
        guard let indexCursor else { return }
        pick(indexCursor)
    }

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

    /// Command and a number key shows the tab with that number, at its
    /// default scope. Command-1 is the first tab of the column.
    func numberKey(_ number: Int) {
        guard tabs.indices.contains(number - 1) else { return }
        let tab = tabs[number - 1]
        guard enter(tab) else { return }
        state.tab = tab
        setScope(state.defaultScope(for: tab, root: model.library.vault.root.path, sessionFolders: model.agents.runner.folders()))
        showsIndex = false
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
            model.files.openFile(row.path)
        case .none:
            break
        }
    }

    private func setExpanded(_ id: String, _ open: Bool) {
        state.expandedFolders.removeAll { $0 == id }
        if open { state.expandedFolders.append(id) }
    }

    // MARK: - Private

    /// Keeps the tab of a folder on the active folder, because Piper scans one folder at a time.
    private func followActiveFolder() {
        if state.tab.isFolder, state.tab != .folder(model.library.wikiPath) { state.tab = .folder(model.library.wikiPath) }
    }

    /// Shows a scope. A move to another scope clears the search and the selection.
    private func setScope(_ scope: PaperScope) {
        let old = state.scope
        if old != scope {
            selectedArticle = nil
            listKeys = []
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
