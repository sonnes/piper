import AppKit
import CapturesDatabase
import Foundation
import Observation
import PiperCore

/// The capture state and every change a reader can make to it.
///
/// Each change writes to the database first. The in-memory state moves only
/// after that write succeeds, so a failed write leaves the notes untouched.
@MainActor @Observable
public final class CaptureStore {

    // MARK: - Properties

    public private(set) var state = SavedState() {
        didSet { childIndex = Self.childIndex(of: state.notes) }
    }
    /// The child notes of each parent, oldest first. Each change of the state rebuilds it.
    public private(set) var childIndex: [UUID: [Note]] = [:]
    public var query = ""
    public var selection: Set<UUID> = []
    public var status = "Local notes"
    public var errorMessage: String?
    /// The note database. Other stores add their own tables to it.
    public private(set) var database: Database?
    private var undoState: SavedState?
    public var notes: [Note] { state.notes }
    public var sections: [String] { state.sections }
    public var canUndo: Bool { undoState != nil }
    public var activeSection: String {
        get { state.activeSection }
        set {
            guard sections.contains(newValue), newValue != activeSection else { return }
            _ = change(recordUndo: false) { $0.activeSection = newValue }
        }
    }

    public var selectedNotes: [Note] {
        sections.flatMap { section in notes.filter { $0.section == section && selection.contains($0.id) } }
    }

    // MARK: - Initialization

    public init(url: URL? = nil) {
        do {
            let location = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Piper/notes.sqlite")
            let db = try Database(url: location)
            state = try Self.decode(db.load())
            childIndex = Self.childIndex(of: state.notes)
            database = db
            prunePages()
        } catch { report(error) }
    }

    // MARK: - Errors

    public func report(_ error: Error) { errorMessage = error.localizedDescription; status = error.localizedDescription }

    // MARK: - Reading

    /// The notes of a section without a parent. A child note shows under its
    /// parent, and a search that matches a child finds the parent.
    public func visibleNotes(in section: String, archived: Bool = false) -> [Note] {
        let ids = Set(notes.map(\.id))
        return notes.filter { note in
            guard note.section == section, note.isDone == archived, note.parent.map(ids.contains) != true else { return false }
            return query.isEmpty || ([note.text, section] + children(of: note.id).map(\.text))
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    /// The notes whose parent is this note, oldest first.
    public func children(of id: UUID) -> [Note] {
        childIndex[id] ?? []
    }

    public func toggleSelection(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    // MARK: - Undo

    public func undo() {
        guard var previous = undoState, let database else { return }
        if previous.sections.contains(activeSection) { previous.activeSection = activeSection }
        do {
            try database.save(JSONEncoder().encode(previous))
            state = previous
            undoState = nil
            selection = selection.intersection(Set(notes.map(\.id)))
            status = "Last note change undone"
        } catch { report(error) }
    }

    // MARK: - Changing Notes

    @discardableResult public func add(_ text: String, source: String? = nil, sourceURL: String? = nil, to section: String? = nil, interpretSection: Bool = true) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if interpretSection, text.hasPrefix("# "), !text.contains("\n") {
            let name = String(text.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return false }
            return chooseSection(name)
        }
        let destination = section ?? activeSection
        guard sections.contains(destination) else { report(PiperError("This section no longer exists. Choose another section.")); return false }
        let url = CaptureLinks(text).standaloneURL
        let urls = Set([url, sourceURL.flatMap(URL.init(string:))].compactMap { value -> String? in
            guard let value, CaptureLinks.isWebURL(value) else { return nil }
            return value.absoluteString
        }).sorted()
        let saved = change { $0.notes.append(Note(text: text, section: destination, sources: source.map { [$0] } ?? [], sourceURLs: urls)) }
        if saved { status = "Saved to \(destination)" }
        return saved
    }

    /// Adds a note under a parent, in the section of the parent.
    @discardableResult public func addChild(_ text: String, to parent: UUID, tags: [String], anchor: NoteAnchor? = nil, source: String? = nil) -> Note? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let owner = notes.first(where: { $0.id == parent }) else {
            report(PiperError("This capture was removed. Open it again before you add a note."))
            return nil
        }
        let note = Note(text: text, section: owner.section, sources: source.map { [$0] } ?? [], sourceURLs: owner.sourceURLs,
                        parent: parent, tags: tags, anchor: anchor)
        guard change({ $0.notes.append(note) }) else { return nil }
        status = "Saved under the capture"
        return note
    }

    /// Adds a paragraph to the end of a note, such as an answer from Claude.
    @discardableResult public func append(_ paragraph: String, to id: UUID) -> Bool {
        let paragraph = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !paragraph.isEmpty, notes.contains(where: { $0.id == id }) else { return false }
        return change(recordUndo: false) { state in
            guard let i = state.notes.firstIndex(where: { $0.id == id }) else { return }
            state.notes[i].text += "\n\n" + paragraph
            state.notes[i].modifiedAt = Date()
        }
    }

    /// Adds a tag. A tag is one word in lowercase, without a leading `#`.
    @discardableResult public func addTag(_ tag: String, to id: UUID) -> Bool {
        let tag = tag.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "#"))).lowercased()
        guard !tag.isEmpty, !tag.contains(where: \.isWhitespace), tag.count <= 40 else {
            report(PiperError("Use a tag with 1 to 40 characters and no spaces."))
            return false
        }
        return change { state in
            guard let i = state.notes.firstIndex(where: { $0.id == id }), !state.notes[i].tags.contains(tag) else { return }
            state.notes[i].tags.append(tag)
            state.notes[i].modifiedAt = Date()
        }
    }

    @discardableResult public func chooseSection(_ name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains(where: \.isNewline), name.count <= 80 else {
            report(PiperError("Use a section name with 1 to 80 characters on one line."))
            return false
        }
        if let existing = sections.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            return change(recordUndo: false) { $0.activeSection = existing }
        }
        return change { $0.sections.append(name); $0.activeSection = name }
    }

    @discardableResult public func renameSection(_ section: String, to name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard section != "Inbox", sections.contains(section) else { return false }
        guard !name.isEmpty, !name.contains(where: \.isNewline), name.count <= 80 else {
            report(PiperError("Use a section name with 1 to 80 characters on one line."))
            return false
        }
        guard !sections.contains(where: { $0 != section && $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            report(PiperError("A section with this name already exists. Choose another name."))
            return false
        }
        let saved = change { state in
            if let index = state.sections.firstIndex(of: section) { state.sections[index] = name }
            for index in state.notes.indices where state.notes[index].section == section {
                state.notes[index].section = name
            }
            if state.activeSection == section { state.activeSection = name }
        }
        if saved { status = "Section renamed · Undo available" }
        return saved
    }

    @discardableResult public func deleteSection(_ section: String) -> Bool {
        guard section != "Inbox", sections.contains(section), sections.contains("Inbox") else { return false }
        let saved = change { state in
            state.sections.removeAll { $0 == section }
            for index in state.notes.indices where state.notes[index].section == section {
                state.notes[index].section = "Inbox"
                state.notes[index].modifiedAt = Date()
            }
            if state.activeSection == section { state.activeSection = "Inbox" }
        }
        if saved { status = "Section deleted · Notes moved to Inbox · Undo available" }
        return saved
    }

    @discardableResult public func update(_ id: UUID, text: String, sourceURL: String? = nil, originalText: String? = nil) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let current = notes.first(where: { $0.id == id }) else { report(PiperError("This note was removed. Copy your changes into a new note.")); return false }
        if let originalText, originalText != current.text {
            report(PiperError("This note changed in another editor. Copy your changes before reopening the note."))
            return false
        }
        if current.text == text, sourceURL == nil { return true }
        return change { state in
            guard let i = state.notes.firstIndex(where: { $0.id == id }) else { return }
            state.notes[i].text = text
            state.notes[i].modifiedAt = Date()
            if let sourceURL { state.notes[i].sourceURLs = sourceURL.isEmpty ? [] : [sourceURL] }
        }
    }

    public func toggleDone(_ id: UUID) {
        _ = change { state in
            guard let i = state.notes.firstIndex(where: { $0.id == id }) else { return }
            state.notes[i].isDone.toggle()
            state.notes[i].modifiedAt = Date()
        }
    }

    public func completeSelection() {
        let done = !selectedNotes.allSatisfy(\.isDone)
        _ = change { state in
            for i in state.notes.indices where selection.contains(state.notes[i].id) { state.notes[i].isDone = done; state.notes[i].modifiedAt = Date() }
        }
    }

    public func move(to section: String) {
        guard sections.contains(section), !selection.isEmpty else { return }
        _ = change { state in
            for i in state.notes.indices where selection.contains(state.notes[i].id) || state.notes[i].parent.map(selection.contains) == true {
                state.notes[i].section = section
                state.notes[i].modifiedAt = Date()
            }
        }
    }

    public func merge() {
        let selected = selectedNotes
        guard selected.count > 1, let first = selected.first else { return }
        if change({ state in
            guard let i = state.notes.firstIndex(where: { $0.id == first.id }) else { return }
            state.notes[i].text = selected.map(\.text).joined(separator: "\n\n")
            state.notes[i].sources = Array(Set(selected.flatMap(\.sources))).sorted()
            state.notes[i].sourceURLs = Array(Set(selected.flatMap(\.sourceURLs))).sorted()
            state.notes[i].isDone = selected.allSatisfy(\.isDone)
            state.notes[i].modifiedAt = Date()
            state.notes.removeAll { selection.contains($0.id) && $0.id != first.id }
            for index in state.notes.indices where state.notes[index].parent.map(selection.contains) == true {
                state.notes[index].parent = first.id
            }
        }) { selection = [first.id]; status = "Notes merged · Undo available" }
    }

    public func deleteSelection() {
        if remove(selection) { selection.removeAll() }
    }

    /// Deletes one note and its child notes, with an undo step. The selection
    /// keeps the notes that remain.
    @discardableResult public func delete(_ id: UUID) -> Bool {
        guard remove([id]) else { return false }
        selection = selection.intersection(Set(notes.map(\.id)))
        return true
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
    public func saveArticle(_ url: URL, title: String? = nil, source: String? = nil, to section: String? = nil) -> Note? {
        guard CaptureLinks.isWebURL(url) else { report(PiperError("Piper can save only web pages.")); return nil }
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if let existing = article(for: url) {
            let saved = change(recordUndo: false) { state in
                guard let i = state.notes.firstIndex(where: { $0.id == existing.id }) else { return }
                if state.notes[i].isDone { state.notes[i].isDone = false; state.notes[i].modifiedAt = Date() }
                var reading = state.notes[i].reading ?? Reading()
                if reading.title == nil { reading.title = title }
                state.notes[i].reading = reading
            }
            status = "Already in Reading"
            return saved ? notes.first { $0.id == existing.id } : nil
        }
        let destination = section.flatMap { sections.contains($0) ? $0 : nil } ?? activeSection
        let note = Note(text: url.absoluteString, section: destination, sources: source.map { [$0] } ?? [],
                        sourceURLs: [url.absoluteString], reading: Reading(title: title))
        guard change({ $0.notes.append(note) }) else { return nil }
        status = "Saved to Reading"
        return note
    }

    /// Saves a selection from a web page as a highlight under the link capture
    /// of the page. The capture is added first when Piper does not have it.
    ///
    /// The quote has one space for each run of white space, as the Reader tab
    /// has, so the highlight finds its place in the article.
    @discardableResult
    public func saveHighlight(_ selection: String, in url: URL, title: String? = nil, source: String? = nil,
                              to section: String? = nil, tags: [String]) -> (article: Note, highlight: Note)? {
        let quote = NoteAnchor.normalized(selection)
        guard !quote.isEmpty, let article = saveArticle(url, title: title, source: source, to: section),
              let highlight = addChild(quote, to: article.id, tags: tags,
                                       anchor: NoteAnchor(quote: quote, block: -1, offset: 0), source: source) else { return nil }
        status = "Highlighted"
        return (article, highlight)
    }

    /// Adds the note of the reader after the quote of a highlight.
    @discardableResult public func comment(_ comment: String, on id: UUID) -> Bool {
        let comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !comment.isEmpty else { return true }
        return change { state in
            guard let i = state.notes.firstIndex(where: { $0.id == id }) else { return }
            state.notes[i].text = HighlightText.adding(comment, to: state.notes[i].text)
            state.notes[i].modifiedAt = Date()
        }
    }

    /// Changes the reading state of a link capture. The change has no undo
    /// step, because scrolling is not an edit.
    @discardableResult public func updateReading(_ id: UUID, _ update: (inout Reading) -> Void) -> Bool {
        change(recordUndo: false) { state in
            guard let i = state.notes.firstIndex(where: { $0.id == id }) else { return }
            var reading = state.notes[i].reading ?? Reading()
            update(&reading)
            state.notes[i].reading = reading
        }
    }

    /// Marks as done each article that the reader finished before the date.
    public func archiveFinishedReading(before date: Date) {
        _ = change(recordUndo: false) { state in
            for i in state.notes.indices {
                guard !state.notes[i].isDone, let finished = state.notes[i].reading?.finishedAt, finished < date else { continue }
                state.notes[i].isDone = true
                state.notes[i].modifiedAt = Date()
            }
        }
    }

    /// Keeps the text of a page that a browser showed, for a page that Piper
    /// cannot load itself, such as a page behind a login.
    public func savePageText(_ text: String, for url: URL) {
        guard let database, !text.isEmpty else { return }
        do { try database.savePage(url: CaptureLinks.canonical(url), text: text) } catch { report(error) }
    }

    /// The text of a page that a browser showed, if Piper kept it.
    public func pageText(for url: URL) -> String? {
        try? database?.loadPage(url: CaptureLinks.canonical(url))
    }

    /// Removes the page text that no link capture uses. A capture that Undo
    /// can bring back keeps its page text.
    public func prunePages() {
        guard let database else { return }
        let kept = Set((state.notes + (undoState?.notes ?? [])).compactMap { note -> String? in
            guard note.parent == nil, note.isArticle else { return nil }
            return note.articleURL.map(CaptureLinks.canonical)
        })
        do {
            for url in try database.pageURLs() where !kept.contains(url) {
                try database.deletePage(url: url)
            }
        } catch { report(error) }
    }

    // MARK: - Clipboard

    public func copyText(asList: Bool) -> String {
        selectedNotes.enumerated().map { index, note in
            asList ? "\(index + 1). \(note.text.replacingOccurrences(of: "\n", with: "\n   "))" : note.text
        }.joined(separator: "\n\n")
    }

    public func copy(asList: Bool) {
        guard !selection.isEmpty else { return }
        write(copyText(asList: asList))
    }

    /// Copies the text of one note.
    public func copy(_ id: UUID, to pasteboard: NSPasteboard = .general) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        write(note.text, to: pasteboard)
    }

    @discardableResult public func captureClipboard(from pasteboard: NSPasteboard = .general) -> Bool {
        guard let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = "The clipboard has no text"; return false }
        return add(text, source: "Clipboard", interpretSection: false)
    }
}

// MARK: - Private

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension CaptureStore {

    static func childIndex(of notes: [Note]) -> [UUID: [Note]] {
        Dictionary(grouping: notes.filter { $0.parent != nil }, by: { $0.parent! })
    }

    /// Removes the notes and every note under them, then the page text that only they used.
    func remove(_ selected: Set<UUID>) -> Bool {
        guard !selected.isEmpty else { return false }
        var ids = selected
        var level = selected
        while !level.isEmpty {
            level = Set(level.flatMap { children(of: $0).map(\.id) }).subtracting(ids)
            ids.formUnion(level)
        }
        let removesArticle = notes.contains { ids.contains($0.id) && $0.parent == nil && $0.isArticle }
        let removed = change { state in
            state.notes.removeAll { ids.contains($0.id) }
        }
        if removed, removesArticle { prunePages() }
        return removed
    }

    /// Writes text to the clipboard. The marker keeps the copy out of the clipboard history.
    func write(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        if pasteboard.setString(text, forType: .string) {
            pasteboard.setData(Data(), forType: ClipboardInbox.copiedNoteType)
            status = "Copied"
        } else {
            report(PiperError("Cannot write to the clipboard."))
        }
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

    @discardableResult func change(recordUndo: Bool = true, _ update: (inout SavedState) -> Void) -> Bool {
        guard let database else { report(PiperError("The note database is unavailable. Restart Piper after resolving the database error.")); return false }
        var candidate = state
        update(&candidate)
        guard candidate != state else { return true }
        do {
            try database.save(JSONEncoder().encode(candidate))
            if recordUndo { undoState = state }
            state = candidate
            return true
        } catch { report(error); return false }
    }
}
