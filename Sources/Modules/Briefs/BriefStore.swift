import Foundation

/// One link that a brief picked for the reader.
public struct BriefPick: Codable, Equatable, Identifiable, Sendable {

    public enum State: String, Codable, Sendable {
        /// Inbox shows the pick.
        case open
        /// The reader saved the link to Inbox.
        case kept
        case skipped
        case read
    }

    public let url: String
    public let title: String
    public let host: String
    /// One sentence from the agent on why the reader can want the link.
    public let why: String
    public let score: Double
    public var state: State

    public var id: String { url }

    public init(url: String, title: String, host: String, why: String, score: Double, state: State = .open) {
        self.url = url
        self.title = title
        self.host = host
        self.why = why
        self.score = score
        self.state = state
    }
}

/// The brief of one day. The id is its date, as in `2026-10-30`.
public struct BriefDay: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let builtAt: Date
    public var picks: [BriefPick]
    /// The hosts of the pages that the build loaded.
    public let sites: [String]
    /// The feeds of the articles, and Hacker News if it gave stories.
    public let feeds: [String]
    /// The sources that the build could not read.
    public let failed: [String]

    public init(id: String, builtAt: Date, picks: [BriefPick], sites: [String], feeds: [String], failed: [String]) {
        self.id = id
        self.builtAt = builtAt
        self.picks = picks
        self.sites = sites
        self.feeds = feeds
        self.failed = failed
    }

    /// The picks that Inbox shows.
    public var openPicks: [BriefPick] { picks.filter { $0.state == .open } }
}

/// Keeps each brief as a JSON file in a private folder, with the date as its name.
public struct BriefStore: Sendable {

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// The newest brief, or nil before the first build.
    public func latest() -> BriefDay? {
        ids().first.flatMap(day)
    }

    public func day(_ id: String) -> BriefDay? {
        guard let data = try? Data(contentsOf: url(of: id)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BriefDay.self, from: data)
    }

    /// The links of each brief before this date. A rebuild of a day can use the links of that day again.
    public func linksBefore(_ date: Date, calendar: Calendar = .current) -> Set<String> {
        let today = Self.id(for: date, calendar: calendar)
        var links = Set<String>()
        for id in ids() where id < today {
            links.formUnion(day(id)?.picks.map { BriefLinks.normalized($0.url) } ?? [])
        }
        return links
    }

    public func save(_ day: BriefDay) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(day).write(to: url(of: day.id), options: .atomic)
    }

    /// Changes the state of one pick and saves the brief. Gives the changed brief.
    @discardableResult
    public func set(_ state: BriefPick.State, of url: String, in id: String) throws -> BriefDay? {
        guard var day = day(id), let index = day.picks.firstIndex(where: { $0.url == url }) else { return nil }
        day.picks[index].state = state
        try save(day)
        return day
    }

    public static func id(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The ids of the saved briefs, the newest first.
    private func ids() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted(by: >)
    }

    private func url(of id: String) -> URL {
        folder.appendingPathComponent(id + ".json")
    }
}
