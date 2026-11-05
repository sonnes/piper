import Foundation

/// One popular submission on Hacker News.
public struct HackerNewsStory: Equatable, Sendable {
    public let title: String
    public let url: String
    public let discussionURL: String
    public let points: Int
    public let comments: Int
    public let postedAt: Date

    public init(title: String, url: String, discussionURL: String, points: Int, comments: Int, postedAt: Date) {
        self.title = title
        self.url = url
        self.discussionURL = discussionURL
        self.points = points
        self.comments = comments
        self.postedAt = postedAt
    }
}

/// Reads the popular submissions of the last day from the public Hacker News search API.
public enum HackerNews {

    public static let sourceID = "hacker-news"
    public static let name = "Hacker News"
    public static let days = 1
    public static let minimumPoints = 50
    public static let storyLimit = 30
    private static let requestLimit = 100
    private static let timeout: TimeInterval = 20

    private struct Response: Decodable {
        let hits: [Hit]
    }

    private struct Hit: Decodable {
        let objectID: String
        let title: String?
        let url: String?
        let points: Int?
        let num_comments: Int?
        let created_at_i: Int?
    }

    public static func fetch(now: Date, blocked: [String], seen: Set<String>) async throws -> [HackerNewsStory] {
        var request = URLRequest(url: requestURL(now: now))
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try stories(in: data, blocked: blocked, seen: seen)
    }

    static func requestURL(now: Date) -> URL {
        let since = Int(now.timeIntervalSince1970) - days * 86_400
        var components = URLComponents(string: "https://hn.algolia.com/api/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "tags", value: "story"),
            URLQueryItem(name: "numericFilters", value: "created_at_i>\(since),points>=\(minimumPoints)"),
            URLQueryItem(name: "hitsPerPage", value: String(requestLimit))
        ]
        return components.url!
    }

    /// The stories with the most points first, without the links of earlier briefs. A submission without a link, such as Ask HN, uses its discussion.
    static func stories(in data: Data, blocked: [String], seen: Set<String> = []) throws -> [HackerNewsStory] {
        let hits = try JSONDecoder().decode(Response.self, from: data).hits
        let stories = hits.compactMap { hit -> HackerNewsStory? in
            guard let title = hit.title else { return nil }
            let discussion = "https://news.ycombinator.com/item?id=\(hit.objectID)"
            let url = hit.url.flatMap { $0.isEmpty ? nil : $0 } ?? discussion
            guard BlockedSites.allows(discussion, list: blocked), BlockedSites.allows(url, list: blocked),
                  !BriefLinks.isSeen(url, in: seen), !BriefLinks.isSeen(discussion, in: seen) else { return nil }
            return HackerNewsStory(title: title, url: url, discussionURL: discussion,
                                   points: hit.points ?? 0, comments: hit.num_comments ?? 0,
                                   postedAt: Date(timeIntervalSince1970: TimeInterval(hit.created_at_i ?? 0)))
        }
        return Array(stories.sorted { $0.points > $1.points }.prefix(storyLimit))
    }
}
