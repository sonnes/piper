import Foundation

/// Facts about the text of a capture that decide how Piper shows it.
public enum CaptureText {

    private static let codeEndings: Set<Character> = ["{", "}", "(", "[", ";", "\\"]
    private static let codeStarts: Set<Character> = ["}", ")", "]"]

    /// Returns true when the text is probably source code.
    ///
    /// The check looks only at the text, so a saved note gives the same
    /// result as the clipboard entry it came from. The text must have at least
    /// two lines. At least half of the lines must obey one of these rules:
    /// the line is indented, the line starts with a closing bracket, or the
    /// line ends with an opening bracket, a brace, a semicolon, or a
    /// backslash. An indented list item does not count. The check reads only
    /// the start of a long text.
    public static func looksLikeCode(_ text: String) -> Bool {
        let lines = text.prefix(4_000).split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }
        guard lines.count >= 2 else { return false }
        let codeLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let first = trimmed.first, let last = trimmed.last else { return false }
            if codeStarts.contains(first) || codeEndings.contains(last) { return true }
            return (line.hasPrefix("\t") || line.hasPrefix("  ")) && !isListItem(trimmed)
        }
        return codeLines.count * 2 >= lines.count
    }

    /// Returns the first line that is not blank, without its indentation.
    public static func firstLine(_ text: String) -> String {
        let line = text.prefix(4_000).split(whereSeparator: \.isNewline).first { !$0.allSatisfy(\.isWhitespace) } ?? ""
        return line.trimmingCharacters(in: .whitespaces)
    }

    private static func isListItem(_ line: String) -> Bool {
        if ["- ", "* ", "+ "].contains(where: line.hasPrefix) { return true }
        let digits = line.prefix { $0.isNumber }
        return !digits.isEmpty && line.dropFirst(digits.count).hasPrefix(". ")
    }
}
