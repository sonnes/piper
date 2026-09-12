import SwiftUI

struct MarkdownView: View {
    let text: String
    var baseURL: URL? = nil

    private struct Block: Identifiable {
        let id: Int
        let text: String
        let kind: String
        let level: Int
    }

    private var blocks: [Block] {
        let lines = text.components(separatedBy: .newlines)
        var result: [Block] = []
        var paragraph: [String] = []
        var code: [String]? = nil
        func add(_ text: String, _ kind: String = "paragraph", _ level: Int = 0) {
            result.append(Block(id: result.count, text: text, kind: kind, level: level))
        }
        func flush() {
            if !paragraph.isEmpty {
                let value = paragraph.joined(separator: "\n")
                let isTable = paragraph.count > 1 && paragraph[0].hasPrefix("|") && paragraph[1].range(of: "^\\|[ :|\\-]+$", options: .regularExpression) != nil
                add(value, isTable ? "table" : "paragraph")
                paragraph = []
            }
        }
        for line in lines {
            if line.hasPrefix("```") {
                flush()
                if let content = code { add(content.joined(separator: "\n"), "code"); code = nil } else { code = [] }
            } else if code != nil { code?.append(line) }
            else if line.isEmpty { flush() }
            else if line == "---" || line == "***" { flush(); add("", "rule") }
            else if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                if level <= 6, line.dropFirst(level).hasPrefix(" ") { flush(); add(String(line.dropFirst(level + 1)), "heading", level) }
                else { paragraph.append(line) }
            } else if line.hasPrefix("> ") { flush(); add(String(line.dropFirst(2)), "quote") }
            else { paragraph.append(line) }
        }
        flush()
        if let code { add(code.joined(separator: "\n"), "code") }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(blocks) { block in
                switch block.kind {
                case "heading":
                    Text(inline(block.text))
                        .font(.system(size: block.level == 1 ? 27 : block.level == 2 ? 20 : 16, weight: .semibold))
                        .padding(.top, 5)
                case "code":
                    Text(block.text).font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(13)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                case "table":
                    let rows = block.text.components(separatedBy: "\n").enumerated().filter { $0.offset != 1 }.map { line in
                        line.element.trimmingCharacters(in: CharacterSet(charactersIn: "|")).components(separatedBy: "|")
                    }
                    Grid(alignment: .topLeading, horizontalSpacing: 15, verticalSpacing: 10) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            GridRow {
                                ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                    Text(inline(cell.trimmingCharacters(in: .whitespaces)))
                                        .font(.system(size: 12, weight: index == 0 ? .semibold : .regular))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            if index == 0 { Divider() }
                        }
                    }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                case "rule": Divider()
                case "quote":
                    HStack(alignment: .top) {
                        Rectangle().fill(.tertiary).frame(width: 2)
                        Text(inline(block.text)).foregroundStyle(PiperTheme.secondary)
                    }.fixedSize(horizontal: false, vertical: true)
                default:
                    Text(inline(block.text)).font(.system(size: 14)).lineSpacing(5)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ text: String) -> AttributedString {
        let rendered = text.replacingOccurrences(of: "\\[\\^([^\\]]+)\\](?!:)", with: "[$1](piper-footnote://source/$1)", options: .regularExpression)
        return (try? AttributedString(markdown: rendered, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace), baseURL: baseURL)) ?? AttributedString(text)
    }
}
