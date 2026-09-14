import Foundation
import PiperCore

/// Reads the frontmatter of a file without reading the whole file.
///
/// A `SKILL.md` body runs to thousands of lines, and an index scan needs four
/// keys from the top. The reader takes a bounded prefix of the bytes and parses
/// the block out of that.
enum FrontmatterReader {
    // MARK: - Properties

    /// How many bytes the reader takes from the front of a file.
    ///
    /// A frontmatter block that does not fit in 8 KB is not a frontmatter block.
    static let byteLimit = 8 * 1024

    // MARK: - Functions

    /// Returns the frontmatter at the top of `url`, or `nil` when the file cannot be read.
    static func read(_ url: URL, byteLimit: Int = byteLimit) -> Frontmatter? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: byteLimit), let text = decode(data) else { return nil }
        return Frontmatter.parse(text)
    }
}

// MARK: - Private

private extension FrontmatterReader {
    /// Decodes UTF-8 bytes that a byte limit can cut inside a character.
    ///
    /// A UTF-8 character is at most four bytes long, so dropping up to three
    /// trailing bytes finds the last whole character.
    static func decode(_ data: Data) -> String? {
        var bytes = data
        for _ in 0...3 {
            if let text = String(data: bytes, encoding: .utf8) { return text }
            guard !bytes.isEmpty else { return nil }
            bytes = bytes.dropLast()
        }
        return nil
    }
}
