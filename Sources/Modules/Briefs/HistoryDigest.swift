import Foundation

/// One site in the digest. It has no full URL.
public struct DigestSite: Codable, Equatable, Identifiable, Sendable {
    public let host: String
    public let visits: Int
    public let pages: Int
    public let lastVisit: Date
    public let sampleTitles: [String]

    public var id: String { host }
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

    /// Ranks each site that the user opened at least two times and that the list does not block.
    public init(visits: [Visit], blocked: [String], now: Date = Date()) {
        var groups: [String: [Visit]] = [:]
        for visit in visits where BlockedSites.allows(visit.url, list: blocked) {
            guard let host = BlockedSites.host(of: visit.url) else { continue }
            groups[host, default: []].append(visit)
        }
        let repeated = groups.filter { $0.value.count >= 2 }
        let scores = repeated.mapValues { Self.score($0, now: now) }
        let hosts = repeated.keys.sorted { first, second in
            let (a, b) = (scores[first] ?? 0, scores[second] ?? 0)
            return a == b ? first < second : a > b
        }
        let sites = hosts.prefix(Self.siteLimit).map { Self.site($0, repeated[$0] ?? []) }
        self.init(totalSites: hosts.count, sites: Array(sites))
    }

    /// The JSON text of the digest, for a prompt.
    public var json: String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    private static func site(_ host: String, _ visits: [Visit]) -> DigestSite {
        let newest = visits.sorted { $0.date > $1.date }
        var titles: [String] = []
        for title in newest.compactMap(\.title) where !title.isEmpty && !titles.contains(title) && titles.count < titleLimit {
            titles.append(String(title.prefix(titleLength)))
        }
        return DigestSite(host: host, visits: visits.count, pages: Set(visits.map(\.url)).count,
                          lastVisit: newest[0].date, sampleTitles: titles)
    }

    /// Frequency 40%, recency 30%, page variety 20%, and visits for each day 10%. Each part is from 0 to 1.
    private static func score(_ visits: [Visit], now: Date) -> Double {
        let days = Double(Self.days)
        let last = visits.map(\.date).max() ?? now
        let age = now.timeIntervalSince(last) / 86_400
        let count = Double(visits.count)
        return min(count / 50, 1) * 0.4
            + max(0, 1 - age / days) * 0.3
            + min(Double(Set(visits.map(\.url)).count) / 10, 1) * 0.2
            + min(count / days / 5, 1) * 0.1
    }
}
