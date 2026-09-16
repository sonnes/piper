import Captures
import Foundation
import PiperCore
import Vault

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

/// Writing an edited body back over a file.
enum WikiSave {

    /// Replaces the body of `file` and keeps its frontmatter byte for byte.
    ///
    /// The write refuses when the file on disk no longer matches what the editor
    /// opened. A different file means another editor wrote first, and the edits
    /// stay in memory instead of overwriting that work.
    static func body(_ body: String, of file: VaultFile, in vault: Vault) throws -> VaultFile {
        guard file.isMarkdown, file.isText else {
            throw PiperError("This file is available as a preview. Open it in another application to edit it.")
        }
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
