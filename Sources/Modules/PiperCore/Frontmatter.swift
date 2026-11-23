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
    /// The reason a present block failed to parse. `nil` when no block exists.
    public let problem: String?

    public func string(_ key: String) -> String? {
        metadata[key] as? String
    }

    /// Reads the block at the top of `raw`.
    ///
    /// The first line must be `---`. A later `---` on its own line closes the
    /// block. Any other text parses as a body with no metadata.
    public static func parse(_ raw: String) -> Frontmatter {
        // Split the original text, never a normalized copy, so that a file
        // written with CRLF keeps its CRLF bytes in the body.
        let lines = raw.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---",
              let end = lines.indices.dropFirst().first(where: {
                  lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) == "---"
              }) else {
            return Frontmatter(metadata: [:], body: raw, problem: nil)
        }
        let body = lines.dropFirst(end + 1).joined(separator: "\n")
        do {
            // The YAML payload drops the carriage returns. The body keeps them.
            let yaml = lines[1..<end].map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }.joined(separator: "\n")
            guard let metadata = try Yams.load(yaml: yaml) as? [String: Any] else {
                return Frontmatter(metadata: [:], body: body, problem: "Frontmatter is not a mapping")
            }
            return Frontmatter(metadata: metadata, body: body, problem: nil)
        } catch {
            return Frontmatter(metadata: [:], body: body, problem: error.localizedDescription)
        }
    }
}
