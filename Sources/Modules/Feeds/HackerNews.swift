import Foundation

/// The front page of Hacker News and the comments of a story.
///
/// The stories come from the Hacker News API at hacker-news.firebaseio.com,
/// in the order of the front page. The comments of a story come in one
/// request from hn.algolia.com. Piper keeps no copy of either.
public enum HackerNews {

    // MARK: - Properties

    /// The feed ID of a Hacker News article, so that a kept story takes "Hacker News" as its source.
    public static let feedID = "https://news.ycombinator.com/"
    public static let title = "Hacker News"
    /// The number of stories that the tab shows, as on the front page.
    public static let storyLimit = 30

    static let api = "https://hacker-news.firebaseio.com/v0/"
    static let commentsAPI = "https://hn.algolia.com/api/v1/items/"

    /// One story of the front page.
    public struct Story: Hashable, Identifiable, Sendable {
        public let id: Int
        public let title: String
        /// The link of the story. An Ask HN post has none.
        public let url: String?
        public let author: String
        public let points: Int
        public let comments: Int
        public let time: Date
        /// The IDs of the top comments, in the order of the story page.
        public let kids: [Int]

        public init(id: Int, title: String, url: String?, author: String, points: Int, comments: Int, time: Date,
                    kids: [Int] = []) {
            self.id = id
            self.title = title
            self.url = url
            self.author = author
            self.points = points
            self.comments = comments
            self.time = time
            self.kids = kids
        }

        /// The page of the story and its comments on Hacker News.
        public var itemURL: String { "https://news.ycombinator.com/item?id=\(id)" }

        /// The link of the story, or its page on Hacker News.
        public var link: String { url ?? itemURL }

        /// The story as a feed article, for the reader paper and Keep.
        public var article: Article {
            Article(id: "hn:\(id)", feedID: HackerNews.feedID, url: link, title: title, summary: "",
                    published: time, arrived: time)
        }
    }

    /// One comment, with its replies.
    public struct Comment: Hashable, Identifiable, Sendable {
        public let id: Int
        public let author: String
        public let text: AttributedString
        public let time: Date
        public let replies: [Comment]

        public init(id: Int, author: String, text: AttributedString, time: Date, replies: [Comment] = []) {
            self.id = id
            self.author = author
            self.text = text
            self.time = time
            self.replies = replies
        }
    }

    /// The comments of a story, and the text of an Ask HN post.
    public struct Thread: Hashable, Sendable {
        public let text: AttributedString?
        public let comments: [Comment]
    }

    /// One comment in the flat list of a thread.
    public struct Row: Hashable, Identifiable, Sendable {
        public let comment: Comment
        /// The IDs of the comments above this comment, the top comment first.
        /// A tree draws one thread line for each of them.
        public let ancestors: [Int]
        /// 0 for a top comment, 1 for a reply to it, and more for each level under that.
        public var depth: Int { ancestors.count }
        /// The count of replies under the comment, at every level.
        public let replyCount: Int

        public var id: Int { comment.id }
    }

    /// The comments as a flat list, each reply after its parent. The replies
    /// of a collapsed comment do not show.
    public static func rows(of comments: [Comment], collapsed: Set<Int>, ancestors: [Int] = []) -> [Row] {
        comments.flatMap { comment -> [Row] in
            let row = Row(comment: comment, ancestors: ancestors, replyCount: count(comment.replies))
            guard !collapsed.contains(comment.id) else { return [row] }
            return [row] + rows(of: comment.replies, collapsed: collapsed, ancestors: ancestors + [comment.id])
        }
    }

    static func count(_ comments: [Comment]) -> Int {
        comments.reduce(0) { $0 + 1 + count($1.replies) }
    }

    // MARK: - Fetching

    /// The stories of the front page, in their order. A story that does not load is skipped.
    public static func topStories(session: URLSession = .shared) async throws -> [Story] {
        let ids = try JSONDecoder().decode([Int].self, from: await get(api + "topstories.json", session: session))
            .prefix(storyLimit)
        let stories = await withTaskGroup(of: (Int, Story?).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask { (index, try? await story(id, session: session)) }
            }
            var stories = [Story?](repeating: nil, count: ids.count)
            for await (index, story) in group { stories[index] = story }
            return stories
        }
        return stories.compactMap { $0 }
    }

    /// The comments of a story. The top comments keep the order of the story
    /// page. The replies keep the order of the Algolia answer.
    public static func thread(of story: Story, session: URLSession = .shared) async throws -> Thread {
        let item = try JSONDecoder().decode(AlgoliaItem.self, from: await get(commentsAPI + "\(story.id)", session: session))
        let rank = Dictionary(story.kids.enumerated().map { ($1, $0) }) { first, _ in first }
        let comments = (item.children ?? []).compactMap(comment)
            .sorted { (rank[$0.id] ?? .max, $0.id) < (rank[$1.id] ?? .max, $1.id) }
        return Thread(text: item.text.map(text(of:)), comments: comments)
    }

    static func story(_ id: Int, session: URLSession) async throws -> Story? {
        let item = try JSONDecoder().decode(FirebaseItem.self, from: await get(api + "item/\(id).json", session: session))
        guard item.type == "story", item.dead != true, item.deleted != true, let title = item.title else { return nil }
        return Story(id: item.id, title: title.decodingHTMLEntities(), url: item.url?.nilIfEmptyOrWhitespace,
                     author: item.by ?? "", points: item.score ?? 0, comments: item.descendants ?? 0,
                     time: Date(timeIntervalSince1970: TimeInterval(item.time ?? 0)), kids: item.kids ?? [])
    }

    /// A comment and its replies. A deleted comment with no replies is skipped.
    static func comment(_ item: AlgoliaItem) -> Comment? {
        let replies = (item.children ?? []).compactMap(comment)
        guard item.text != nil || !replies.isEmpty else { return nil }
        return Comment(id: item.id, author: item.author ?? "[deleted]", text: text(of: item.text ?? "[deleted]"),
                       time: Date(timeIntervalSince1970: TimeInterval(item.createdAt ?? 0)), replies: replies)
    }

    private static func get(_ address: String, session: URLSession) async throws -> Data {
        guard let url = URL(string: address) else { throw FeedError("The address is not valid.") }
        let (data, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: FeedFetch.timeout))
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw FeedError("Hacker News answered \(status).")
        }
        return data
    }

    // MARK: - Text

    /// The text of a comment from its HTML: paragraphs, italics, links, and code.
    static func text(of html: String) -> AttributedString {
        guard let tag = try? NSRegularExpression(pattern: "<(/?)([a-zA-Z]+)([^>]*)>") else { return AttributedString(html) }
        var result = AttributedString()
        var italic = false
        var code = false
        var link: URL?
        var cursor = html.startIndex

        func append(_ raw: Substring) {
            let plain = String(raw).decodingHTMLEntities()
            guard !plain.isEmpty else { return }
            var run = AttributedString(plain)
            var intent: InlinePresentationIntent = []
            if italic { intent.insert(.emphasized) }
            if code { intent.insert(.code) }
            if !intent.isEmpty { run.inlinePresentationIntent = intent }
            if let link { run.link = link }
            result += run
        }

        func breakParagraph() {
            guard !result.characters.isEmpty else { return }
            result += AttributedString("\n\n")
        }

        let range = NSRange(html.startIndex..., in: html)
        for match in tag.matches(in: html, range: range) {
            guard let whole = Range(match.range, in: html), let nameRange = Range(match.range(at: 2), in: html),
                  let attributes = Range(match.range(at: 3), in: html) else { continue }
            append(html[cursor..<whole.lowerBound])
            cursor = whole.upperBound
            let closing = match.range(at: 1).length > 0
            switch html[nameRange].lowercased() {
            case "p", "pre": if !closing { breakParagraph() }
            case "i", "em": italic = !closing
            case "code": code = !closing
            case "a": link = closing ? nil : href(in: String(html[attributes]))
            default: break
            }
        }
        append(html[cursor...])
        return result
    }

    private static func href(in attributes: String) -> URL? {
        guard let start = attributes.range(of: "href=\"")?.upperBound,
              let end = attributes[start...].firstIndex(of: "\"") else { return nil }
        return URL(string: String(attributes[start..<end]).decodingHTMLEntities())
    }

    // MARK: - Decoding

    struct FirebaseItem: Decodable {
        let id: Int
        let type: String?
        let by: String?
        let title: String?
        let url: String?
        let score: Int?
        let descendants: Int?
        let time: Int?
        let kids: [Int]?
        let dead: Bool?
        let deleted: Bool?
    }

    struct AlgoliaItem: Decodable {
        let id: Int
        let author: String?
        let text: String?
        let createdAt: Int?
        let children: [AlgoliaItem]?

        enum CodingKeys: String, CodingKey {
            case id, author, text, children
            case createdAt = "created_at_i"
        }
    }
}
