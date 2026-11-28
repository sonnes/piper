import Foundation

/// The progress of the fetch that starts when Piper opens, or after Refresh
/// All. Today shows it as a strip of source icons.
///
/// A round holds only the feeds whose posts reach Today. A feed in the Off
/// mode is fetched, but it is not part of the round.
public struct FetchRound: Equatable, Identifiable, Sendable {
    public let id = UUID()
    /// The IDs of the feeds, in the order of the fetches.
    public let feeds: [String]
    /// The IDs of the feeds whose fetch ended, with or without an error.
    public private(set) var ended: Set<String> = []
    /// The IDs of the feeds whose fetch failed.
    public private(set) var failed: Set<String> = []
    /// The count of new posts that the fetches saved.
    public private(set) var newPosts = 0
    /// The time when the last fetch ended. Nil while a fetch runs.
    public private(set) var finished: Date?

    public init(feeds: [String]) {
        self.feeds = feeds
    }

    public var isFinished: Bool { finished != nil }

    /// Records the end of the fetch of a feed. A feed that is not part of the round is skipped.
    mutating func end(_ feed: String, newPosts: Int, failed: Bool) {
        guard feeds.contains(feed), !ended.contains(feed) else { return }
        ended.insert(feed)
        if failed { self.failed.insert(feed) }
        self.newPosts += newPosts
        finishIfDone()
    }

    /// Records the removal of a feed during its fetch, so that the round can finish.
    mutating func drop(_ feed: String) {
        guard feeds.contains(feed) else { return }
        ended.insert(feed)
        finishIfDone()
    }

    private mutating func finishIfDone() {
        if finished == nil, ended.count == feeds.count { finished = Date() }
    }
}
