import AppKit
import Agents
import Captures
import Feeds
import Observation
import PiperCore
import Stream
import Vault

/// A place that File puts an item: a capture section, a folder as a new
/// file, or a Markdown file that the text goes to the end of.
enum FileTarget: Hashable, Identifiable {
    case section(String)
    /// The root of a folder of the folder list, and a folder under it. An
    /// empty folder is the root.
    case folder(root: String, folder: String)
    /// A Markdown file of the active folder, as a path from its root.
    case file(String)

    var id: Self { self }

    /// The name in the picker, such as "Field Notes / Harbor".
    var title: String {
        switch self {
        case .section(let name): return name
        case .folder(let root, let folder):
            let name = URL(fileURLWithPath: root).lastPathComponent
            return folder.isEmpty ? name : name + " / " + folder
        case .file(let path): return path
        }
    }

    /// The kind in the picker.
    var detail: String {
        switch self {
        case .section: return "section"
        case .folder: return "folder"
        case .file: return "append"
        }
    }

    /// The targets that match a search: the sections first, then the folders,
    /// then the Markdown files of the active folder.
    static func targets(sections: [String], roots: [String], active: String, folders: [String], files: [VaultFile],
                        query: String) -> [FileTarget] {
        let all = sections.map(FileTarget.section)
            + roots.flatMap { root in
                [FileTarget.folder(root: root, folder: "")]
                    + (root == active ? folders.sorted().map { .folder(root: root, folder: $0) } : [])
            }
            + files.filter(\.isMarkdown).map(\.relativePath).sorted().map(FileTarget.file)
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}

/// An Undo button that shows for a few seconds after Done or Delete. It
/// runs Edit > Undo.
struct UndoOffer: Identifiable {
    let id = UUID()
    let message: String
}

/// What the list of Today shows: the stream of a scope, or the done captures.
struct TodayList {
    /// The stream of the scope. Nil on Done, which shows the done captures by month.
    let stream: UnifiedStream?
    let groups: [UnifiedStream.Group]
    /// The rows of the groups and then of the tray, in the order of the list.
    let order: [StreamItem.Ref]
    let items: [StreamItem.Ref: StreamItem]

    var tray: [StreamItem] { stream?.tray ?? [] }
    var doneToday: [StreamItem] { stream?.doneToday ?? [] }

    init(stream: UnifiedStream?, groups: [UnifiedStream.Group]) {
        self.stream = stream
        self.groups = groups
        let rows = groups.flatMap(\.items) + (stream?.tray ?? [])
        order = rows.map(\.id)
        items = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The rows of the references, in the order of the list.
    func rows(_ refs: Set<StreamItem.Ref>) -> [StreamItem] {
        order.filter(refs.contains).compactMap { items[$0] }
    }
}

/// The state of Today and the verbs of its rows, such as Keep, Done, File, and Send.
///
/// The model holds the list and the counts. It builds them again only when
/// an input changes: the feeds, the captures, the clipboard, the files, the
/// read articles that stay, the lens, the scope, the search, or the day.
/// The selection holds the rows of the list, of any kind. The verbs act on
/// the selected rows, or on one row from its buttons and menus.
@MainActor @Observable
final class TodayModel {

    // MARK: - Properties

    /// The seconds that Undo shows after Done or Delete.
    static let undoSeconds: TimeInterval = 5
    let model: AppModel
    /// The selected rows.
    var selection: Set<StreamItem.Ref> = []
    /// The row that Shift-click and Shift-arrow extend the selection from.
    var anchor: StreamItem.Ref?
    /// True while Command-click or Shift selects several rows. The floating bar shows.
    var multiple = false
    /// The words of the search field.
    var query = ""
    /// The read articles that stay in the list until the list shows again,
    /// as in NetNewsWire.
    private(set) var keeping: Set<String> = []
    /// The Undo button after Done or Delete.
    var undo: UndoOffer?
    /// The rows that the File picker files. The picker shows while it is not empty.
    var filing: [StreamItem] = []
    @ObservationIgnored private var undoTimer: Timer?
    /// The count of stream builds, for the tests.
    @ObservationIgnored private(set) var builds = 0
    @ObservationIgnored private var inputCache: (key: InputKey, value: UnifiedStream.Input)?
    @ObservationIgnored private var listCache: (key: ListKey, value: TodayList)?
    @ObservationIgnored private var countsCache: (key: CountsKey, value: UnifiedStream.Counts)?
    @ObservationIgnored private var relevanceCache: (key: RelevanceKey, value: Relevance)?

    private var store: CaptureStore { model.store }
    private var feeds: FeedStore { model.feeds }
    private var messages: Messages { model.messages }
    private var undoManager: UndoManager { model.undoManager }

    // MARK: - Initialization

    init(model: AppModel) {
        self.model = model
    }

    // MARK: - Stream

    /// The list of a scope with a lens.
    func list(lens: UnifiedStream.Lens, scope: PaperScope, now: Date = Date()) -> TodayList {
        let key = ListKey(input: inputKey, lens: lens, scope: scope, query: query, day: Calendar.current.startOfDay(for: now))
        if let listCache, listCache.key == key { return listCache.value }
        let value: TodayList
        switch scope {
        case .done:
            value = TodayList(stream: nil, groups: UnifiedStream.done(notes: store.notes, query: query))
        case .today(let section):
            let stream = build(lens: lens, section: section, query: query, now: now)
            value = TodayList(stream: stream, groups: stream.groups)
        case .feed, .sources, .folder, .sessions:
            value = TodayList(stream: nil, groups: [])
        }
        listCache = (key, value)
        return value
    }

    /// The counts of everything, with no search: the Today tab and the Today index show them.
    func counts(now: Date = Date()) -> UnifiedStream.Counts {
        let key = CountsKey(input: inputKey, day: Calendar.current.startOfDay(for: now))
        if let countsCache, countsCache.key == key { return countsCache.value }
        let counts: UnifiedStream.Counts
        if let listCache, listCache.key.counts == key, listCache.key.scope == .today(section: nil), listCache.key.query.isEmpty,
           let stream = listCache.value.stream {
            counts = stream.counts
        } else {
            counts = build(lens: .all, section: nil, query: "", now: now).counts
        }
        countsCache = (key, counts)
        return counts
    }

    /// The reader opens an article row. The row stays in the list, read,
    /// until the list shows again.
    func open(article id: String) {
        if !keeping.contains(id) { keeping.insert(id) }
    }

    /// The list shows again, or shows another scope. The read articles leave it.
    func resetKeeping() {
        if !keeping.isEmpty { keeping.removeAll() }
    }

    private var inputKey: InputKey {
        InputKey(feeds: feeds.revision, store: store.revision, clipboard: model.clipboard.revision,
                 files: model.library.filesRevision, keeping: keeping)
    }

    private func build(lens: UnifiedStream.Lens, section: String?, query: String, now: Date) -> UnifiedStream {
        builds += 1
        return UnifiedStream(input(), lens: lens, section: section, query: query, now: now)
    }

    /// Everything that the stream reads.
    private func input() -> UnifiedStream.Input {
        let key = inputKey
        if let inputCache, inputCache.key == key { return inputCache.value }
        let value = UnifiedStream.Input(notes: store.notes, clips: model.clipboard.entries,
                                        articles: feeds.articles(.allUnread, keeping: keeping), feeds: feeds.feeds,
                                        relevance: relevance())
        inputCache = (key, value)
        return value
    }

    /// The relevance from local data. It changes when the feeds, the captures,
    /// or the files change.
    private func relevance() -> Relevance {
        let key = RelevanceKey(feeds: feeds.revision, store: store.revision, files: model.library.filesRevision)
        if let relevanceCache, relevanceCache.key == key { return relevanceCache.value }
        let value = Relevance(feeds: feeds, notes: store.notes, fileNames: model.library.files.map(\.relativePath))
        relevanceCache = (key, value)
        return value
    }

    // MARK: - Selection

    /// Selects one row and ends a selection of several.
    func select(_ ref: StreamItem.Ref) {
        selection = [ref]
        anchor = ref
        multiple = false
    }

    /// Command-click adds or removes a row. Shift-click selects the rows from
    /// the anchor to the row.
    func extend(to ref: StreamItem.Ref, range: Bool, in order: [StreamItem.Ref]) {
        if range, let anchor, let start = order.firstIndex(of: anchor), let end = order.firstIndex(of: ref) {
            selection.formUnion(order[min(start, end)...max(start, end)])
        } else {
            if selection.contains(ref) { selection.remove(ref) } else { selection.insert(ref) }
            anchor = ref
        }
        multiple = !selection.isEmpty
    }

    /// Up Arrow and Down Arrow. Shift adds the next row to the selection.
    func move(_ delta: Int, extending: Bool, in order: [StreamItem.Ref]) {
        guard let ref = order.step(from: anchor, by: delta) else { return }
        if extending {
            selection.insert(ref)
            multiple = true
        } else {
            selection = [ref]
            multiple = false
        }
        anchor = ref
    }

    func clearSelection() {
        selection.removeAll()
        anchor = nil
        multiple = false
    }

    /// Drops the selected rows that the list does not show any more.
    func keepSelection(in order: [StreamItem.Ref]) {
        selection.formIntersection(order)
        if selection.isEmpty { multiple = false }
    }

    // MARK: - Keep

    /// Keeps the items: a capture gets the kept tag, an article becomes a kept
    /// link capture, and a clipboard text becomes a kept note. When every
    /// capture is kept already, Keep takes the mark away.
    func keep(_ items: [StreamItem]) {
        let captures = items.compactMap(\.note)
        do {
            if !captures.isEmpty, captures.count == items.count, captures.allSatisfy(\.isKept) {
                try store.setKept(false, Set(captures.map(\.id)))
                return messages.show("Not kept")
            }
            if !captures.isEmpty { try store.setKept(true, Set(captures.map(\.id))) }
            for clip in items.compactMap(\.clip) { try model.clipboard.save(clip.id) }
        } catch {
            return messages.report(error)
        }
        let articles = items.flatMap(\.articles)
        if !articles.isEmpty, !model.articleActions.keep(articles) { return }
        messages.show("Kept")
    }

    // MARK: - Done

    /// Marks the items as done: a capture goes to Done, an article is read,
    /// and a clipboard text leaves the tray. Undo shows for a few seconds.
    func done(_ items: [StreamItem]) {
        let captures = items.compactMap(\.note)
        let reopen = !captures.isEmpty && captures.allSatisfy(\.isDone)
        undoManager.beginUndoGrouping()
        defer { undoManager.endUndoGrouping() }
        do { try store.setDone(!reopen, Set(captures.map(\.id))) } catch { return messages.report(error) }
        markRead(items)
        dismissClips(items.compactMap(\.clip).map(\.id))
        selection.subtract(items.map(\.id))
        offerUndo(reopen ? "Reopened \(Self.count(items.count))" : "Done · \(Self.count(items.count))")
    }

    // MARK: - File

    /// The places that the File picker offers for a search.
    func fileTargets(query: String) -> [FileTarget] {
        FileTarget.targets(sections: store.sections, roots: model.library.wikiPaths, active: model.library.wikiPath,
                           folders: model.library.folders, files: model.library.files, query: query)
    }

    /// Files the items. A section takes the captures, and keeps an article or
    /// a clipboard text as a capture in it. A folder saves the items as a new
    /// file, and a file takes them at its end. Then the items are done.
    @discardableResult
    func file(_ items: [StreamItem], to target: FileTarget, now: Date = Date()) -> Bool {
        guard !items.isEmpty else { return false }
        undoManager.beginUndoGrouping()
        defer { undoManager.endUndoGrouping() }
        do {
            messages.show(try file(items, to: target, now: now))
        } catch {
            messages.report(error)
            return false
        }
        selection.subtract(items.map(\.id))
        return true
    }

    /// Files the items, and returns the message for the reader.
    private func file(_ items: [StreamItem], to target: FileTarget, now: Date) throws -> String {
        switch target {
        case .section(let section):
            try store.move(Set(items.compactMap(\.note).map(\.id)), to: section)
            let articles = items.flatMap(\.articles)
            if !articles.isEmpty {
                try model.articleActions.capture(articles, to: section)
                markRead(items)
            }
            for clip in items.compactMap(\.clip) {
                try store.add(clip.text, section: section, source: Note.clipboardSource)
            }
            return "Filed in \(section)"
        case .folder(let root, let folder):
            let vault = Vault(path: root)
            let title = items.count == 1 ? Self.fileTitle(items[0]) : "Notes \(CaptureText.day(now))"
            let text = items.count == 1 ? fileText(items[0], now: now) : items.map { appendText($0) }.joined(separator: "\n")
            let name = ArticleMarkdown.fileName(for: title)
            let path = vault.freeName((name as NSString).deletingPathExtension, ext: (name as NSString).pathExtension, in: folder)
            try vault.write(text, to: path)
            try finishFiling(items, savedFile: vault.root.appendingPathComponent(path).path)
            model.library.reload()
            return "Saved to " + target.title
        case .file(let path):
            let vault = model.library.vault
            let current = (try? vault.read(path)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let block = items.map { appendText($0) }.joined(separator: "\n")
            let joined = current.isEmpty || current.hasSuffix("\n\n") ? current
                : current.hasSuffix("\n") ? current + "\n" : current + "\n\n"
            try vault.write(joined + block, to: path)
            try finishFiling(items, savedFile: vault.root.appendingPathComponent(path).path)
            model.library.reload()
            return "Added to " + path
        }
    }

    // MARK: - Send

    /// Opens a draft with a skill of a folder for each item, or with the
    /// default skill of each item. An article goes as its link. A clipboard
    /// text goes to Inbox first.
    func send(_ items: [StreamItem], action: SkillFolders.Action?) {
        for item in items {
            do {
                var session: AgentSession?
                if let clip = item.clip {
                    session = try model.send.clip(clip, from: model.clipboard, action: action)
                } else if let note = sendable(item) {
                    session = try model.send.note(note, action: action)
                }
                if let session { messages.show("Draft in \(session.folderName)") }
            } catch {
                messages.report(error)
            }
        }
    }

    /// Opens a new session about the item, with the text of the item in the message field.
    func ask(_ item: StreamItem) {
        guard let note = sendable(item) else { return }
        model.agents.openDraft(text: note.text + "\n\n", folder: model.library.agentFolder, noteID: note.id)
    }

    // MARK: - Merge, Copy, and Delete

    /// Joins the selected captures into the first one.
    func merge(_ items: [StreamItem]) {
        let ids = items.compactMap(\.note).map(\.id)
        guard ids.count > 1 else { return }
        do {
            select(.note(try store.merge(ids).id))
            messages.show("Notes merged")
        } catch {
            messages.report(error)
        }
    }

    /// Copies the text of each item: the text of a note, the link of a link
    /// or an article, and the links of a digest.
    func copy(_ items: [StreamItem], asList: Bool = false, to pasteboard: NSPasteboard = .general) {
        let texts = items.map(Self.copyText)
        let text = asList
            ? texts.enumerated().map { "\($0.offset + 1). " + $0.element.replacingOccurrences(of: "\n", with: "\n   ") }.joined(separator: "\n\n")
            : texts.joined(separator: "\n\n")
        if Clipboard.copy(text, to: pasteboard) {
            messages.show("Copied")
        } else {
            messages.report(PiperError("Cannot write to the clipboard."))
        }
    }

    /// True for a row that Delete removes: a capture or a clipboard text.
    /// An article and a digest have no Delete.
    static func canDelete(_ ref: StreamItem.Ref) -> Bool {
        switch ref {
        case .note, .clip: return true
        case .article, .digest: return false
        }
    }

    /// Deletes the captures, with Undo, and takes the clipboard texts out of
    /// the tray. Articles and digests stay as they are.
    func delete(_ items: [StreamItem]) {
        let items = items.filter { Self.canDelete($0.id) }
        guard !items.isEmpty else { return }
        undoManager.beginUndoGrouping()
        defer { undoManager.endUndoGrouping() }
        do { try store.delete(items.compactMap(\.note).map(\.id)) } catch { return messages.report(error) }
        dismissClips(items.compactMap(\.clip).map(\.id))
        selection.subtract(items.map(\.id))
        offerUndo("Deleted \(Self.count(items.count))")
    }

    // MARK: - Undo

    /// Runs Edit > Undo from the Undo button, while it shows.
    func runUndo() {
        guard undo != nil else { return }
        undo = nil
        undoTimer?.invalidate()
        undoManager.undo()
    }

    private func offerUndo(_ message: String) {
        undoTimer?.invalidate()
        let offer = UndoOffer(message: message)
        undo = offer
        undoTimer = Timer.scheduledTimer(withTimeInterval: Self.undoSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.undo?.id == offer.id { self?.undo = nil }
            }
        }
    }

    // MARK: - Private

    /// A note that a skill can take: the capture, or a note that is not
    /// saved and holds the link of an article or the links of a digest.
    private func sendable(_ item: StreamItem) -> Note? {
        if let note = item.note { return note }
        if let clip = item.clip { return Note(text: clip.text, section: store.activeSection) }
        let text = item.kind == .digest ? Self.copyText(item) : item.articles.first?.url ?? ""
        return text.isEmpty ? nil : Note(text: text, section: store.activeSection)
    }

    /// Marks the filed items as done, and records the file of a link capture.
    private func finishFiling(_ items: [StreamItem], savedFile: String) throws {
        for note in items.compactMap(\.note) where note.isArticle {
            try store.updateReading(note.id) { $0.savedFile = savedFile; $0.savedAt = Date() }
        }
        try store.setDone(true, Set(items.compactMap(\.note).map(\.id)))
        markRead(items)
        dismissClips(items.compactMap(\.clip).map(\.id))
    }

    /// Marks the unread articles of the items as read, with an undo step.
    private func markRead(_ items: [StreamItem]) {
        let ids = items.flatMap(\.articles).filter { !$0.read }.map(\.id)
        setRead(true, ids: ids)
    }

    private func setRead(_ read: Bool, ids: [String]) {
        guard !ids.isEmpty else { return }
        feeds.setRead(read, ids: ids)
        undoManager.registerUndo(withTarget: self) { today in today.setRead(!read, ids: ids) }
    }

    /// Takes the texts out of the clipboard tray, with an undo step that puts them back.
    private func dismissClips(_ ids: [UUID]) {
        let entries = ids.compactMap { model.clipboard.dismiss($0) }
        guard !entries.isEmpty else { return }
        undoManager.registerUndo(withTarget: self) { today in today.restoreClips(entries) }
    }

    private func restoreClips(_ entries: [ClipboardEntry]) {
        entries.forEach(model.clipboard.restore)
        undoManager.registerUndo(withTarget: self) { today in today.dismissClips(entries.map(\.id)) }
    }

    /// The text of a new file for one item.
    private func fileText(_ item: StreamItem, now: Date) -> String {
        switch item.kind {
        case .link:
            guard let note = item.note, let url = note.articleURL else { return item.title }
            return ArticleMarkdown.file(title: item.title, url: url, children: store.children(of: note.id),
                                        parts: ArticleMarkdown.Parts(), date: now)
        case .article:
            guard let article = item.articles.first, let url = URL(string: article.url) else { return item.title }
            let summary = article.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            return ArticleMarkdown.file(title: article.title, url: url, children: [], parts: ArticleMarkdown.Parts(), date: now)
                + (summary.isEmpty ? "" : "\n" + summary + "\n")
        case .digest:
            return "# \(item.title)\n\n" + Self.copyText(item) + "\n"
        case .note, .clip:
            let text = item.note?.text ?? item.clip?.text ?? item.title
            return text.hasSuffix("\n") ? text : text + "\n"
        }
    }

    /// The text that File adds to the end of a file for one item.
    private func appendText(_ item: StreamItem) -> String {
        switch item.kind {
        case .link, .article:
            let url = item.url?.absoluteString ?? item.articles.first?.url ?? ""
            let quotes = item.note.map { ReadingList.highlights(in: store.children(of: $0.id)) } ?? []
            return "- [\(Self.linkTitle(item.title))](\(url))\n"
                + quotes.map { "  > " + RowNotes.quote(of: $0).replacingOccurrences(of: "\n", with: " ") + "\n" }.joined()
        case .digest:
            return Self.copyText(item) + "\n"
        case .note, .clip:
            let text = item.note?.text ?? item.clip?.text ?? item.title
            return text.hasSuffix("\n") ? text : text + "\n"
        }
    }

    private static func copyText(_ item: StreamItem) -> String {
        switch item.kind {
        case .note: return item.note?.text ?? item.title
        case .clip: return item.clip?.text ?? item.title
        case .link, .article: return item.url?.absoluteString ?? item.articles.first?.url ?? item.title
        case .digest: return item.articles.map { "- [\(linkTitle($0.title))](\($0.url))" }.joined(separator: "\n")
        }
    }

    private static func fileTitle(_ item: StreamItem) -> String {
        CaptureText.firstLine(item.title)
    }

    private static func linkTitle(_ title: String) -> String {
        CaptureText.firstLine(title).replacingOccurrences(of: "]", with: "\\]")
    }

    static func count(_ value: Int) -> String {
        value == 1 ? "1 item" : "\(value) items"
    }
}

// MARK: - Keys

private extension TodayModel {
    struct InputKey: Equatable {
        let feeds: Int
        let store: Int
        let clipboard: Int
        let files: Int
        let keeping: Set<String>
    }

    struct ListKey: Equatable {
        let input: InputKey
        let lens: UnifiedStream.Lens
        let scope: PaperScope
        let query: String
        let day: Date

        var counts: CountsKey { CountsKey(input: input, day: day) }
    }

    /// The counts do not change with the lens, the scope, or the search.
    struct CountsKey: Equatable {
        let input: InputKey
        let day: Date
    }

    struct RelevanceKey: Equatable {
        let feeds: Int
        let store: Int
        let files: Int
    }
}
