import Foundation

/// One link in the text of a block. The offset and the length count UTF-16 code
/// units, as the reader page does.
public struct BriefInlineLink: Equatable, Sendable {
    public let offset: Int
    public let length: Int
    public let url: String
}

/// One paragraph, heading, list item, quote, or code block of a brief.
public struct BriefBlock: Equatable, Sendable {
    /// `paragraph`, `heading`, `subheading`, `item`, `quote`, or `code`.
    public let kind: String
    public let text: String
    public let links: [BriefInlineLink]
}

/// Converts the Markdown of a brief to the blocks that the reader page shows.
public enum BriefDocument {

    private static let link = try! NSRegularExpression(pattern: #"\[([^\]]*)\]\(\s*<?(https?://[^)\s>]+)>?\s*\)"#)
    private static let item = try! NSRegularExpression(pattern: #"^\s*(?:[-*+]|\d+[.)])\s+"#)

    public static func blocks(in markdown: String) -> [BriefBlock] {
        var blocks: [BriefBlock] = []
        var paragraph: [String] = []
        var code: [String]?

        func endParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(inlineBlock("paragraph", paragraph.joined(separator: " ")))
            paragraph = []
        }

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let lines = code {
                    blocks.append(BriefBlock(kind: "code", text: lines.joined(separator: "\n"), links: []))
                    code = nil
                } else {
                    endParagraph()
                    code = []
                }
            } else if code != nil {
                code?.append(line)
            } else if trimmed.isEmpty {
                endParagraph()
            } else if let heading = heading(in: trimmed) {
                endParagraph()
                blocks.append(inlineBlock(heading.kind, heading.text))
            } else if trimmed.hasPrefix(">") {
                endParagraph()
                blocks.append(inlineBlock("quote", String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else if let match = item.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let marker = Range(match.range, in: line) {
                endParagraph()
                blocks.append(inlineBlock("item", String(line[marker.upperBound...]).trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(trimmed)
            }
        }
        endParagraph()
        return blocks.filter { !$0.text.isEmpty }
    }

    private static func heading(in line: String) -> (kind: String, text: String)? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level), line.dropFirst(level).first == " " else { return nil }
        return (level <= 2 ? "heading" : "subheading", String(line.dropFirst(level + 1)).trimmingCharacters(in: .whitespaces))
    }

    /// Takes out each link and the marks of bold text, italic text, and code.
    private static func inlineBlock(_ kind: String, _ markdown: String) -> BriefBlock {
        let source = markdown as NSString
        var text = ""
        var links: [BriefInlineLink] = []
        var position = 0
        for match in link.matches(in: markdown, range: NSRange(location: 0, length: source.length)) {
            text += plain(source.substring(with: NSRange(location: position, length: match.range.location - position)))
            let label = plain(source.substring(with: match.range(at: 1)))
            links.append(BriefInlineLink(offset: text.utf16.count, length: label.utf16.count,
                                         url: source.substring(with: match.range(at: 2))))
            text += label
            position = match.range.location + match.range.length
        }
        text += plain(source.substring(from: position))
        return BriefBlock(kind: kind, text: text, links: links)
    }

    private static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
    }
}
