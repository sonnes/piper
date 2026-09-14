import Captures
import Foundation
import PiperCore
import Vault
import Yams

/// The few things the views ask of a file that `VaultFile` names differently.
///
/// Piper has no opinion about the structure of the folder, so a file needs no
/// metadata. Where a file does carry frontmatter, these read it.
extension VaultFile {
    /// The whole text of the file, including any frontmatter.
    var raw: String { text ?? "" }

    /// The text that the editor shows. Frontmatter stays out of the editor.
    var editableBody: String { body }

    /// The `description` key, when the file has one.
    var summary: String { metadata["description"] as? String ?? "" }

    /// The reason the frontmatter of this file failed to parse.
    var problem: String? { frontmatterProblem }
}

/// Writing capture notes into the folder as one Markdown file.
///
/// The export writes the file the reader names and nothing else. It builds no
/// index, and it appends to no log. The folder belongs to the reader.
enum WikiExport {

    // MARK: - Functions

    /// Builds the Markdown for a set of captures.
    ///
    /// The frontmatter holds the title, the time, and the source links. Piper
    /// writes these because it created the file. It requires them of no other
    /// file in the folder.
    static func markdown(notes: [Note], title: String, sourceURL: String) throws -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty, !name.isEmpty else { throw PiperError("Enter a title, and select at least one note.") }
        if !sourceURL.isEmpty {
            guard let url = URL(string: sourceURL), ["http", "https"].contains(url.scheme ?? ""), url.host != nil else {
                throw PiperError("Enter an HTTP or HTTPS source URL.")
            }
        }
        let urls = Array(Set(notes.flatMap(\.sourceURLs) + (sourceURL.isEmpty ? [] : [sourceURL]))).sorted()
        var metadata: [String: Any] = [
            "title": name.replacingOccurrences(of: "\n", with: " "),
            "created": ISO8601DateFormatter().string(from: Date())
        ]
        if !urls.isEmpty { metadata["sources"] = urls }
        let yaml = try Yams.dump(object: metadata, sortKeys: true)
        let body = notes.map(\.text).joined(separator: "\n\n---\n\n")
        let references = urls.isEmpty ? "" : "\n\n## Sources\n\n" + urls.map { "* <\($0)>" }.joined(separator: "\n")
        return "---\n" + yaml + "---\n\n# " + name.replacingOccurrences(of: "\n", with: " ") + "\n\n" + body + references + "\n"
    }

    /// A file name for a title. The reader can change it in the save panel.
    static func fileName(_ title: String) -> String {
        let value = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return (value.isEmpty ? "capture" : String(value.prefix(80))) + ".md"
    }
}

/// Writing an edited body back over a file.
enum WikiSave {

    /// Replaces the body of `file` and keeps its frontmatter byte for byte.
    ///
    /// The write refuses when the file on disk no longer matches what the editor
    /// opened. A different file means another editor wrote first, and the edits
    /// stay in memory instead of overwriting that work.
    static func body(_ body: String, of file: VaultFile, in vault: Vault) throws -> VaultFile {
        let prefix = file.frontmatterPrefix
        let separator = prefix.isEmpty || prefix.last?.isNewline == true || body.isEmpty ? "" : "\n"
        let raw = prefix + separator + body
        let data = Data(raw.utf8)
        guard data != Data(file.raw.utf8) else { return file }
        let url = try vault.containedURL(file.id)
        guard try Data(contentsOf: url) == Data(file.raw.utf8) else {
            throw PiperError("This file changed in another editor. Your edits are still open. Copy them before discarding changes and reopening the file.")
        }
        try data.write(to: url, options: .atomic)
        return try vault.read(file.id)
    }
}
