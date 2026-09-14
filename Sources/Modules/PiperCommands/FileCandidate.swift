import Foundation

/// One file that the search bar can offer.
///
/// The parser does not read the file system. The caller holds the file list and
/// gives it to each parse, so the parser stays a pure function of its input.
public struct FileCandidate: Identifiable, Hashable, Sendable {
    public let url: URL
    /// The folder that holds the file, relative to the Wiki folder. Empty at the root.
    public let folder: String
    /// The text that a text match reads, and that a text row shows.
    public let excerpt: String

    public var id: URL { url }
    public var name: String { url.lastPathComponent }
    /// The path a row shows, such as `engineering/payment-retries.md`.
    public var path: String { folder.isEmpty ? name : folder + "/" + name }

    // MARK: - Life Cycle

    public init(url: URL, folder: String = "", excerpt: String = "") {
        self.url = url
        self.folder = folder
        self.excerpt = excerpt
    }
}
