import Captures
import Feeds
import Foundation

/// Today: one stream of notes, links, and feed articles, in groups.
///
/// The stream reads the captures, the clipboard texts, and the feed articles
/// when it is built. It writes nothing. A feed article that a capture holds
/// shows only as the row of that capture.
public struct UnifiedStream: Equatable {

    /// The segments over the list.
    public enum Lens: String, CaseIterable, Codable, Sendable {
        case all
        case notes
        case reading
        case kept

        public var title: String {
            switch self {
            case .all: return "All"
            case .notes: return "Notes"
            case .reading: return "Reading"
            case .kept: return "Kept"
            }
        }
    }

    /// What a group holds, which decides how its rows look.
    public enum GroupKind: Equatable, Sendable {
        /// Articles that the reader started.
        case started
        /// Items of one day, or of a range of days.
        case day
        /// Links that the reader did not open.
        case upNext
        /// Articles that the reader read to the end in the last week.
        case finished
        /// Done captures of one month.
        case month
    }

    public struct Group: Equatable {
        public let title: String
        public let kind: GroupKind
        public let items: [StreamItem]
    }

    /// Everything that the stream reads.
    public struct Input {
        public var notes: [Note]
        public var clips: [ClipboardEntry]
        public var articles: [Article]
        public var feeds: [Feed]
        public var relevance: Relevance

        public init(notes: [Note], clips: [ClipboardEntry] = [], articles: [Article] = [], feeds: [Feed] = [],
                    relevance: Relevance = Relevance()) {
            self.notes = notes
            self.clips = clips
            self.articles = articles
            self.feeds = feeds
            self.relevance = relevance
        }
    }

    // MARK: - Properties

    /// The number of articles that Continue Reading shows in All.
    public static let continueCount = 3
    /// Today shows the feed articles of this many days.
    public static let articleDays = 7

    public let groups: [Group]
    /// The count of rows of each lens.
    public let counts: [Lens: Int]
    /// The clipboard texts of the tray at the foot of the list.
    public let tray: [StreamItem]
    /// The rows in the order of the list.
    public var items: [StreamItem] { groups.flatMap(\.items) }

    // MARK: - Initialization

    /// The stream of one capture section, or of everything when the section
    /// is nil. A section holds no feed articles.
    public init(_ input: Input, lens: Lens, section: String? = nil, query: String = "",
                now: Date = Date(), calendar: Calendar = .current) {
        let children = Dictionary(grouping: input.notes.filter { $0.parent != nil }, by: { $0.parent! })
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let captures = input.notes.filter { note in
            guard note.parent == nil, !note.isDone, section.map({ note.section == $0 }) ?? true else { return false }
            return Self.matches(note, children: children[note.id] ?? [], query: query)
        }
        let items = captures.map { StreamItem.capture($0, children: children[$0.id] ?? []) }
        let feedRows = section == nil ? Self.feedRows(input, query: query, now: now, calendar: calendar) : []
        let reading = ReadingList(notes: captures + captures.flatMap { children[$0.id] ?? [] }, now: now)
        func rows(_ notes: [Note]) -> [StreamItem] {
            notes.map { StreamItem.capture($0, children: children[$0.id] ?? []) }
        }

        counts = [
            .all: items.count + feedRows.count,
            .notes: items.filter { $0.kind == .note }.count,
            .reading: reading.count,
            .kept: items.filter { $0.state == .kept }.count
        ]
        tray = input.clips.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }.map(StreamItem.clip)

        switch lens {
        case .all:
            let started = query.isEmpty ? Array(reading.inProgress.prefix(Self.continueCount)) : []
            let shown = Set(started.map(\.id))
            let rest = items.filter { $0.note.map { !shown.contains($0.id) } ?? true } + feedRows
            groups = (started.isEmpty ? [] : [Group(title: "Continue Reading", kind: .started, items: rows(started))])
                + Self.days(rest, now: now, calendar: calendar)
        case .notes:
            groups = Self.days(items.filter { $0.kind == .note }, now: now, calendar: calendar)
        case .reading:
            groups = [
                Group(title: "Continue", kind: .started, items: rows(reading.inProgress)),
                Group(title: "Up Next", kind: .upNext, items: rows(reading.upNext)),
                Group(title: "Finished This Week", kind: .finished, items: rows(reading.finished))
            ].filter { !$0.items.isEmpty }
        case .kept:
            groups = Self.days(items.filter { $0.state == .kept }, now: now, calendar: calendar)
        }
    }

    // MARK: - Done

    /// The done captures, one group for each month in which they were marked
    /// as done, the newest month first. A search matches the text of a
    /// capture and of its child notes.
    public static func done(notes: [Note], query: String = "", calendar: Calendar = .current) -> [Group] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let children = Dictionary(grouping: notes.filter { $0.parent != nil }, by: { $0.parent! })
        let done = notes.filter { $0.parent == nil && $0.isDone && matches($0, children: children[$0.id] ?? [], query: query) }
        let months = Dictionary(grouping: done) { note in
            calendar.dateInterval(of: .month, for: note.modifiedAt)?.start ?? note.modifiedAt
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return months.keys.sorted(by: >).map { month in
            Group(title: formatter.string(from: month), kind: .month,
                  items: (months[month] ?? []).sorted { $0.modifiedAt > $1.modifiedAt }
                    .map { StreamItem.capture($0, children: children[$0.id] ?? []) })
        }
    }

    /// The captures of one section, or of every section when the section is
    /// nil, that the reader marked as done today. The newest is first.
    ///
    /// An article that Piper moved to Done a week after the reader finished
    /// it is not in the list, because the reader did not mark it today.
    public static func doneToday(notes: [Note], section: String?, now: Date = Date(),
                                 calendar: Calendar = .current) -> [Note] {
        notes.filter { note in
            guard note.parent == nil, note.isDone, section.map({ note.section == $0 }) ?? true else { return false }
            let finished = note.reading?.finishedAt ?? note.modifiedAt
            return calendar.isDate(note.modifiedAt, inSameDayAs: now) && calendar.isDate(finished, inSameDayAs: now)
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: - Private

    private static func matches(_ note: Note, children: [Note], query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return ([note.text, note.reading?.title ?? ""] + children.map(\.text))
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }

    /// The rows of the feed articles. An article that a capture holds and an
    /// article older than `articleDays` have no row.
    /// A search gives each article that matches its own row.
    private static func feedRows(_ input: Input, query: String, now: Date, calendar: Calendar) -> [StreamItem] {
        let held = Set(input.notes.compactMap { note -> String? in
            guard note.parent == nil, note.isArticle else { return nil }
            return note.articleURL.map(CaptureLinks.canonical)
        })
        let since = now.addingTimeInterval(-Double(articleDays) * 86_400)
        let articles = input.articles.filter { article in
            guard article.date >= since else { return false }
            guard let url = URL(string: article.url), !held.contains(CaptureLinks.canonical(url)) else { return false }
            return true
        }
        guard query.isEmpty else {
            let feeds = Dictionary(input.feeds.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return articles.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query) }
                .map { StreamItem.article($0, feed: feeds[$0.feedID], score: input.relevance.score($0)) }
        }
        return FeedRows.rows(articles: articles, feeds: input.feeds, relevance: input.relevance, calendar: calendar)
    }

    /// Today, Yesterday, This Week, and Earlier. The newest item is first in each group.
    static func days(_ items: [StreamItem], now: Date, calendar: Calendar) -> [Group] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let week = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let titles = ["Today", "Yesterday", "This Week", "Earlier"]
        let grouped = Dictionary(grouping: items) { item -> String in
            if item.date >= today { return titles[0] }
            if item.date >= yesterday { return titles[1] }
            if item.date >= week { return titles[2] }
            return titles[3]
        }
        return titles.compactMap { title in
            grouped[title].map { Group(title: title, kind: .day, items: $0.sorted { $0.date > $1.date }) }
        }
    }
}
