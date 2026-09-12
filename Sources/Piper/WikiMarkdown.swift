import Foundation

struct WikiBlock: Identifiable, Equatable {
    enum Kind { case paragraph, heading, code, table, quote, rule, listItem, footnote }
    let id: Int
    var kind: Kind
    var text: String
    var level = 0
    var marker = ""
    var anchor = ""
    var sourceLine = 0
}

enum WikiMarkdown {
    static func range(ofAnchor requested: String, in text: String) -> NSRange? {
        guard let block = parse(text).first(where: { !$0.anchor.isEmpty && ($0.anchor == requested || $0.anchor == anchor(requested)) }) else { return nil }
        let lines = text.components(separatedBy: "\n")
        let location = lines.prefix(block.sourceLine).reduce(0) { $0 + $1.utf16.count + 1 }
        return NSRange(location: location, length: lines[block.sourceLine].utf16.count)
    }

    static func anchor(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "[^\\p{L}\\p{N} _-]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " +", with: "-", options: .regularExpression)
    }

    static func parse(_ text: String) -> [WikiBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [WikiBlock] = []
        var paragraph: [String] = []
        var code: [String]?
        var fence = ""
        var language = ""
        var anchors: [String: Int] = [:]
        var sourceLine = 0
        func add(_ kind: WikiBlock.Kind, _ text: String, level: Int = 0, marker: String = "", anchor: String = "") {
            result.append(WikiBlock(id: result.count, kind: kind, text: text, level: level, marker: marker, anchor: anchor, sourceLine: sourceLine))
        }
        func flush() {
            guard !paragraph.isEmpty else { return }
            let table = paragraph.count > 1 && paragraph[1].contains("|") && paragraph[1].range(of: "^[ |:-]+$", options: .regularExpression) != nil
            add(table ? .table : .paragraph, paragraph.joined(separator: table ? "\n" : " "))
            paragraph = []
        }
        let list = try! NSRegularExpression(pattern: #"^(\s*)([-+*]|\d+[.)])\s+(.*)$"#)
        let footnote = try! NSRegularExpression(pattern: #"^\[\^([^\]]+)\]:\s*(.*)$"#)
        for (lineIndex, line) in lines.enumerated() {
            sourceLine = lineIndex
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if code != nil {
                if trimmed.hasPrefix(fence), trimmed.dropFirst(fence.count).allSatisfy({ $0 == fence.first || $0.isWhitespace }) {
                    add(.code, code!.joined(separator: "\n"), marker: language); code = nil
                } else { code?.append(line) }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                fence = String(trimmed.prefix(while: { $0 == trimmed.first }))
                language = String(trimmed.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
                code = []
            } else if trimmed.isEmpty { flush() }
            else if ["---", "***", "___"].contains(trimmed) { flush(); add(.rule, "") }
            else if trimmed.hasPrefix("#"), (1...6).contains(trimmed.prefix(while: { $0 == "#" }).count), trimmed.drop(while: { $0 == "#" }).hasPrefix(" ") {
                flush()
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let title = String(trimmed.dropFirst(level + 1)).replacingOccurrences(of: " +#+$", with: "", options: .regularExpression)
                let slug = anchor(title)
                let count = anchors[slug, default: 0]
                anchors[slug] = count + 1
                add(.heading, title, level: level, anchor: count == 0 ? slug : "\(slug)-\(count)")
            } else if trimmed.hasPrefix(">") {
                flush()
                let quote = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                if result.last?.kind == .quote { result[result.count - 1].text += "\n" + quote }
                else { add(.quote, quote) }
            } else if let match = footnote.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                      let id = Range(match.range(at: 1), in: trimmed), let content = Range(match.range(at: 2), in: trimmed) {
                flush(); add(.footnote, String(trimmed[content]), marker: String(trimmed[id]), anchor: "fn-" + String(trimmed[id]))
            } else if let match = list.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let indent = Range(match.range(at: 1), in: line), let marker = Range(match.range(at: 2), in: line), let content = Range(match.range(at: 3), in: line) {
                flush()
                let value = String(line[content])
                var bullet = line[marker].first?.isNumber == true ? String(line[marker]) : "•"
                var body = value
                if value.hasPrefix("[ ] ") || value.lowercased().hasPrefix("[x] ") {
                    bullet = value.lowercased().hasPrefix("[x]") ? "☑" : "☐"
                    body = String(value.dropFirst(4))
                }
                add(.listItem, body, level: line[indent].count / 2, marker: bullet)
            } else if line.hasPrefix("  "), result.last?.kind == .listItem, paragraph.isEmpty {
                result[result.count - 1].text += " " + trimmed
            } else { paragraph.append(trimmed) }
        }
        flush()
        if let code { add(.code, code.joined(separator: "\n"), marker: language) }
        return result
    }

    static func inline(_ text: String) -> AttributedString {
        let pattern = #"`+[^`]*`+|!\[([^\]]*)\]\([^)]*\)|\[\[([^\]|]+)(?:\|([^\]]+))?\]\]|\[\^([^\]]+)\](?!:)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        var rendered = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: rendered) else { continue }
            func group(_ index: Int) -> String? { Range(match.range(at: index), in: text).map { String(text[$0]) } }
            if String(rendered[range]).hasPrefix("`") { continue }
            if let alt = group(1) { rendered.replaceSubrange(range, with: "Image: " + alt); continue }
            if let target = group(2) {
                var components = URLComponents()
                components.scheme = "piper-note"; components.host = "open"
                components.queryItems = [URLQueryItem(name: "target", value: target)]
                let label = (group(3) ?? target.components(separatedBy: "#").first ?? target).replacingOccurrences(of: "]", with: "\\]")
                rendered.replaceSubrange(range, with: "[\(label)](\(components.url!.absoluteString))")
            } else if let footnote = group(4) {
                let target = footnote.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? footnote
                rendered.replaceSubrange(range, with: "[\(footnote)](piper-footnote://source/\(target))")
            }
        }
        return (try? AttributedString(markdown: rendered, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
