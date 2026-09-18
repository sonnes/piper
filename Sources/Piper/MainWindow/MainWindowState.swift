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
    /// One capture section. The Inbox list scrolls to it.
    case section(String)
    /// The clipboard texts that the reader has not saved.
    case clipboard
    case allFiles
    /// One folder of the vault. The empty path is the root.
    case folder(String)
    /// The Claude sessions of a folder, by its absolute path.
    case sessions(String)

    /// The folder path, or the root for the inbox.
    var folder: String {
        if case .folder(let path) = self { return path }
        return ""
    }

    /// True for the rows that show captures in the file list.
    var showsCaptures: Bool {
        switch self {
        case .inbox, .section, .clipboard: return true
        case .home, .allFiles, .folder, .sessions: return false
        }
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
    /// True while the Claude pane is open on the right.
    var inspectorVisible = false

    // MARK: - Persistence

    private static let key = "mainWindowState"

    mutating func resetForVault() {
        selection = .folder("")
        selectedFile = nil
        expandedFolders = nil
    }

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
    func fileListViewController(_ controller: FileListViewController, didSelectNote id: UUID?)
}
