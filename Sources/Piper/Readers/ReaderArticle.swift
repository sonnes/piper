import Foundation
import Captures
import PiperCore

/// The clean text of a web page, as the Reader tab shows it.
struct ReaderArticle: Codable, Equatable {

    /// One paragraph, heading, list item, quote, code block, image, video,
    /// video frame, or table.
    struct Block: Codable, Equatable {
        /// `paragraph`, `heading`, `subheading`, `item`, `quote`, `code`,
        /// `image`, `video`, `embed`, or `table`.
        let kind: String
        /// The text, or the caption of an image or a video. A table has no text.
        let text: String
        /// The address of an image or a video, or the page of a video frame.
        var src: String? = nil
        var alt: String? = nil
        /// The still image of a video.
        var poster: String? = nil
        /// The cells of a table, row by row. The first row is the header.
        var rows: [[String]]? = nil
    }

    let url: URL
    let site: String
    let title: String
    /// The author and the reading time.
    let byline: [String]
    let blocks: [Block]

    var texts: [String] { blocks.map(\.text) }
    var words: Int { blocks.reduce(0) { $0 + ReadingTime.words(in: $1.text) } }

    init(url: URL, site: String, title: String, byline: [String], blocks: [Block]) {
        self.url = url
        self.site = site
        self.title = title
        self.byline = byline
        self.blocks = blocks
    }

    /// An article with the reading time in its byline.
    init(url: URL, site: String, title: String, author: String, blocks: [Block]) {
        let minutes = ReadingTime.minutes(words: blocks.reduce(0) { $0 + ReadingTime.words(in: $1.text) })
        self.init(url: url, site: site, title: title, byline: [author, "\(minutes) min read"].filter { !$0.isEmpty }, blocks: blocks)
    }

    /// The article in the text of a page that a browser showed. Each line of
    /// 40 characters or more is a paragraph. Shorter lines are menus and
    /// buttons. Nil when no line is long enough.
    init?(url: URL, title: String?, pageText: String) {
        let blocks = pageText.components(separatedBy: .newlines)
            .map(NoteAnchor.normalized)
            .filter { $0.count >= Self.shortestParagraph && $0 != title }
            .map { Block(kind: "paragraph", text: $0) }
        guard !blocks.isEmpty else { return nil }
        let site = Site(url)?.key ?? url.absoluteString
        self.init(url: url, site: site, title: title ?? site, author: "", blocks: blocks)
    }

    private static let shortestParagraph = 40
}
