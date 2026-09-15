import Foundation
import Captures

/// Every notification name the application uses.
///
/// State changes inside a module travel through `Observation`. State changes
/// that cross a module boundary travel through `NotificationCenter`, and every
/// name for them is declared here. Post each one on the main queue.
extension Notification.Name {

    /// macOS changed the preferred sidebar row size.
    static let appleSideBarDefaultIconSizeChanged = Notification.Name("AppleSideBarDefaultIconSizeChanged")

    /// The vault finished a scan. The object is the `VaultScan`.
    static let vaultDidScan = Notification.Name("VaultDidScanNotification")

    /// The reader chose a different vault folder.
    static let vaultPathDidChange = Notification.Name("VaultPathDidChangeNotification")

    /// The export scan opened a file. The object is the application model.
    static let exportedDocumentDidOpen = Notification.Name("ExportedDocumentDidOpenNotification")

    /// A file on disk under the vault root changed.
    static let vaultFilesDidChange = Notification.Name("VaultFilesDidChangeNotification")

    /// A capture was saved. The object is the `Note`.
    static let captureDidSave = Notification.Name("CaptureDidSaveNotification")

    /// The set of captures changed for any reason, including undo.
    static let capturesDidChange = Notification.Name("CapturesDidChangeNotification")

    /// The unsaved state of the open file changed. The object is a `Bool`.
    static let editedStateDidChange = Notification.Name("EditedStateDidChangeNotification")

    /// The reader changed the application style.
    static let styleDidChange = Notification.Name("StyleDidChangeNotification")
}

/// Keys for the `userInfo` dictionary of the notifications above.
enum UserInfoKey {
    static let path = "path"
    static let anchor = "anchor"
    static let note = "note"
    static let scan = "scan"
}
