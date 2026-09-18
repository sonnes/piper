import Foundation

/// The `@` mention that the reader types at the end of a message.
public enum SessionComposerText {

    /// The part of a file name after the last `@`, while the reader types it.
    /// An empty string means the reader typed only `@`. The `@` must start the
    /// text or follow a space.
    public static func partialMention(_ text: String) -> String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        if at > text.startIndex, !text[text.index(before: at)].isWhitespace { return nil }
        let name = text[text.index(after: at)...]
        guard !name.contains(where: \.isWhitespace) else { return nil }
        return String(name)
    }

    /// The text with the partial mention replaced by `@path` and a space.
    public static func replacingMention(in text: String, with path: String) -> String {
        guard partialMention(text) != nil, let at = text.lastIndex(of: "@") else { return text }
        return String(text[..<at]) + "@" + path + " "
    }
}
