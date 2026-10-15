import Foundation

/// The place of a quote in an article: the block that holds it and the offset
/// in that block.
///
/// The offset counts UTF-16 code units, as JavaScript does, so the reader page
/// and Piper agree on it.
public struct NoteAnchor: Codable, Equatable, Sendable {

    // MARK: - Properties

    public var quote: String
    public var block: Int
    public var offset: Int

    // MARK: - Initialization

    public init(quote: String, block: Int, offset: Int) {
        self.quote = quote
        self.block = block
        self.offset = offset
    }

    // MARK: - Locating

    /// The place of the quote in these blocks.
    ///
    /// The stored place wins when its text still matches. If not, the first
    /// match in the stored block wins, then the first match in another block.
    /// Nil means that the article no longer holds the quote.
    public func locate(in blocks: [String]) -> NoteAnchor? {
        guard !quote.isEmpty else { return nil }
        let length = (quote as NSString).length
        if blocks.indices.contains(block) {
            let text = blocks[block] as NSString
            if offset >= 0, offset + length <= text.length,
               text.substring(with: NSRange(location: offset, length: length)) == quote {
                return self
            }
            let found = text.range(of: quote)
            if found.location != NSNotFound { return NoteAnchor(quote: quote, block: block, offset: found.location) }
        }
        for (index, text) in blocks.enumerated() where index != block {
            let found = (text as NSString).range(of: quote)
            if found.location != NSNotFound { return NoteAnchor(quote: quote, block: index, offset: found.location) }
        }
        return spanning(blocks)
    }

    /// The quote with one space for each run of white space, and without
    /// invisible characters such as a soft hyphen.
    ///
    /// The Reader tab collapses white space in the same way, so a selection
    /// from a browser matches the article text.
    public static func normalized(_ text: String) -> String {
        let invisible: Set<Character> = ["\u{00AD}", "\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}"]
        return text.filter { !invisible.contains($0) }
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

// MARK: - Private

private extension NoteAnchor {

    /// The start of a quote that runs over more than one block, or that the
    /// article holds only in part.
    ///
    /// The search joins the blocks with spaces. It tries the whole quote, then
    /// shorter starts of it, down to four words. The mark stops at the end of
    /// the block where the match starts.
    func spanning(_ blocks: [String]) -> NoteAnchor? {
        let words = quote.split(separator: " ")
        guard words.count >= Self.minimumWords else { return nil }
        let joined = blocks.joined(separator: " ") as NSString
        var count = words.count
        while count >= Self.minimumWords {
            let found = joined.range(of: words.prefix(count).joined(separator: " "))
            if found.location != NSNotFound { return place(found, in: blocks) }
            count = count > 8 ? count * 3 / 4 : count - 1
        }
        return nil
    }

    /// Converts a range in the joined text to a place in one block.
    func place(_ range: NSRange, in blocks: [String]) -> NoteAnchor? {
        var start = 0
        for (index, text) in blocks.enumerated() {
            let length = (text as NSString).length
            if range.location < start + length {
                let offset = range.location - start
                let part = (text as NSString).substring(with: NSRange(location: offset, length: min(range.length, length - offset)))
                return NoteAnchor(quote: part, block: index, offset: offset)
            }
            start += length + 1
        }
        return nil
    }

    static let minimumWords = 4
}

/// The text of a highlight note: the quote, then the note of the reader.
public enum HighlightText {

    /// The note of the reader after the quote. Empty when the highlight has none.
    public static func comment(of text: String, quote: String?) -> String {
        if let quote, !quote.isEmpty, text.hasPrefix(quote) {
            return String(text.dropFirst(quote.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let end = text.range(of: "\n\n") else { return "" }
        return String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The highlight text with a new note after the quote and any earlier note.
    public static func adding(_ comment: String, to text: String) -> String {
        let comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        return comment.isEmpty ? text : text + "\n\n" + comment
    }
}

/// The questions and answers of a question note.
///
/// The note text is plain, so the reader can edit it. The first line names the
/// action and the quote. Each paragraph that starts with `Q: ` opens a turn,
/// and the paragraphs after it are the answer.
public struct NoteThread: Equatable, Sendable {

    /// One question and its answer. The first turn of an Explain or a Define
    /// has no question.
    public struct Turn: Equatable, Sendable {
        public var question: String?
        public var answer: String

        public init(question: String? = nil, answer: String = "") {
            self.question = question
            self.answer = answer
        }
    }

    // MARK: - Properties

    public static let questionPrefix = "Q: "

    public let title: String
    public let turns: [Turn]

    // MARK: - Initialization

    public init(_ text: String) {
        let paragraphs = text.components(separatedBy: "\n\n")
        title = paragraphs.first ?? ""
        var turns = [Turn()]
        for paragraph in paragraphs.dropFirst() {
            if paragraph.hasPrefix(Self.questionPrefix) {
                let question = String(paragraph.dropFirst(Self.questionPrefix.count))
                if let only = turns.first, turns.count == 1, only.question == nil, only.answer.isEmpty {
                    turns = [Turn(question: question)]
                } else {
                    turns.append(Turn(question: question))
                }
            } else {
                let last = turns.count - 1
                turns[last].answer += (turns[last].answer.isEmpty ? "" : "\n\n") + paragraph
            }
        }
        self.turns = turns
    }

    /// The paragraph that opens a follow-up question.
    public static func question(_ text: String) -> String {
        questionPrefix + text.replacingOccurrences(of: "\n\n", with: "\n")
    }
}
