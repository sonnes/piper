import Foundation
import Vault

/// Builds a `VaultFile` from text, the way a scan would.
///
/// The tests care about the text and the path. Size and date follow from them.
func makeFile(_ raw: String, path: String) -> VaultFile {
    VaultFile(relativePath: path, size: raw.utf8.count, modifiedAt: Date(), text: raw)
}
