import AppKit

/// What the source list has selected, and what the file list therefore shows.
///
/// The home page and the capture inbox sit over the vault, because both hold
/// items that no folder holds.
enum SidebarSelection: Codable, Equatable {
    /// The search page, which the window opens on.
    case home
    /// The captures, which live in the database rather than in the vault.
    case inbox
    /// One folder of the vault. The empty path is the root.
    case folder(String)

    /// The folder path, or the root for the inbox.
    var folder: String {
        if case .folder(let path) = self { return path }
        return ""
    }
}

/// What the main window restores when it opens again.
///
/// One type covers the whole window.
struct MainWindowState: Codable, Equatable {

    // MARK: - Properties

    /// What the sidebar had selected. The window opens on the home page.
    var selection = SidebarSelection.home
    /// The folder the sidebar had selected. An empty string is the vault root.
    var selectedFolder: String { selection.folder }
    /// The file the list had selected, as a path relative to the vault root.
    var selectedFile: String?
    /// The capture the detail pane showed, while the inbox was selected.
    var selectedNote: UUID?
    /// The folders the sidebar had open. A nil value means the window has not
    /// opened before, so the sidebar opens every folder.
    var expandedFolders: [String]?
    var sidebarWidth: CGFloat = 216
    var listWidth: CGFloat = 340
    var inspectorVisible = false

    // MARK: - Persistence

    private static let key = "mainWindowState"

    static func restore() -> MainWindowState {
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(MainWindowState.self, from: data) else {
            return MainWindowState()
        }
        return state
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

// MARK: - Pane delegates

/// What the sidebar reports upward.
///
/// A pane never calls another pane. It reports to `MainWindowController`, which
/// decides what happens next.
@MainActor
protocol SidebarViewControllerDelegate: AnyObject {
    func sidebarViewController(_ controller: SidebarViewController, didSelect selection: SidebarSelection)
}

/// What the file list reports upward.
@MainActor
protocol FileListViewControllerDelegate: AnyObject {
    func fileListViewController(_ controller: FileListViewController, didSelectFile path: String)
    func fileListViewController(_ controller: FileListViewController, didSelectNote id: UUID)
}

