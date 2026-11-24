import Foundation

struct WikiBlock: Identifiable, Equatable {
    enum Kind { case paragraph, heading, code, table, quote, rule, listItem, footnote }
    let id: Int
    var kind: Kind
    var text: String
}

enum WikiMarkdown {
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
        func add(_ kind: WikiBlock.Kind, _ text: String) {
            result.append(WikiBlock(id: result.count, kind: kind, text: text))
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
                    add(.code, code!.joined(separator: "\n")); code = nil
                } else { code?.append(line) }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                fence = String(trimmed.prefix(while: { $0 == trimmed.first }))
                code = []
            } else if trimmed.isEmpty { flush() }
            else if ["---", "***", "___"].contains(trimmed) { flush(); add(.rule, "") }
            else if trimmed.hasPrefix("#"), (1...6).contains(trimmed.prefix(while: { $0 == "#" }).count), trimmed.drop(while: { $0 == "#" }).hasPrefix(" ") {
                flush()
                let level = trimmed.prefix(while: { $0 == "#" }).count
                add(.heading, String(trimmed.dropFirst(level + 1)).replacingOccurrences(of: " +#+$", with: "", options: .regularExpression))
            } else if trimmed.hasPrefix(">") {
                flush()
                let quote = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                if result.last?.kind == .quote { result[result.count - 1].text += "\n" + quote }
                else { add(.quote, quote) }
            } else if let match = footnote.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                      let content = Range(match.range(at: 2), in: trimmed) {
                flush(); add(.footnote, String(trimmed[content]))
            } else if let match = list.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let content = Range(match.range(at: 3), in: line) {
                flush()
                let value = String(line[content])
                let isTask = value.hasPrefix("[ ] ") || value.lowercased().hasPrefix("[x] ")
                add(.listItem, isTask ? String(value.dropFirst(4)) : value)
            } else if line.hasPrefix("  "), result.last?.kind == .listItem, paragraph.isEmpty {
                result[result.count - 1].text += " " + trimmed
            } else { paragraph.append(trimmed) }
        }
        flush()
        if let code { add(.code, code.joined(separator: "\n")) }
        return result
    }
}
