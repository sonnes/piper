import AppKit
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
    var showsIndex = false
    /// The open papers and the flash of a row.
    let marks = DeskMarks()
    /// A new value puts the cursor in the add field of the Inbox list.
    var composerRequest: UUID?
    /// The selected article of the list of a feed.
    var selectedArticle: String?
    /// Opens an item as a reader paper. `PaperDesk` sets it.
    @ObservationIgnored var open: (PaperItem) -> Void = { _ in }
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

    /// A click on a tab.
    ///
    /// A click on the active tab moves between its index and its list. A
    /// click on another tab shows its index, or the list of a tab without one.
    func choose(_ tab: PaperTab) {
        if tab == state.tab {
            showsIndex = tab.hasIndex && !showsIndex
            return
        }
        if case .pinned(let path) = tab, !enterRoot(of: path) { return }
        state.tab = tab
        setScope(state.defaultScope(for: tab, root: model.vault.root.path, sessionFolders: model.agents.runner.folders()))
        showsIndex = tab.hasIndex
    }

    /// A pick on the index: the paper shows the list of the scope.
    func pick(_ scope: PaperScope) {
        setScope(scope)
        showsIndex = false
    }

    /// A pick of a pinned folder on the Folders index.
    func pickPinned(_ path: String) {
        guard enterRoot(of: path) else { return }
        pick(.folder(PaperDeskState.relativePath(of: path, in: model.vault.root.path) ?? ""))
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

    /// Pins a folder to the column of tabs, or removes its pin.
    func togglePin(_ path: String) {
        state.togglePin(path)
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

    /// Makes the folder that holds `path` the active folder. A path in no
    /// folder of the list stays where it is.
    private func enterRoot(of path: String) -> Bool {
        if PaperDeskState.relativePath(of: path, in: model.vault.root.path) != nil { return true }
        guard let root = model.wikiPaths.first(where: { PaperDeskState.relativePath(of: path, in: $0) != nil }) else { return false }
        model.changeWiki(to: URL(fileURLWithPath: root))
        return PaperDeskState.relativePath(of: path, in: model.vault.root.path) != nil
    }
}
