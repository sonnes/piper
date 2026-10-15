import Foundation

/// The Inbox list of the main window: one stream of notes and links, newest
/// first, in groups.
///
/// All starts with up to three articles that the reader started, then
/// groups the other captures by day. Notes groups only the captures that are
/// not links. Reading groups the links as Continue, Up Next, and Finished
/// This Week.
public struct InboxStream: Equatable {

    /// The chips over the list.
    public enum Filter: String, CaseIterable, Sendable {
        case all
        case notes
        case reading

        public var title: String {
            switch self {
            case .all: return "All"
            case .notes: return "Notes"
            case .reading: return "Reading"
            }
        }
    }

    /// What a group holds, which decides how its rows look.
    public enum Kind: Equatable, Sendable {
        /// Articles that the reader started.
        case started
        /// Captures of one day, or of a range of days.
        case day
        /// Links that the reader did not open.
        case upNext
        /// Articles that the reader read to the end in the last week.
        case finished
        /// Done captures of one month, in Archived.
        case month
    }

    public struct Group: Equatable {
        public let title: String
        public let kind: Kind
        public let notes: [Note]
    }

    // MARK: - Properties

    /// The number of articles that Continue Reading shows in All.
    public static let continueCount = 3

    public let groups: [Group]
    /// The number of captures that each chip shows.
    public let counts: [Filter: Int]
    /// The captures in the order of the list.
    public var notes: [Note] { groups.flatMap(\.notes) }

    // MARK: - Initialization

    /// The stream of one section, or of every section when the section is nil.
    public init(notes: [Note], section: String?, filter: Filter, query: String = "",
                now: Date = Date(), calendar: Calendar = .current) {
        let children = Dictionary(grouping: notes.filter { $0.parent != nil }, by: { $0.parent! })
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = notes.filter { note in
            guard note.parent == nil, !note.isDone, section.map({ note.section == $0 }) ?? true else { return false }
            guard !query.isEmpty else { return true }
            return ([note.text, note.reading?.title ?? ""] + (children[note.id] ?? []).map(\.text))
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
        let reading = ReadingList(notes: scope + scope.flatMap { children[$0.id] ?? [] }, now: now)
        counts = [.all: scope.count, .notes: scope.filter { !$0.isArticle }.count, .reading: reading.count]

        switch filter {
        case .reading:
            groups = [
                Group(title: "Continue", kind: .started, notes: reading.inProgress),
                Group(title: "Up Next", kind: .upNext, notes: reading.upNext),
                Group(title: "Finished This Week", kind: .finished, notes: reading.finished)
            ].filter { !$0.notes.isEmpty }
        case .notes:
            groups = Self.days(scope.filter { !$0.isArticle }, now: now, calendar: calendar)
        case .all:
            let started = query.isEmpty ? Array(reading.inProgress.prefix(Self.continueCount)) : []
            let shown = Set(started.map(\.id))
            let rest = scope.filter { !shown.contains($0.id) }
            groups = (started.isEmpty ? [] : [Group(title: "Continue Reading", kind: .started, notes: started)])
                + Self.days(rest, now: now, calendar: calendar)
        }
    }

    // MARK: - Archived

    /// The done captures, one group for each month in which they were marked
    /// as done, the newest month first. A search matches the text of a
    /// capture and of its child notes.
    public static func archive(notes: [Note], query: String = "", calendar: Calendar = .current) -> [Group] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let children = Dictionary(grouping: notes.filter { $0.parent != nil }, by: { $0.parent! })
        let done = notes.filter { note in
            guard note.parent == nil, note.isDone else { return false }
            guard !query.isEmpty else { return true }
            return ([note.text, note.reading?.title ?? ""] + (children[note.id] ?? []).map(\.text))
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
        let months = Dictionary(grouping: done) { note in
            calendar.dateInterval(of: .month, for: note.modifiedAt)?.start ?? note.modifiedAt
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return months.keys.sorted(by: >).map { month in
            Group(title: formatter.string(from: month), kind: .month,
                  notes: (months[month] ?? []).sorted { $0.modifiedAt > $1.modifiedAt })
        }
    }

    // MARK: - Days

    /// Today, Yesterday, This Week, and Earlier, by the creation time. The
    /// newest capture is first in each group.
    static func days(_ notes: [Note], now: Date, calendar: Calendar) -> [Group] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let week = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let titles = ["Today", "Yesterday", "This Week", "Earlier"]
        let grouped = Dictionary(grouping: notes) { note -> String in
            if note.createdAt >= today { return titles[0] }
            if note.createdAt >= yesterday { return titles[1] }
            if note.createdAt >= week { return titles[2] }
            return titles[3]
        }
        return titles.compactMap { title in
            grouped[title].map { Group(title: title, kind: .day, notes: $0.sorted { $0.createdAt > $1.createdAt }) }
        }
    }
}
