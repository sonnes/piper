import AppKit

/// What the source list has selected, and what the other panes therefore show.
///
/// The capture inbox sits over the vault, because it holds items that no
/// folder holds. Only the captures use the list pane.
enum SidebarSelection: Codable, Equatable {
    /// The captures, which live in the database rather than in the vault. The
    /// window opens on Inbox.
    case inbox
    /// One capture section. The Inbox list scrolls to it.
    case section(String)
    case archived
    /// The clipboard texts that the reader has not saved. The detail pane shows them.
    case clipboard
    /// One folder of the vault. The empty path is the root. The detail pane
    /// keeps the last file.
    case folder(String)
    /// One file of the vault, picked in the sidebar tree.
    case file(String)
    /// A folder of the Claude group, by its absolute path. The detail pane
    /// shows `AppModel.selectedSession` when it belongs to the folder, or a new session.
    case sessions(String)

    /// The folder path, the folder that holds the file, or the root for the inbox.
    var folder: String {
        switch self {
        case .folder(let path): return path
        case .file(let path): return (path as NSString).deletingLastPathComponent
        default: return ""
        }
    }

    /// True for the rows that show captures or clipboard texts.
    var showsCaptures: Bool {
        switch self {
        case .inbox, .section, .clipboard, .archived: return true
        case .folder, .file, .sessions: return false
        }
    }

    /// True for the rows that show the list pane between the sidebar and the detail pane.
    var showsList: Bool {
        switch self {
        case .inbox, .section, .archived: return true
        case .clipboard, .folder, .file, .sessions: return false
        }
    }
}

/// What the main window restores when it opens again.
///
/// One type covers the whole window.
struct MainWindowState: Codable, Equatable {

    // MARK: - Properties

    /// What the sidebar had selected. The window opens on Inbox.
    var selection = SidebarSelection.inbox
    /// The folder the sidebar had selected. An empty string is the vault root.
    var selectedFolder: String { selection.folder }
    /// The file the detail pane showed, as a path relative to the vault root.
    var selectedFile: String?
    /// The capture the detail pane showed, while the inbox was selected.
    var selectedNote: UUID?
    /// The rows the sidebar had open: folder paths and the keys of
    /// `SidebarOutline`. A window that has not opened before has none, so
    /// every folder starts closed.
    var expandedRows: [String]?
    var sidebarWidth: CGFloat = 210
    var listWidth: CGFloat = 350

    // MARK: - Persistence

    private static let key = "mainWindowState"

    mutating func resetForVault() {
        selection = .folder("")
        selectedFile = nil
        expandedRows = nil
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

/// What the capture list reports upward.
@MainActor
protocol CaptureListViewControllerDelegate: AnyObject {
    func captureListViewController(_ controller: CaptureListViewController, didSelectNote id: UUID?)
}
