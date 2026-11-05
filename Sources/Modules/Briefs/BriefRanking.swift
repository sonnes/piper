import Foundation

/// One link that a brief can pick: a Hacker News story, a feed article, or a
/// link on a loaded page.
public struct BriefCandidate: Equatable, Sendable {

    public enum Kind: String, Codable, Sendable {
        case story
        case starredArticle
        case article
        case pageLink
    }

    public let url: String
    public let title: String
    public let host: String
    public let kind: Kind
    public let score: Double

    public init(url: String, title: String, host: String, kind: Kind, score: Double) {
        self.url = url
        self.title = title
        self.host = host
        self.kind = kind
        self.score = score
    }
}

/// Ranks the candidate links of a brief with `Decay`.
///
/// Each source gives the points of a link. The site score of the host of the
/// link raises the points, so a link from a site that the reader visits often
/// goes up the list.
public enum BriefRanking {

    public static let starredArticlePoints = 100.0
    public static let articlePoints = 40.0
    public static let pageLinkPoints = 30.0
    /// The age of a link that has no date, and the most age of a page link.
    public static let undatedHours = 24.0
    public static let candidateLimit = 25

    /// The best candidates first, at most `candidateLimit`. Two forms of one
    /// link count once, with the better score.
    ///
    /// The caller removes the links of earlier briefs first. A page link has no
    /// date. Its age is the hours since the previous build, at most `undatedHours`.
    public static func rank(stories: [HackerNewsStory], articles: [FeedArticle], pages: [LoadedPage],
                            digest: HistoryDigest, blocked: [String], previousBuild: Date?, now: Date) -> [BriefCandidate] {
        let best = digest.sites.map(\.score).max() ?? 0
        let pageHours = previousBuild.map { min(Decay.hours(from: $0, to: now), undatedHours) } ?? undatedHours

        func candidate(_ url: String, _ title: String, _ kind: BriefCandidate.Kind, points: Double, hours: Double) -> BriefCandidate? {
            guard BlockedSites.allows(url, list: blocked), let host = BlockedSites.host(of: url) else { return nil }
            let boost = best > 0 ? digest.score(of: host) / best : 0
            let score = Decay.score(points: points * (1 + boost) - 1, hours: hours)
            return BriefCandidate(url: url, title: title, host: host, kind: kind, score: score)
        }

        let all = stories.compactMap { story in
            candidate(story.url, story.title, .story, points: Double(story.points),
                      hours: Decay.hours(from: story.postedAt, to: now))
        } + articles.compactMap { article in
            candidate(article.url, article.title, article.starred ? .starredArticle : .article,
                      points: article.starred ? starredArticlePoints : articlePoints,
                      hours: article.publishedAt.map { Decay.hours(from: $0, to: now) } ?? undatedHours)
        } + pages.flatMap(\.links).compactMap { link in
            candidate(link.url, link.label, .pageLink, points: pageLinkPoints, hours: pageHours)
        }

        var kept: [String: BriefCandidate] = [:]
        for item in all {
            let key = BriefLinks.normalized(item.url)
            if let earlier = kept[key], earlier.score >= item.score { continue }
            kept[key] = item
        }
        let ranked = kept.values.sorted { $0.score == $1.score ? $0.url < $1.url : $0.score > $1.score }
        return Array(ranked.prefix(candidateLimit))
    }
}
