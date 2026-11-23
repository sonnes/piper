import AppKit
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
    static func targets(sections: [String], roots: [String], active: String, folders: [String], files: [String],
                        query: String) -> [FileTarget] {
        let all = sections.map(FileTarget.section)
            + roots.flatMap { root in
                [FileTarget.folder(root: root, folder: "")]
                    + (root == active ? folders.sorted().map { .folder(root: root, folder: $0) } : [])
            }
            + files.filter { $0.lowercased().hasSuffix(".md") }.sorted().map(FileTarget.file)
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}

/// An Undo button that shows for a few seconds after Done or Delete.
struct UndoOffer: Identifiable {
    let id = UUID()
    let message: String
    let run: () -> Void
}

/// The state of Today and the four verbs of its rows: Keep, Done, File, and Send.
///
/// The selection holds the rows of the stream, of any kind. The verbs act on
/// the selected rows, or on one row from its buttons and menus.
@MainActor @Observable
final class TodayModel {

    // MARK: - Properties

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
    var keeping: Set<String> = []
    /// The Undo button after Done or Delete.
    var undo: UndoOffer?
    /// The rows that the File picker files. The picker shows while it is not empty.
    var filing: [StreamItem] = []
    @ObservationIgnored private var undoTimer: Timer?
    @ObservationIgnored private var relevanceCache: (key: [Int], value: Relevance)?

    private var store: CaptureStore { model.store }
    private var feeds: FeedStore { model.feeds }

    // MARK: - Initialization

    init(model: AppModel) {
        self.model = model
    }

    // MARK: - Stream

    /// Everything that the stream reads.
    func input() -> UnifiedStream.Input {
        UnifiedStream.Input(notes: store.notes, clips: model.clipboard.entries,
                            articles: feeds.articles(.allUnread, keeping: keeping), feeds: feeds.feeds,
                            relevance: relevance())
    }

    /// The relevance from local data. It changes when the feeds, the captures,
    /// or the files change.
    func relevance() -> Relevance {
        let key = [feeds.revision, store.notes.count, model.files.count]
        if let relevanceCache, relevanceCache.key == key { return relevanceCache.value }
        let stats = FeedStats.compute(feeds: feeds.feeds, counts: feeds.articleCounts(days: FeedStats.days), notes: store.notes)
        let history = Dictionary(feeds.suggestions.map { ($0.host, $0.score) }, uniquingKeysWith: max)
        let value = Relevance(stats: stats, history: history, fileNames: model.files.map(\.relativePath))
        relevanceCache = (key, value)
        return value
    }

    /// The stats of each feed, for the Sources paper.
    func stats() -> [String: FeedStats] {
        FeedStats.compute(feeds: feeds.feeds, counts: feeds.articleCounts(days: FeedStats.days), notes: store.notes)
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
        guard !order.isEmpty else { return }
        let current = anchor.flatMap { order.firstIndex(of: $0) }
        let next = max(0, min(order.count - 1, (current ?? (delta > 0 ? -1 : order.count)) + delta))
        let ref = order[next]
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
        if !captures.isEmpty, captures.count == items.count, captures.allSatisfy(\.isKept) {
            store.setKept(false, Set(captures.map(\.id)))
            store.status = "Not kept"
            return
        }
        if !captures.isEmpty { store.setKept(true, Set(captures.map(\.id))) }
        let articles = items.filter { $0.kind == .article || $0.kind == .digest }.flatMap(\.articles)
        if !articles.isEmpty {
            store.keep(links: links(articles))
            feeds.setRead(true, articles)
        }
        for clip in items.compactMap(\.clip) { model.clipboard.save(clip.id) }
        store.status = "Kept"
    }

    // MARK: - Done

    /// Marks the items as done: a capture goes to Done, an article is read,
    /// and a clipboard text leaves the tray. Undo shows for a few seconds.
    func done(_ items: [StreamItem]) {
        let captures = items.compactMap(\.note)
        let reopen = !captures.isEmpty && captures.allSatisfy(\.isDone)
        let ids = Set(captures.map(\.id))
        if !ids.isEmpty { store.setDone(!reopen, ids) }
        let articles = items.filter { $0.kind == .article || $0.kind == .digest }.flatMap(\.articles).filter { !$0.read }
        feeds.setRead(true, articles)
        let clips = items.compactMap(\.clip).compactMap { model.clipboard.dismiss($0.id) }
        selection.subtract(items.map(\.id))
        let count = items.count
        offerUndo(reopen ? "Reopened \(Self.count(count))" : "Done · \(Self.count(count))") { [weak self] in
            guard let self else { return }
            if !ids.isEmpty { store.setDone(reopen, ids) }
            feeds.setRead(false, articles.map { var article = $0; article.read = true; return article })
            clips.forEach(model.clipboard.restore)
        }
    }

    // MARK: - File

    /// The places that the File picker offers for a search.
    func fileTargets(query: String) -> [FileTarget] {
        FileTarget.targets(sections: store.sections, roots: model.wikiPaths, active: model.wikiPath,
                           folders: model.folders, files: model.files.map(\.relativePath), query: query)
    }

    /// Files the items. A section takes the captures, and keeps an article or
    /// a clipboard text as a capture in it. A folder saves the items as a new
    /// file, and a file takes them at its end. Then the items are done.
    @discardableResult
    func file(_ items: [StreamItem], to target: FileTarget, now: Date = Date()) -> Bool {
        guard !items.isEmpty else { return false }
        switch target {
        case .section(let section):
            let ids = Set(items.compactMap(\.note).map(\.id))
            if !ids.isEmpty, !store.move(ids, to: section) { return false }
            let articles = items.filter { $0.kind == .article || $0.kind == .digest }.flatMap(\.articles)
            if !articles.isEmpty {
                store.keep(links: links(articles), to: section)
                feeds.setRead(true, articles)
            }
            for clip in items.compactMap(\.clip) {
                store.add(clip.text, source: "Clipboard", to: section, interpretSection: false)
            }
            store.status = "Filed in \(section)"
        case .folder(let root, let folder):
            let vault = Vault(root: URL(fileURLWithPath: (root as NSString).expandingTildeInPath).standardizedFileURL)
            let title = items.count == 1 ? Self.fileTitle(items[0]) : "Notes \(Self.day(now))"
            let text = items.count == 1 ? fileText(items[0], now: now) : items.map { appendText($0) }.joined(separator: "\n")
            let path = Self.freePath(folder: folder, name: ArticleMarkdown.fileName(for: title), in: vault.root)
            do { try vault.write(text, to: path) } catch { store.report(error); return false }
            finishFiling(items, savedFile: vault.root.appendingPathComponent(path).path)
            store.status = "Saved to " + target.title
            model.reload()
        case .file(let path):
            let vault = model.vault
            do {
                let current = (try? vault.read(path).text) ?? ""
                let block = items.map { appendText($0) }.joined(separator: "\n")
                let joined = current.isEmpty || current.hasSuffix("\n\n") ? current
                    : current.hasSuffix("\n") ? current + "\n" : current + "\n\n"
                try vault.write(joined + block, to: path)
            } catch { store.report(error); return false }
            finishFiling(items, savedFile: vault.root.appendingPathComponent(path).path)
            store.status = "Added to " + path
            model.reload()
        }
        selection.subtract(items.map(\.id))
        return true
    }

    // MARK: - Send

    /// Opens a draft with a skill of a folder for each item, or with the
    /// default skill of each item. An article goes as its link. A clipboard
    /// text goes to Inbox first.
    func send(_ items: [StreamItem], action: FolderAgents.Action?) {
        for item in items {
            if let clip = item.clip {
                model.agents.send(clip, from: model.clipboard, action: action)
            } else if let note = sendable(item) {
                model.agents.send(note, action: action)
            }
        }
    }

    /// Opens a new session about the item in the default folder, with the
    /// text of the item in the message field.
    func ask(_ item: StreamItem) {
        guard let folder = model.agents.defaultFolder ?? model.agents.folders.first, let note = sendable(item) else {
            store.report(PiperError("Add a folder with Claude skills in Settings > AI before you ask about a note."))
            return
        }
        let session = model.agents.newSession(in: folder.path, noteID: note.id)
        session.draft = note.text + "\n\n"
        model.agents.showDraft?(session.id)
    }

    // MARK: - Merge, Copy, and Delete

    /// Joins the selected captures into the first one.
    func merge(_ items: [StreamItem]) {
        let ids = items.compactMap(\.note).map(\.id)
        guard ids.count > 1 else { return }
        store.selection = Set(ids)
        store.merge()
        if let first = store.selection.first { select(.note(first)) }
        store.selection.removeAll()
    }

    /// Copies the text of each item: the text of a note, the link of a link
    /// or an article, and the links of a digest.
    func copy(_ items: [StreamItem], asList: Bool = false) {
        let texts = items.map(Self.copyText)
        let text = asList
            ? texts.enumerated().map { "\($0.offset + 1). " + $0.element.replacingOccurrences(of: "\n", with: "\n   ") }.joined(separator: "\n\n")
            : texts.joined(separator: "\n\n")
        if Self.copy(text) { store.status = "Copied" }
    }

    /// Deletes the captures, with Undo. An article becomes read, and a
    /// clipboard text leaves the tray.
    func delete(_ items: [StreamItem]) {
        let ids = Set(items.compactMap(\.note).map(\.id))
        let articles = items.filter { $0.kind == .article || $0.kind == .digest }.flatMap(\.articles).filter { !$0.read }
        feeds.setRead(true, articles)
        let clips = items.compactMap(\.clip).compactMap { model.clipboard.dismiss($0.id) }
        var deleted = false
        if !ids.isEmpty {
            store.selection = ids
            store.deleteSelection()
            deleted = store.selection.isEmpty
        }
        selection.subtract(items.map(\.id))
        offerUndo("Deleted \(Self.count(items.count))") { [weak self] in
            guard let self else { return }
            if deleted { store.undo() }
            feeds.setRead(false, articles.map { var article = $0; article.read = true; return article })
            clips.forEach(model.clipboard.restore)
        }
    }

    /// Puts the text on the clipboard as plain text.
    @discardableResult
    static func copy(_ text: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    // MARK: - Undo

    /// Runs the Undo of the last Done or Delete, while it shows.
    func runUndo() {
        guard let undo else { return }
        self.undo = nil
        undoTimer?.invalidate()
        undo.run()
    }

    private func offerUndo(_ message: String, run: @escaping () -> Void) {
        undoTimer?.invalidate()
        let offer = UndoOffer(message: message, run: run)
        undo = offer
        undoTimer = Timer.scheduledTimer(withTimeInterval: AppDefaults.Today.undoSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.undo?.id == offer.id { self?.undo = nil }
            }
        }
    }

    // MARK: - Private

    private func links(_ articles: [Article]) -> [KeptLink] {
        articles.compactMap { article in
            URL(string: article.url).map { KeptLink(url: $0, title: article.title, source: feeds.feed(article.feedID)?.title) }
        }
    }

    /// A note that a skill can take: the capture, or a note that is not
    /// saved and holds the link of an article or the links of a digest.
    private func sendable(_ item: StreamItem) -> Note? {
        if let note = item.note { return note }
        if let clip = item.clip { return Note(text: clip.text, section: store.activeSection) }
        let text = item.kind == .digest ? Self.copyText(item) : item.articles.first?.url ?? ""
        return text.isEmpty ? nil : Note(text: text, section: store.activeSection)
    }

    /// Marks the filed items as done, and records the file of a link capture.
    private func finishFiling(_ items: [StreamItem], savedFile: String) {
        for note in items.compactMap(\.note) where note.isArticle {
            store.updateReading(note.id) { $0.savedFile = savedFile; $0.savedAt = Date() }
        }
        let ids = Set(items.compactMap(\.note).map(\.id))
        if !ids.isEmpty { store.setDone(true, ids) }
        feeds.setRead(true, items.filter { $0.kind == .article || $0.kind == .digest }.flatMap(\.articles))
        items.compactMap(\.clip).forEach { model.clipboard.dismiss($0.id) }
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

    /// A path in the folder that no file has: the name, or the name with a number.
    private static func freePath(folder: String, name: String, in root: URL) -> String {
        let stem = (name as NSString).deletingPathExtension
        var path = (folder as NSString).appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) {
            path = (folder as NSString).appendingPathComponent("\(stem)-\(number).md")
            number += 1
        }
        return path
    }

    private static func day(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }

    static func count(_ value: Int) -> String {
        value == 1 ? "1 item" : "\(value) items"
    }
}
