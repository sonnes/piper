import Foundation

/// Removes each image and each link that no loaded page or feed holds. The
/// agent reads text from unknown authors, so its Markdown is not trusted.
public enum BriefLinks {

    private static let inline = try! NSRegularExpression(
        pattern: #"(!?)\[([^\]]*)\]\(\s*<?([^)\s>]*)>?(?:\s+"[^"]*")?\s*\)"#)
    private static let reference = try! NSRegularExpression(pattern: #"(?m)^\s*\[[^\]]+\]:\s*\S+.*$\n?"#)
    private static let html = try! NSRegularExpression(pattern: #"</?[a-zA-Z][^>]*>"#)
    private static let bare = try! NSRegularExpression(pattern: #"(?<!\]\()<?\b[a-zA-Z][a-zA-Z0-9+.-]*://[^\s)>\]]+>?"#)

    public static func clean(_ markdown: String, known: Set<String>) -> String {
        let allowed = Set(known.map(normalized))
        var text = reference.stringByReplacingMatches(in: markdown, range: range(of: markdown), withTemplate: "")
        text = html.stringByReplacingMatches(in: text, range: range(of: text), withTemplate: "")
        text = replace(inline, in: text) { groups in
            if !groups[1].isEmpty { return "" }
            return allowed.contains(normalized(groups[3])) ? "[\(groups[2])](\(groups[3]))" : groups[2]
        }
        return replace(bare, in: text) { groups in
            let url = groups[0].trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            return allowed.contains(normalized(url)) ? url : ""
        }
    }

    /// True if the set from `BriefStore.linksBefore` holds this link.
    public static func isSeen(_ url: String, in seen: Set<String>) -> Bool {
        seen.contains(normalized(url))
    }

    /// Two forms of one link compare as equal: the fragment and a last slash do not count.
    public static func normalized(_ url: String) -> String {
        var value = url
        if let fragment = value.firstIndex(of: "#") { value = String(value[..<fragment]) }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    private static func range(of text: String) -> NSRange { NSRange(text.startIndex..., in: text) }

    private static func replace(_ expression: NSRegularExpression, in text: String, _ change: ([String]) -> String) -> String {
        var result = text
        for match in expression.matches(in: text, range: range(of: text)).reversed() {
            guard let whole = Range(match.range, in: result) else { continue }
            let groups = (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
            result.replaceSubrange(whole, with: change(groups))
        }
        return result
    }
}
