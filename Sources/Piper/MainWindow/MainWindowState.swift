import AppKit

/// What the main window restores when it opens again.
///
/// One type covers the whole window.
struct MainWindowState: Codable, Equatable {

    // MARK: - Properties

    /// The folder the sidebar had selected. An empty string is the vault root.
    var selectedFolder = ""
    /// The file the list had selected, as a path relative to the vault root.
    var selectedFile: String?
    /// Whether the window showed the home page rather than the browser.
    var showsHome = true
    var sidebarWidth: CGFloat = 216
    var listWidth: CGFloat = 340
    var inspectorVisible = true

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
    func sidebarViewController(_ controller: SidebarViewController, didSelectFolder folder: String)
    func sidebarViewControllerDidRequestHome(_ controller: SidebarViewController)
}

/// What the file list reports upward.
@MainActor
protocol FileListViewControllerDelegate: AnyObject {
    func fileListViewController(_ controller: FileListViewController, didSelectFile path: String)
}

/// What the home page reports upward.
@MainActor
protocol HomeViewControllerDelegate: AnyObject {
    func homeViewController(_ controller: HomeViewController, didOpenFile path: String)
}
