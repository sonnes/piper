import Captures
import Feeds
import Foundation

/// One row of an index that the keyboard can pick, in the order of the index.
enum IndexEntry: Equatable {
    /// A row that shows a scope in the list.
    case scope(PaperScope)
    /// A Show row of the Inbox index: every section, with only notes or only links.
    case inboxFilter(InboxStream.Filter)

    /// The rows of the index of a tab, from the top.
    ///
    /// - Parameters:
    ///   - sections: The capture sections, for the Inbox index.
    ///   - feeds: The ids of the feeds, for the Feeds index.
    ///   - sessionFolders: The folders that have agent sessions.
    static func entries(tab: PaperTab, sections: [String], feeds: [String], sessionFolders: [String]) -> [IndexEntry] {
        switch tab {
        case .inbox:
            return [.scope(.inbox(section: nil)), .inboxFilter(.notes), .inboxFilter(.reading)]
                + sections.map { .scope(.inbox(section: $0)) }
                + [.scope(.done)]
        case .feeds:
            return [.scope(.feed(.discover)), .scope(.feed(.allUnread))]
                + feeds.map { .scope(.feed(.feed($0))) }
        case .agents:
            return sessionFolders.map { .scope(.sessions($0)) }
        case .clipboard, .folder:
            return []
        }
    }

    /// The row of the list that the paper shows, for the cursor when the index opens.
    static func current(scope: PaperScope, filter: InboxStream.Filter) -> IndexEntry {
        if scope == .inbox(section: nil), filter != .all { return .inboxFilter(filter) }
        return .scope(scope)
    }

    /// The row after or before `cursor`. The cursor stops at the first and the last row.
    static func move(_ cursor: IndexEntry?, by delta: Int, in entries: [IndexEntry]) -> IndexEntry? {
        guard !entries.isEmpty else { return nil }
        guard let cursor, let index = entries.firstIndex(of: cursor) else {
            return delta > 0 ? entries.first : entries.last
        }
        return entries[max(0, min(entries.count - 1, index + delta))]
    }

    /// The scope before or after `scope` among the scope rows, for `[` and `]`.
    /// The scopes go round.
    static func cycle(_ scope: PaperScope, by delta: Int, in entries: [IndexEntry]) -> PaperScope? {
        let scopes = entries.compactMap { entry -> PaperScope? in
            if case .scope(let scope) = entry { return scope }
            return nil
        }
        guard !scopes.isEmpty else { return nil }
        guard let index = scopes.firstIndex(of: scope) else { return scopes.first }
        return scopes[(index + delta + scopes.count) % scopes.count]
    }
}

/// What a number key does on the feed paper.
enum NumberKey: Equatable {
    /// Show the index of the active tab, or hide it.
    case toggleIndex
    /// Show the tab in its default scope, as a list.
    case showTab(PaperTab)
    /// No tab has this number.
    case none

    /// The action of key `number`, from 1.
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
