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

    public private(set) var state = SavedState()
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
            database = db
        } catch { report(error) }
    }

    // MARK: - Errors

    public func report(_ error: Error) { errorMessage = error.localizedDescription; status = error.localizedDescription }

    // MARK: - Reading

    public func visibleNotes(in section: String) -> [Note] {
        notes.filter { $0.section == section && (query.isEmpty || ($0.text + section).localizedCaseInsensitiveContains(query)) }
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
            for i in state.notes.indices where selection.contains(state.notes[i].id) { state.notes[i].section = section; state.notes[i].modifiedAt = Date() }
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
        }) { selection = [first.id]; status = "Notes merged · Undo available" }
    }

    public func deleteSelection() {
        if change({ $0.notes.removeAll { selection.contains($0.id) } }) { selection.removeAll() }
    }

    // MARK: - Clipboard

    public func copyText(asList: Bool) -> String {
        selectedNotes.enumerated().map { index, note in
            asList ? "\(index + 1). \(note.text.replacingOccurrences(of: "\n", with: "\n   "))" : note.text
        }.joined(separator: "\n\n")
    }

    public func copy(asList: Bool) {
        guard !selection.isEmpty else { return }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(copyText(asList: asList), forType: .string) {
            NSPasteboard.general.setData(Data(), forType: ClipboardInbox.copiedNoteType)
            status = "Copied"
        }
        else { report(PiperError("Cannot write to the clipboard.")) }
    }

    @discardableResult public func captureClipboard(from pasteboard: NSPasteboard = .general) -> Bool {
        guard let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = "The clipboard has no text"; return false }
        return add(text, source: "Clipboard", interpretSection: false)
    }
}

// MARK: - Private

private extension CaptureStore {

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
