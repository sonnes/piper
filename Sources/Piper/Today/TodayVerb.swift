import Captures
import Stream
import SwiftUI

/// A verb of the rows of Today, such as Keep or Done.
///
/// `TodayVerb.all` is the one table of the verbs. The keys of Today, the
/// selection bar, the round buttons of a row, the More menu and the context
/// menu of a row, and the accessibility hint of a row come from it. To add a
/// verb, add one entry here and one method on `TodayModel`.
@MainActor
struct TodayVerb: Identifiable {

    /// The state of a row that changes the title and the symbol of a verb.
    struct Mark {
        var kept = false
        var done = false

        init(kept: Bool = false, done: Bool = false) {
            self.kept = kept
            self.done = done
        }

        init(_ item: StreamItem) {
            kept = item.note?.isKept == true
            done = item.state == .done
        }
    }

    /// The rows that a verb acts on, and the actions of the view.
    struct Context {
        let today: TodayModel
        /// The rows that the verb acts on.
        let items: [StreamItem]
        /// The row of a button or a menu, or the first selected row for a key.
        let first: StreamItem?
        let open: (StreamItem) -> Void
        /// Edits a capture in a sheet over the paper.
        let edit: (Note) -> Void
        /// Edits a capture in a window of its own.
        let editInWindow: (Note) -> Void
    }

    /// Where a verb shows, apart from its keys.
    enum Place {
        /// A round button on the row.
        case row
        /// A button on the floating bar of a selection of several rows.
        case bar
    }

    /// The name of the verb in the hint strip, such as "keep". It is unique.
    let id: String
    /// The label on the selection bar, and the start of the help text of a button.
    let name: String
    /// The title of the item in the menu of a row.
    let title: (Mark) -> String
    /// The keys of the verb. The first key shows in the help text of a button.
    var keys: [CommandKey] = []
    /// The SF Symbol of the round button.
    var symbol: (Mark) -> String = { _ in "" }
    /// True when the round button shows in the accent color, such as Keep on a kept row.
    var highlights: (Mark) -> Bool = { _ in false }
    /// The help text of the round button, when it differs from "Name · Key".
    var markHelp: (Mark) -> String? = { _ in nil }
    /// The words of the accessibility hint of a row, such as "keeps".
    var hint: String?
    var places: Set<Place> = []
    /// The verb shows a menu of the skills in place of a button.
    var listsSkills = false
    var animates = false
    var isDestructive = false
    /// True when the verb can act on the rows of the context.
    var isAvailable: @MainActor (Context) -> Bool = { !$0.items.isEmpty }
    let run: @MainActor (Context) -> Void

    /// The first key, as the help text and the selection bar show it, such as K.
    var glyph: String { keys.first?.glyph ?? "" }

    /// The help text of a button, such as "Keep · K".
    func help(_ mark: Mark = Mark()) -> String {
        markHelp(mark) ?? name + " · " + glyph
    }
}

// MARK: - Table

extension TodayVerb {
    static let open = TodayVerb(id: "open as a paper", name: "Open", title: { _ in "Open" }, keys: [.enter]) {
        if let first = $0.first { $0.open(first) }
    }

    static let keep = TodayVerb(
        id: "keep", name: "Keep", title: { $0.kept ? "Remove Keep" : "Keep" }, keys: [CommandKey("k", [])],
        symbol: { $0.kept ? "star.fill" : "star" }, highlights: { $0.kept }, markHelp: { $0.kept ? "Kept · K removes the mark" : nil }, hint: "keeps",
        places: [.row, .bar], animates: true
    ) { $0.today.keep($0.items) }

    static let done = TodayVerb(
        id: "done", name: "Done", title: { $0.done ? "Reopen" : "Done" }, keys: [CommandKey("e", []), .space],
        symbol: { $0.done ? "arrow.uturn.backward" : "checkmark" }, markHelp: { $0.done ? "Reopen · E" : nil }, hint: "marks as done",
        places: [.row, .bar], animates: true
    ) { $0.today.done($0.items) }

    static let file = TodayVerb(
        id: "file", name: "File", title: { _ in "File…" }, keys: [CommandKey("f", [])],
        symbol: { _ in "arrow.turn.down.right" }, hint: "files", places: [.row, .bar]
    ) { $0.today.filing = $0.items }

    static let send = TodayVerb(
        id: "send", name: "Send", title: { _ in "Send" }, keys: [CommandKey("s", []), CommandKey("\r", [.shift, .command])],
        symbol: { _ in "paperplane" }, hint: "sends it", places: [.row, .bar], listsSkills: true
    ) { $0.today.send($0.items, action: nil) }

    static let edit = TodayVerb(id: "edit here", name: "Edit", title: { _ in "Edit" },
                                isAvailable: { $0.first?.note != nil }) {
        if let note = $0.first?.note { $0.edit(note) }
    }

    static let editInWindow = TodayVerb(id: "edit", name: "Edit", title: { _ in "Edit in New Window" },
                                        keys: [CommandKey("\r")],
                                        isAvailable: { $0.first?.note != nil }) {
        if let note = $0.first?.note { $0.editInWindow(note) }
    }

    static let merge = TodayVerb(id: "merge", name: "Merge", title: { _ in "Merge Notes" }, keys: [CommandKey("m", [])],
                                 places: [.bar],
                                 isAvailable: { $0.items.compactMap(\.note).count > 1 }) { $0.today.merge($0.items) }

    static let copy = TodayVerb(id: "copy", name: "Copy", title: { _ in "Copy" }, keys: [CommandKey("c")],
                                places: [.bar]) { $0.today.copy($0.items) }

    static let copyAsList = TodayVerb(id: "copy as a list", name: "Copy as a List", title: { _ in "Copy as a List" },
                                      keys: [CommandKey("c", [.shift, .command])]) { $0.today.copy($0.items, asList: true) }

    static let delete = TodayVerb(id: "delete", name: "Delete", title: { _ in "Delete" }, keys: [.delete],
                                  animates: true, isDestructive: true,
                                  isAvailable: { $0.items.contains { TodayModel.canDelete($0.id) } }) { $0.today.delete($0.items) }

    /// Every verb, in the order of the hint strip, the buttons, and the bar.
    static let all: [TodayVerb] = [open, keep, done, file, send, merge, delete, copy, copyAsList, editInWindow, edit]

    /// The groups of the menu of a row. A divider goes between two groups.
    static let menu: [[TodayVerb]] = [[open], [keep, done, file, send], [edit, editInWindow, merge, copy], [delete]]

    /// The round buttons of a row.
    static var row: [TodayVerb] { all.filter { $0.places.contains(.row) } }

    /// The buttons of the selection bar.
    static var bar: [TodayVerb] { all.filter { $0.places.contains(.bar) } }

    /// The accessibility hint of a row, from the verbs of its buttons.
    static var rowHint: String {
        let phrases = row.compactMap { verb in verb.hint.map { (verb.keys.first?.glyph ?? "") + " " + $0 } }
        let list = phrases.count > 1 ? phrases.dropLast().joined(separator: ", ") + ", and " + (phrases.last ?? "") : phrases.joined()
        return "Click to select. Return opens it. " + list + "."
    }

    /// The keys of the verbs. Each key runs its verb on the context that
    /// `context` gives, while the verb is available.
    ///
    /// - Returns: The keys without Command first, then the keys with Command.
    ///   The keys of Today put other keys between the two lists.
    static func keys(context: @escaping () -> Context, run: @escaping (TodayVerb, Context) -> Void) -> (plain: [PaperKey], command: [PaperKey]) {
        let keys = all.flatMap { verb in
            verb.keys.map { key in
                PaperKey(key: key, title: verb.id, isOn: { verb.isAvailable(context()) }) { run(verb, context()) }
            }
        }
        return (keys.filter { !$0.key.modifiers.contains(.command) }, keys.filter { $0.key.modifiers.contains(.command) })
    }
}

extension TodayVerb: Equatable {
    nonisolated static func == (lhs: TodayVerb, rhs: TodayVerb) -> Bool { lhs.id == rhs.id }
}
