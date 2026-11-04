import Foundation

/// Ranks files and commands for the command palette. The scores copy the
/// palette of Hubble.md (`packages/ui/src/lib/fuzzy.ts`): an exact match ranks
/// over a prefix, a prefix over a substring, and a substring over a subsequence.
public enum PaletteSearch {

    /// 1 for an exact match, 0.9 for a prefix, 0.75 for a substring, 0.45 for a
    /// subsequence, and 0 for no match. Case, spaces, `_`, and `-` do not count.
    public static func score(_ query: String, _ text: String) -> Double {
        let needle = normalize(query)
        if needle.isEmpty { return 1 }
        let haystack = normalize(text)
        if haystack == needle { return 1 }
        if haystack.hasPrefix(needle) { return 0.9 }
        if haystack.contains(needle) { return 0.75 }
        if isSubsequence(needle, of: haystack) { return 0.45 }
        return 0
    }

    /// A match in the file name ranks over a match in a folder name only.
    public static func score(_ query: String, path: String, title: String) -> Double {
        let name = (path as NSString).lastPathComponent
        return max(score(query, title), score(query, name), 0.8 * score(query, path))
    }

    /// A line of a file that holds the query.
    public struct Excerpt: Equatable, Sendable {
        /// The line, cut to the context around the match, with `…` where it is cut.
        public let text: String
        /// The match in `text`.
        public let match: Range<String.Index>
        /// The line number, from zero.
        public let line: Int
    }

    /// The lines that hold the query, in a literal search with no case. A
    /// query shorter than `minimumQueryLength` finds nothing.
    public static func excerpts(of query: String, in content: String,
                                limit: Int = 3, context: Int = 40) -> [Excerpt] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard needle.count >= minimumQueryLength else { return [] }
        var result: [Excerpt] = []
        for (number, rawLine) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            guard result.count < limit else { break }
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let found = line.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
            let start = line.index(found.lowerBound, offsetBy: -context, limitedBy: line.startIndex) ?? line.startIndex
            let end = line.index(found.upperBound, offsetBy: context, limitedBy: line.endIndex) ?? line.endIndex
            let prefix = start > line.startIndex ? "…" : ""
            let suffix = end < line.endIndex ? "…" : ""
            let text = prefix + line[start..<end] + suffix
            let offset = prefix.count + line.distance(from: start, to: found.lowerBound)
            let lower = text.index(text.startIndex, offsetBy: offset)
            let upper = text.index(lower, offsetBy: line.distance(from: found.lowerBound, to: found.upperBound))
            result.append(Excerpt(text: text, match: lower..<upper, line: number))
        }
        return result
    }

    public static let minimumQueryLength = 3
    /// The most files that the content search lists.
    public static let contentFileLimit = 50

    private static func normalize(_ text: String) -> String {
        String(text.lowercased().filter { !$0.isWhitespace && $0 != "_" && $0 != "-" })
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var remaining = needle[...]
        for character in haystack where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }
}
