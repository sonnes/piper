import Foundation

/// One item that a message names as context: a file, a web link, or the text
/// of a note.
///
/// A transcript stores each item as one string. A file is its absolute path, a
/// link is its address, and a note is its text after `note:`.
public enum ContextItem: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    /// A file, by its absolute path.
    case file(String)
    /// A web page, by its HTTP or HTTPS address.
    case link(URL)
    /// The text of a note.
    case note(String)

    private static let notePrefix = "note:"

    public init(_ stored: String) {
        if stored.hasPrefix(Self.notePrefix) {
            self = .note(String(stored.dropFirst(Self.notePrefix.count)))
        } else if let url = URL(string: stored), ["http", "https"].contains(url.scheme?.lowercased()) {
            self = .link(url)
        } else {
            self = .file(stored)
        }
    }

    public init(stringLiteral value: String) { self.init(value) }

    public init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stored)
    }

    /// The string that a transcript stores.
    public var stored: String {
        switch self {
        case .file(let path): return path
        case .link(let url): return url.absoluteString
        case .note(let text): return Self.notePrefix + text
        }
    }

    /// What follows a slash command: the path, the address, or the text.
    public var argument: String {
        switch self {
        case .file(let path): return path
        case .link(let url): return url.absoluteString
        case .note(let text): return text
        }
    }

    /// The line or lines that name the item under a message.
    var contextLines: String {
        switch self {
        case .file(let path): return "Context file: " + path
        case .link(let url): return "Context link: " + url.absoluteString
        case .note(let text):
            return "Context note:\n" + text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { "> " + $0 }.joined(separator: "\n")
        }
    }
}
