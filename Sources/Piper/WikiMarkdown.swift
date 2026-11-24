import Foundation

struct WikiBlock: Identifiable, Equatable {
    enum Kind { case paragraph, heading, code, table, quote, rule, listItem, footnote }
    let id: Int
    var kind: Kind
    var text: String
    var level = 0
    var marker = ""
    var anchor = ""
}

enum WikiMarkdown {
    static func anchor(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "[^\\p{L}\\p{N} _-]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " +", with: "-", options: .regularExpression)
    }

    /// The blocks that a note anchor counts: the blocks with text, in order.
    /// `textBlocks` in `web/src/ReaderLayer.tsx` counts the same blocks.
    static func textBlocks(_ text: String) -> [WikiBlock] {
        parse(text).filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    static func parse(_ text: String) -> [WikiBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [WikiBlock] = []
        var paragraph: [String] = []
        var code: [String]?
        var fence = ""
        var language = ""
        var anchors: [String: Int] = [:]
        func add(_ kind: WikiBlock.Kind, _ text: String, level: Int = 0, marker: String = "", anchor: String = "") {
            result.append(WikiBlock(id: result.count, kind: kind, text: text, level: level, marker: marker, anchor: anchor))
        }
        func flush() {
            guard !paragraph.isEmpty else { return }
            let table = paragraph.count > 1 && paragraph[1].contains("|") && paragraph[1].range(of: "^[ |:-]+$", options: .regularExpression) != nil
            add(table ? .table : .paragraph, paragraph.joined(separator: table ? "\n" : " "))
            paragraph = []
        }
        let list = try! NSRegularExpression(pattern: #"^(\s*)([-+*]|\d+[.)])\s+(.*)$"#)
        let footnote = try! NSRegularExpression(pattern: #"^\[\^([^\]]+)\]:\s*(.*)$"#)
        for line in lines {
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
}
