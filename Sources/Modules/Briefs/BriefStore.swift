import Foundation

/// One saved brief. The id is its date, as in `2026-10-30`.
public struct BriefFile: Identifiable, Equatable, Sendable {
    public let id: String
    public let url: URL
}

/// Keeps each brief as a Markdown file in a private folder, with the date as its name.
public struct BriefStore: Sendable {

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// The briefs, the newest first.
    public func files() -> [BriefFile] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".md") }.sorted(by: >).map { name in
            BriefFile(id: String(name.dropLast(3)), url: folder.appendingPathComponent(name))
        }
    }

    /// The links of each brief before this date. A rebuild of a day can use the links of that day again.
    public func linksBefore(_ date: Date, calendar: Calendar = .current) -> Set<String> {
        let id = Self.id(for: date, calendar: calendar)
        var links = Set<String>()
        for file in files() where file.id < id {
            guard let text = try? body(of: file) else { continue }
            for block in BriefDocument.blocks(in: text) {
                links.formUnion(block.links.map { BriefLinks.normalized($0.url) })
            }
        }
        return links
    }

    @discardableResult
    public func save(_ body: String, date: Date, title: String, sites: [String], feeds: [String], failed: [String],
                     calendar: Calendar = .current) throws -> BriefFile {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let id = Self.id(for: date, calendar: calendar)
        let url = folder.appendingPathComponent(id + ".md")
        let text = """
        ---
        title: \(Self.quoted(title))
        sites: \(Self.list(sites))
        feeds: \(Self.list(feeds))
        failed: \(Self.list(failed))
        ---

        \(body)

        """
        try Data(text.utf8).write(to: url, options: .atomic)
        return BriefFile(id: id, url: url)
    }

    /// The Markdown of a brief, without its frontmatter.
    public func body(of file: BriefFile) throws -> String {
        let text = try String(contentsOf: file.url, encoding: .utf8)
        guard text.hasPrefix("---\n"), let end = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) else {
            return text
        }
        return text[end.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func id(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func list(_ values: [String]) -> String {
        "[" + values.map(quoted).joined(separator: ", ") + "]"
    }

    /// A JSON string is a valid YAML string.
    private static func quoted(_ value: String) -> String {
        (try? JSONEncoder().encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
    }
}
