import Foundation

/// One site in the digest. It has no full URL.
public struct DigestSite: Equatable, Identifiable, Sendable {
    public let host: String
    public let visits: Int
    public let pages: Int
    public let lastVisit: Date
    /// The decay score of the site. See `HistoryDigest.score`.
    public let score: Double

    public var id: String { host }

    public init(host: String, visits: Int, pages: Int, lastVisit: Date, score: Double) {
        self.host = host
        self.visits = visits
        self.pages = pages
        self.lastVisit = lastVisit
        self.score = score
    }
}

/// The sites of recent history, ranked by visits and age.
public struct HistoryDigest: Equatable, Sendable {
    /// The count of all sites. The digest keeps the best `siteLimit` of them.
    public let totalSites: Int
    public let sites: [DigestSite]

    public static let siteLimit = 30
    public static let days = 14

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

    private static func site(_ host: String, _ visits: [Visit], score: Double) -> DigestSite {
        DigestSite(host: host, visits: visits.count, pages: Set(visits.map(\.url)).count,
                   lastVisit: visits.map(\.date).max() ?? .distantPast, score: score)
    }

    /// The decay score: the visits are the points, and the age is the hours since the last visit.
    static func score(_ visits: [Visit], now: Date) -> Double {
        let last = visits.map(\.date).max() ?? now
        return Decay.score(points: Double(visits.count), hours: Decay.hours(from: last, to: now))
    }
}
