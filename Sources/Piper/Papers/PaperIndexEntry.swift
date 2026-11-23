import Foundation
import Stream

/// One row of an index that the keyboard can pick, in the order of the index.
enum IndexEntry: Equatable {
    /// A row that shows a scope in the list.
    case scope(PaperScope)
    /// A lens row of the Today index: everything, with one lens.
    case lens(UnifiedStream.Lens)

    /// The rows of the index of a tab, from the top.
    ///
    /// - Parameters:
    ///   - sections: The capture sections, for the Today index.
    ///   - sessionFolders: The folders that have agent sessions.
    static func entries(tab: PaperTab, sections: [String], sessionFolders: [String]) -> [IndexEntry] {
        switch tab {
        case .today:
            return UnifiedStream.Lens.allCases.map(IndexEntry.lens)
                + sections.map { .scope(.today(section: $0)) }
                + [.scope(.done), .scope(.sources)]
        case .agents:
            return sessionFolders.map { .scope(.sessions($0)) }
        case .folder:
            return []
        }
    }

    /// The row of the list that the paper shows, for the cursor when the index opens.
    static func current(scope: PaperScope, lens: UnifiedStream.Lens) -> IndexEntry {
        scope == .today(section: nil) ? .lens(lens) : .scope(scope)
    }

    /// The row after or before `cursor`. The cursor stops at the first and the last row.
    static func move(_ cursor: IndexEntry?, by delta: Int, in entries: [IndexEntry]) -> IndexEntry? {
        guard !entries.isEmpty else { return nil }
        guard let cursor, let index = entries.firstIndex(of: cursor) else {
            return delta > 0 ? entries.first : entries.last
        }
        return entries[max(0, min(entries.count - 1, index + delta))]
    }

    /// The row before or after the row of the list, for `[` and `]`. The rows go round.
    static func cycle(_ current: IndexEntry, by delta: Int, in entries: [IndexEntry]) -> IndexEntry? {
        guard !entries.isEmpty else { return nil }
        guard let index = entries.firstIndex(of: current) else { return entries.first }
        return entries[(index + delta + entries.count) % entries.count]
    }
}

/// What Command and a number key do on the feed paper.
enum NumberKey: Equatable {
    /// Show the index of the active tab, or hide it.
    case toggleIndex
    /// Show the tab in its default scope, as a list.
    case showTab(PaperTab)
    /// No tab has this number.
    case none

    /// The action of Command and `number`, from 1.
    ///
    /// The key of the active tab shows its index when the list shows the
    /// default scope of the tab, and hides the index while it shows. The key
    /// of the active tab in another scope, or of another tab, shows the
    /// default scope of that tab.
    static func action(_ number: Int, tabs: [PaperTab], active: PaperTab, showsIndex: Bool,
                       atDefaultScope: Bool) -> NumberKey {
        guard number >= 1, number <= tabs.count else { return .none }
        let tab = tabs[number - 1]
        if tab == active, tab.hasIndex, showsIndex || atDefaultScope { return .toggleIndex }
        return .showTab(tab)
    }
}
