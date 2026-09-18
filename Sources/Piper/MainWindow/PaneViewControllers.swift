import AppKit
import SwiftUI

/// A view controller whose view is a SwiftUI view.
///
/// AppKit owns the window chrome, the split view, and the responder chain,
/// because those give state restoration and keyboard handling at no cost.
/// SwiftUI draws the content of each pane. `MainWindowController` supplies that
/// content, so a pane holds no reference to another pane.
@MainActor
class HostingPaneViewController: NSViewController {

    // MARK: - Properties

    private var hostingView: NSHostingView<AnyView>?

    // MARK: - NSViewController

    override func loadView() {
        let hosting = NSHostingView(rootView: AnyView(Color.clear))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // A hosting view reports the fitting size of its content by default. A
        // window that takes a content view controller then resizes to that size,
        // which collapses this window to the height of one pane.
        hosting.sizingOptions = []
        hostingView = hosting
        view = hosting
    }

    // MARK: - API

    /// Replaces what the pane draws.
    func setContent(_ content: some View) {
        loadViewIfNeeded()
        hostingView?.rootView = AnyView(content)
    }
}

/// The folder tree. It reports a folder and never touches another pane.
@MainActor
final class SidebarViewController: HostingPaneViewController {
    weak var delegate: SidebarViewControllerDelegate?

    func select(_ selection: SidebarSelection) {
        delegate?.sidebarViewController(self, didSelect: selection)
    }
}

/// The files of the selected folder. It reports a file and nothing else.
@MainActor
final class FileListViewController: HostingPaneViewController {
    override var acceptsFirstResponder: Bool { true }
    weak var delegate: FileListViewControllerDelegate?

    func selectFile(_ path: String) {
        delegate?.fileListViewController(self, didSelectFile: path)
    }

    func selectNote(_ id: UUID?) {
        delegate?.fileListViewController(self, didSelectNote: id)
    }
}

/// The content of the selected file.
@MainActor
final class DetailViewController: HostingPaneViewController {}

/// The Claude pane on the right of the window.
@MainActor
final class SessionPaneViewController: HostingPaneViewController {}

