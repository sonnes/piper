import Foundation
import Yams

/// The optional YAML block at the top of a text file.
///
/// Piper reads frontmatter where a file has it and ignores its absence. A file
/// without frontmatter is a normal file, not a problem to report.
public struct Frontmatter {
    /// The keys of the YAML block. Empty when the file carries no block.
    public let metadata: [String: Any]
    /// The text after the closing delimiter, or the whole text when no block exists.
    public let body: String
    /// The delimiters and the YAML between them, including the trailing newline.
    public let prefix: String
    /// The reason a present block failed to parse. `nil` when no block exists.
    public let problem: String?

    public var isEmpty: Bool { metadata.isEmpty }

    public func string(_ key: String) -> String? {
        metadata[key] as? String
    }

    public func strings(_ key: String) -> [String] {
        if let list = metadata[key] as? [String] { return list }
        if let one = metadata[key] as? String { return [one] }
        return []
    }

    /// Reads the block at the top of `raw`.
    ///
    /// The first line must be `---`. A later `---` on its own line closes the
    /// block. Any other text parses as a body with no metadata.
    public static func parse(_ raw: String) -> Frontmatter {
        // Split the original text, never a normalized copy. A file written with
        // CRLF must keep its CRLF bytes, because a save rewrites the prefix
        // verbatim and the reader did not edit those bytes.
        let lines = raw.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---",
              let end = lines.indices.dropFirst().first(where: {
                  lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) == "---"
              }) else {
            return Frontmatter(metadata: [:], body: raw, prefix: "", problem: nil)
        }
        let prefix = lines[0...end].joined(separator: "\n") + "\n"
        let body = lines.dropFirst(end + 1).joined(separator: "\n")
        do {
            // The YAML payload drops the carriage returns. The prefix keeps them.
            let yaml = lines[1..<end].map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }.joined(separator: "\n")
            guard let metadata = try Yams.load(yaml: yaml) as? [String: Any] else {
                return Frontmatter(metadata: [:], body: body, prefix: prefix, problem: "Frontmatter is not a mapping")
            }
            return Frontmatter(metadata: metadata, body: body, prefix: prefix, problem: nil)
        } catch {
            return Frontmatter(metadata: [:], body: body, prefix: prefix, problem: error.localizedDescription)
        }
    }
}
