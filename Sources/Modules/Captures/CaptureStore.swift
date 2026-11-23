import CapturesDatabase
import Foundation
import Observation
import PiperCore

/// The capture state and every change a reader can make to it.
///
/// Each change writes to the database first. The in-memory state moves only
/// after that write succeeds, so a failed write leaves the notes untouched and
/// throws its error to the caller.
@MainActor @Observable
public final class CaptureStore {

    // MARK: - Properties

    public private(set) var state = SavedState() {
        didSet { childIndex = Note.childrenByParent(state.notes) }
    }
    /// The child notes of each parent, oldest first. Each change of the state rebuilds it.
    private var childIndex: [UUID: [Note]] = [:]
    /// The error that stopped the database from opening. Each change then fails.
    public private(set) var loadError: Error?
    /// The note database. The app also keeps the agent sessions in it.
    public private(set) var database: Database?
    private var undoState: SavedState?
    public var notes: [Note] { state.notes }
    public var sections: [String] { state.sections }
    public var activeSection: String { state.activeSection }

    // MARK: - Initialization

    public init(url: URL? = nil) {
        do {
            let location = url ?? DataFolder.url.appendingPathComponent("notes.sqlite")
            let db = try Database(url: location)
            state = try Self.decode(db.load())
            childIndex = Note.childrenByParent(state.notes)
            database = db
            try prunePages()
        } catch { loadError = error }
    }

    // MARK: - Reading

    /// The notes whose parent is this note, oldest first.
    public func children(of id: UUID) -> [Note] {
        childIndex[id] ?? []
    }

    // MARK: - Undo

    public func undo() throws {
        guard var previous = undoState, let database else { return }
        if previous.sections.contains(activeSection) { previous.activeSection = activeSection }
        try database.save(JSONEncoder().encode(previous))
        state = previous
        undoState = nil
    }

    // MARK: - Changing Notes

    @discardableResult
    public func add(_ text: String, section: String, source: String? = nil, sourceURL: String? = nil,
                    tags: [String] = []) throws -> Note {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PiperError("The note has no text.") }
        guard sections.contains(section) else { throw PiperError("This section no longer exists. Choose another section.") }
        let url = CaptureLinks(text).standaloneURL
        let urls = Set([url, sourceURL.flatMap(URL.init(string:))].compactMap { value -> String? in
            guard let value, value.isWeb else { return nil }
            return value.absoluteString
        }).sorted()
        let note = Note(text: text, section: section, sources: source.map { [$0] } ?? [], sourceURLs: urls, tags: tags)
        try change { $0.notes.append(note) }
        return note
    }

    /// Adds a note under a parent, in the section of the parent.
    @discardableResult
    public func addChild(_ text: String, to parent: UUID, tags: [String], anchor: NoteAnchor? = nil, source: String? = nil) throws -> Note {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PiperError("The note has no text.") }
        guard let owner = notes.first(where: { $0.id == parent }) else {
            throw PiperError("This capture was removed. Open it again before you add a note.")
        }
        let note = Note(text: text, section: owner.section, sources: source.map { [$0] } ?? [], sourceURLs: owner.sourceURLs,
                        parent: parent, tags: tags, anchor: anchor)
        try change { $0.notes.append(note) }
        return note
    }

    /// Finds the note that holds the highlights of a local page, or adds one.
    /// The link names the page and is not a web link.
    public func pageNote(for link: String, title: String, source: String) throws -> Note {
        if let existing = notes.first(where: { $0.parent == nil && $0.sourceURLs.contains(link) }) { return existing }
        let note = Note(text: title, section: activeSection, sources: [source], sourceURLs: [link])
        try change { $0.notes.append(note) }
        return note
    }

    /// Adds a paragraph to the end of a note, such as an answer from Claude.
    public func append(_ paragraph: String, to id: UUID) throws {
        let paragraph = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !paragraph.isEmpty else { return }
        guard notes.contains(where: { $0.id == id }) else { throw PiperError("This note was removed.") }
        try change(recordUndo: false) { state in
            guard let i = state.notes.firstIndex(where: { $0.id == id }) else { return }
            state.notes[i].text += "\n\n" + paragraph
            state.notes[i].modifiedAt = Date()
        }
    }

    /// Makes a section active. A name that no section has adds a section.
    public func chooseSection(_ name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains(where: \.isNewline), name.count <= 80 else {
            throw PiperError("Use a section name with 1 to 80 characters on one line.")
        }
        if let existing = sections.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            guard existing != activeSection else { return }
            return try change(recordUndo: false) { $0.activeSection = existing }
        }
        try change { $0.sections.append(name); $0.activeSection = name }
    }

    public func renameSection(_ section: String, to name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard section != Note.inbox, sections.contains(section) else { return }
        guard !name.isEmpty, !name.contains(where: \.isNewline), name.count <= 80 else {
            throw PiperError("Use a section name with 1 to 80 characters on one line.")
        }
        guard !sections.contains(where: { $0 != section && $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw PiperError("A section with this name already exists. Choose another name.")
        }
        try change { state in
            if let index = state.sections.firstIndex(of: section) { state.sections[index] = name }
            for index in state.notes.indices where state.notes[index].section == section {
                state.notes[index].section = name
            }
            if state.activeSection == section { state.activeSection = name }
        }
    }

    /// Removes a section and moves its notes to Inbox.
    public func deleteSection(_ section: String) throws {
        guard section != Note.inbox, sections.contains(section), sections.contains(Note.inbox) else { return }
        try change { state in
            state.sections.removeAll { $0 == section }
            for index in state.notes.indices where state.notes[index].section == section {
                state.notes[index].section = Note.inbox
                state.notes[index].modifiedAt = Date()
            }
            if state.activeSection == section { state.activeSection = Note.inbox }
        }
    }

    /// Replaces the text of a note.
    ///
    /// - Parameter originalText: The text that the editor opened. A note that
    ///   changed since then is not overwritten.
    public func update(_ id: UUID, text: String, sourceURL: String? = nil, originalText: String? = nil) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PiperError("The note has no text.") }
        guard let current = notes.first(where: { $0.id == id }) else {
            throw PiperError("This note was removed. Copy your changes into a new note.")
        }
        if let originalText, originalText != current.text {
            throw PiperError("This note changed in another editor. Copy your changes before reopening the note.")
        }
        if current.text == text, sourceURL == nil { return }
        try change { state in
            guard let i = state.notes.firstIndex(where: { $0.id == id }) else { return }
            state.notes[i].text = text
            state.notes[i].modifiedAt = Date()
            if let sourceURL { state.notes[i].sourceURLs = sourceURL.isEmpty ? [] : [sourceURL] }
        }
    }

    public func toggleDone(_ id: UUID) throws {
        try change { state in
            guard let i = state.notes.firstIndex(where: { $0.id == id }) else { return }
            state.notes[i].isDone.toggle()
            state.notes[i].modifiedAt = Date()
        }
    }

    /// Marks the captures as done, or as not done, with one undo step.
    public func setDone(_ done: Bool, _ ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        try change { state in
            for i in state.notes.indices where ids.contains(state.notes[i].id) && state.notes[i].isDone != done {
                state.notes[i].isDone = done
                state.notes[i].modifiedAt = Date()
            }
        }
    }

    /// Adds or removes the kept tag of the captures, with one undo step.
    public func setKept(_ kept: Bool, _ ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        try change { state in
            for i in state.notes.indices where ids.contains(state.notes[i].id) && state.notes[i].isKept != kept {
                if kept { state.notes[i].tags.append(NoteTag.kept.rawValue) } else { state.notes[i].tags.removeAll { $0 == NoteTag.kept.rawValue } }
            }
        }
    }

    /// Adds a kept link capture for each web link that no capture holds, with
    /// one undo step. A link that a capture holds already gets the kept tag.
    /// Returns the captures of the links, in the order of the links.
    ///
    /// - Parameter recordUndo: False for a copy that Undo must not remove, such
    ///   as `StarMigration`. The undo step before the copy goes too.
    @discardableResult
    public func keep(links: [KeptLink], to section: String? = nil, recordUndo: Bool = true) throws -> [Note] {
        let destination = section.flatMap { sections.contains($0) ? $0 : nil } ?? activeSection
        var seen: Set<String> = []
        let fresh = links.filter { link in
            link.url.isWeb && article(for: link.url) == nil && seen.insert(CaptureLinks.canonical(link.url)).inserted
        }
        let existing = Set(links.compactMap { article(for: $0.url)?.id })
        let added = fresh.map { link in
            Note(text: link.url.absoluteString, section: destination, sources: link.source.map { [$0] } ?? [],
                 sourceURLs: [link.url.absoluteString], tags: [NoteTag.kept.rawValue], reading: Reading(title: link.title))
        }
        try change(recordUndo: recordUndo) { state in
            state.notes += added
            for i in state.notes.indices where existing.contains(state.notes[i].id) && !state.notes[i].isKept {
                state.notes[i].tags.append(NoteTag.kept.rawValue)
            }
        }
        // Undo restores a whole state. An older state has no copy, so it goes.
        if !recordUndo { undoState = nil }
        return links.compactMap { article(for: $0.url) }
    }

    /// Moves the captures and their child notes to a section, with one undo step.
    public func move(_ ids: Set<UUID>, to section: String) throws {
        guard !ids.isEmpty else { return }
        guard sections.contains(section) else { throw PiperError("This section no longer exists. Choose another section.") }
        try change { state in
            for i in state.notes.indices where ids.contains(state.notes[i].id) || state.notes[i].parent.map(ids.contains) == true {
                state.notes[i].section = section
                state.notes[i].modifiedAt = Date()
            }
        }
    }

    /// Joins the notes into the first of them, in the order of the sections
    /// and of the notes. The child notes move to that note.
    @discardableResult
    public func merge(_ ids: [UUID]) throws -> Note {
        let chosen = Set(ids)
        let selected = sections.flatMap { section in notes.filter { $0.section == section && chosen.contains($0.id) } }
        guard selected.count > 1, let first = selected.first else { throw PiperError("Choose two or more notes to merge.") }
        try change { state in
            guard let i = state.notes.firstIndex(where: { $0.id == first.id }) else { return }
            state.notes[i].text = selected.map(\.text).joined(separator: "\n\n")
            state.notes[i].sources = Array(Set(selected.flatMap(\.sources))).sorted()
            state.notes[i].sourceURLs = Array(Set(selected.flatMap(\.sourceURLs))).sorted()
            state.notes[i].isDone = selected.allSatisfy(\.isDone)
            state.notes[i].modifiedAt = Date()
            state.notes.removeAll { chosen.contains($0.id) && $0.id != first.id }
            for index in state.notes.indices where state.notes[index].parent.map(chosen.contains) == true {
                state.notes[index].parent = first.id
            }
        }
        return notes.first { $0.id == first.id } ?? first
    }

    /// Deletes the notes and every note under them, with one undo step.
    public func delete(_ ids: [UUID]) throws {
        try remove(Set(ids))
    }

    // MARK: - Reading

    /// The link capture of a web link, in any section. Links that differ only
    /// in tracking parameters, the fragment, or `www.` name one article.
    public func article(for url: URL) -> Note? {
        let key = CaptureLinks.canonical(url)
        return notes.first { note in
            note.isArticle && note.articleURL.map(CaptureLinks.canonical) == key
        }
    }

    /// Finds the link capture of a web link, or adds one.
    ///
    /// A done capture opens again, because the reader came back to it. A title
    /// fills a capture that has none.
    @discardableResult
    public func saveArticle(_ url: URL, title: String? = nil, source: String? = nil, to section: String? = nil) throws -> Note {
        guard url.isWeb else { throw PiperError("Piper can save only web pages.") }
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if let existing = article(for: url) {
            try change(recordUndo: false) { state in
                guard let i = state.notes.firstIndex(where: { $0.id == existing.id }) else { return }
                if state.notes[i].isDone { state.notes[i].isDone = false; state.notes[i].modifiedAt = Date() }
                var reading = state.notes[i].reading ?? Reading()
                if reading.title == nil { reading.title = title }
                state.notes[i].reading = reading
            }
            return notes.first { $0.id == existing.id } ?? existing
        }
        let destination = section.flatMap { sections.contains($0) ? $0 : nil } ?? activeSection
        let note = Note(text: url.absoluteString, section: destination, sources: source.map { [$0] } ?? [],
                        sourceURLs: [url.absoluteString], reading: Reading(title: title))
        try change { $0.notes.append(note) }
        return note
    }

    /// Saves a selection from a web page as a highlight under the link capture
    /// of the page. The capture is added first when Piper does not have it.
    ///
    /// The quote has one space for each run of white space, as the Reader tab
    /// has, so the highlight finds its place in the article.
    @discardableResult
    public func saveHighlight(_ selection: String, in url: URL, title: String? = nil, source: String? = nil,
                              to section: String? = nil, tags: [String]) throws -> (article: Note, highlight: Note) {
        let quote = NoteAnchor.normalized(selection)
        guard !quote.isEmpty else { throw PiperError("The selection has no text.") }
        let article = try saveArticle(url, title: title, source: source, to: section)
        let highlight = try addChild(quote, to: article.id, tags: tags,
                                     anchor: NoteAnchor(quote: quote, block: -1, offset: 0), source: source)
        return (article, highlight)
    }

    /// Adds the note of the reader after the quote of a highlight.
    public func comment(_ comment: String, on id: UUID) throws {
        let comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !comment.isEmpty else { return }
        try change { state in
            guard let i = state.notes.firstIndex(where: { $0.id == id }) else { return }
            state.notes[i].text = HighlightText.adding(comment, to: state.notes[i].text)
            state.notes[i].modifiedAt = Date()
        }
    }

    /// Changes the reading state of a link capture. The change has no undo
    /// step, because scrolling is not an edit.
    public func updateReading(_ id: UUID, _ update: (inout Reading) -> Void) throws {
        try change(recordUndo: false) { state in
            guard let i = state.notes.firstIndex(where: { $0.id == id }) else { return }
            var reading = state.notes[i].reading ?? Reading()
            update(&reading)
            state.notes[i].reading = reading
        }
    }

    /// Marks as done each article that left Finished of the reading list.
    public func archiveFinishedReading(now: Date = Date()) throws {
        let date = ReadingList.finishedCutoff(now: now)
        try change(recordUndo: false) { state in
            for i in state.notes.indices {
                guard !state.notes[i].isDone, let finished = state.notes[i].reading?.finishedAt, finished < date else { continue }
                state.notes[i].isDone = true
                state.notes[i].modifiedAt = Date()
            }
        }
    }

    /// Keeps the text of a page that a browser showed, for a page that Piper
    /// cannot load itself, such as a page behind a login.
    public func savePageText(_ text: String, for url: URL) throws {
        guard !text.isEmpty else { return }
        try openDatabase().savePage(url: CaptureLinks.canonical(url), text: text)
    }

    /// The text of a page that a browser showed. Nil when Piper kept none.
    public func pageText(for url: URL) throws -> String? {
        try openDatabase().loadPage(url: CaptureLinks.canonical(url))
    }

    /// Removes the page text that no link capture uses. A capture that Undo
    /// can bring back keeps its page text.
    private func prunePages() throws {
        let database = try openDatabase()
        let kept = Set((state.notes + (undoState?.notes ?? [])).compactMap { note -> String? in
            guard note.parent == nil, note.isArticle else { return nil }
            return note.articleURL.map(CaptureLinks.canonical)
        })
        for url in try database.pageURLs() where !kept.contains(url) {
            try database.deletePage(url: url)
        }
    }
}

/// A web link that Keep saves as a link capture.
public struct KeptLink: Equatable, Sendable {
    public let url: URL
    public let title: String?
    public let source: String?

    public init(url: URL, title: String? = nil, source: String? = nil) {
        self.url = url
        self.title = title
        self.source = source
    }
}

// MARK: - Private

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension CaptureStore {

    /// Removes the notes and every note under them, then the page text that only they used.
    func remove(_ selected: Set<UUID>) throws {
        guard !selected.isEmpty else { return }
        var ids = selected
        var level = selected
        while !level.isEmpty {
            level = Set(level.flatMap { children(of: $0).map(\.id) }).subtracting(ids)
            ids.formUnion(level)
        }
        let removesArticle = notes.contains { ids.contains($0.id) && $0.parent == nil && $0.isArticle }
        try change { state in
            state.notes.removeAll { ids.contains($0.id) }
        }
        if removesArticle { try prunePages() }
    }

    /// Reads the stored blob. An empty database starts a new state.
    static func decode(_ data: Data?) throws -> SavedState {
        guard let data else { return SavedState() }
        let state = try JSONDecoder().decode(SavedState.self, from: data)
        guard !state.sections.isEmpty, Set(state.sections).count == state.sections.count,
              state.sections.contains(state.activeSection), Set(state.notes.map(\.id)).count == state.notes.count,
              state.notes.allSatisfy({ state.sections.contains($0.section) }) else {
            throw PiperError("The note database contains invalid records. Restore a backup before adding notes.")
        }
        return state
    }

    func openDatabase() throws -> Database {
        guard let database else {
            throw PiperError("The note database is unavailable. Restart Piper after resolving the database error.")
        }
        return database
    }

    func change(recordUndo: Bool = true, _ update: (inout SavedState) -> Void) throws {
        let database = try openDatabase()
        var candidate = state
        update(&candidate)
        guard candidate != state else { return }
        try database.save(JSONEncoder().encode(candidate))
        if recordUndo { undoState = state }
        state = candidate
    }
}
