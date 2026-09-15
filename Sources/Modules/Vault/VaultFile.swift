import Foundation
import PiperCore

/// One file in the vault folder.
///
/// A vault holds files of any kind. Piper reports what the folder contains and
/// applies no document scheme to it. Frontmatter is optional metadata.
public struct VaultFile: Identifiable {

    // MARK: Properties

    /// The path from the vault root, with no leading slash.
    public let relativePath: String
    /// The last path component, with its extension.
    public let name: String
    /// The parent path from the vault root. Empty for a file in the root.
    public let folder: String
    /// The size of the file in bytes.
    public let size: Int
    /// The date of the last change to the content.
    public let modifiedAt: Date
    /// True when Piper can show the file as text.
    public let isText: Bool
    /// The content of the file. `nil` when the file is not text.
    public let text: String?

    private let frontmatter: Frontmatter?

    public var id: String { relativePath }
    public var isMarkdown: Bool { Self.markdownExtensions.contains((name as NSString).pathExtension.lowercased()) }

    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]

    /// The keys of the frontmatter block. Empty when the file has no block.
    public var metadata: [String: Any] { frontmatter?.metadata ?? [:] }

    /// The text after the frontmatter block, or the whole text when no block exists.
    public var body: String { frontmatter?.body ?? text ?? "" }

    /// The frontmatter block itself, including the delimiters.
    public var frontmatterPrefix: String { frontmatter?.prefix ?? "" }

    /// The reason a frontmatter block failed to parse.
    ///
    /// A file without a block has no problem. Only broken YAML gives a value here.
    public var frontmatterProblem: String? { frontmatter?.problem }

    /// The name to show in a list. Non-Markdown files keep their extension.
    ///
    /// The frontmatter `title` key comes first. Then the first Markdown heading
    /// of the body. Then the file name without its extension.
    public var title: String {
        guard isMarkdown else { return name }
        if let value = frontmatter?.string("title"), !value.trimmingCharacters(in: .whitespaces).isEmpty {
            return value
        }
        if let heading = Self.firstHeading(of: body) { return heading }
        return (name as NSString).deletingPathExtension
    }

    // MARK: Lifecycle

    public init(relativePath: String, size: Int, modifiedAt: Date, text: String?) {
        self.relativePath = relativePath
        self.name = (relativePath as NSString).lastPathComponent
        self.folder = (relativePath as NSString).deletingLastPathComponent
        self.size = size
        self.modifiedAt = modifiedAt
        self.isText = text != nil
        self.text = text
        self.frontmatter = Self.markdownExtensions.contains((relativePath as NSString).pathExtension.lowercased())
            ? text.map(Frontmatter.parse) : nil
    }
}

// MARK: - Hashable

extension VaultFile: Hashable {

    public static func == (lhs: VaultFile, rhs: VaultFile) -> Bool {
        lhs.relativePath == rhs.relativePath && lhs.size == rhs.size && lhs.modifiedAt == rhs.modifiedAt
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(relativePath)
    }
}

// MARK: - Headings

private extension VaultFile {

    /// Returns the text of a leading `# Heading` line.
    ///
    /// Blank lines before the heading are allowed. Any other text stops the search.
    static func firstHeading(of body: String) -> String? {
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard trimmed.hasPrefix("# ") else { return nil }
            let heading = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
            return heading.isEmpty ? nil : heading
        }
        return nil
    }
}
