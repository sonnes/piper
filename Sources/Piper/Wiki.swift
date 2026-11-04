import Foundation
import Vault

/// The few things the views ask of a file that `VaultFile` names differently.
///
/// Piper has no opinion about the structure of the folder, so a file needs no
/// metadata. Where a file does carry frontmatter, these read it.
extension VaultFile {
    /// The whole text of the file, including any frontmatter.
    var raw: String { text ?? "" }

    /// The `description` key, when the file has one.
    var summary: String { metadata["description"] as? String ?? "" }

    /// The reason the frontmatter of this file failed to parse.
    var problem: String? { frontmatterProblem }
}
