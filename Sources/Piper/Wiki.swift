import Foundation
import Vault

extension VaultFile {
    /// The whole text of the file, including any frontmatter.
    var raw: String { text ?? "" }
}
