import Foundation

/// One site in the digest. It has no full URL.
public struct DigestSite: Codable, Equatable, Identifiable, Sendable {
    public let host: String
    public let visits: Int
    public let pages: Int
    public let lastVisit: Date
    public let sampleTitles: [String]
    /// The decay score of the site. See `HistoryDigest.score`.
    public let score: Double

    public var id: String { host }

    public init(host: String, visits: Int, pages: Int, lastVisit: Date, sampleTitles: [String], score: Double) {
        self.host = host
        self.visits = visits
        self.pages = pages
        self.lastVisit = lastVisit
        self.sampleTitles = sampleTitles
        self.score = score
    }
}

/// The ranked summary of history that the agent receives.
public struct HistoryDigest: Codable, Equatable, Sendable {
    /// The count of all sites, so the agent knows that the list is partial.
    public let totalSites: Int
    public let sites: [DigestSite]

    public static let siteLimit = 30
    public static let titleLimit = 5
    public static let days = 14
    private static let titleLength = 120

    public init(totalSites: Int, sites: [DigestSite]) {
        self.totalSites = totalSites
        self.sites = sites
    }

    /// Ranks each site that the list does not block. One visit is enough.
    public init(visits: [Visit], blocked: [String], now: Date = Date()) {
        var groups: [String: [Visit]] = [:]
        for visit in visits where BlockedSites.allows(visit.url, list: blocked) {
            guard let host = BlockedSites.host(of: visit.url) else { continue }
            groups[host, default: []].append(visit)
        }
        let scores = groups.mapValues { Self.score($0, now: now) }
        let hosts = groups.keys.sorted { first, second in
            let (a, b) = (scores[first] ?? 0, scores[second] ?? 0)
            return a == b ? first < second : a > b
        }
        let sites = hosts.prefix(Self.siteLimit).map { Self.site($0, groups[$0] ?? [], score: scores[$0] ?? 0) }
        self.init(totalSites: hosts.count, sites: Array(sites))
    }

    /// The score of the site of a host, or 0 if the digest does not hold it.
    public func score(of host: String) -> Double {
        sites.first { $0.host == host }?.score ?? 0
    }

    /// The JSON text of the digest, for a prompt.
    public var json: String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    private static func site(_ host: String, _ visits: [Visit], score: Double) -> DigestSite {
        let newest = visits.sorted { $0.date > $1.date }
        var titles: [String] = []
        for title in newest.compactMap(\.title) where !title.isEmpty && !titles.contains(title) && titles.count < titleLimit {
            titles.append(String(title.prefix(titleLength)))
        }
        return DigestSite(host: host, visits: visits.count, pages: Set(visits.map(\.url)).count,
                          lastVisit: newest[0].date, sampleTitles: titles, score: score)
    }

    /// The decay score: the visits are the points, and the age is the hours since the last visit.
    static func score(_ visits: [Visit], now: Date) -> Double {
        let last = visits.map(\.date).max() ?? now
        return Decay.score(points: Double(visits.count), hours: Decay.hours(from: last, to: now))
    }
}
