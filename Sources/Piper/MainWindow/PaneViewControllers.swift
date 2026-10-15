import AppKit
import SwiftUI

/// The card and tabs share the available width of the detail pane.
@MainActor @Observable
final class DetailPaneLayout {
    var width: CGFloat = 0

    var cardWidth: CGFloat {
        min(AppDefaults.SessionCard.width, max(0, width - 2 * AppDefaults.SessionCard.margin))
    }

    var stacksControls: Bool {
        width < AppDefaults.SessionCard.width + 2 * AppDefaults.SessionCard.margin + AppDefaults.SessionCard.tabsMinimumWidth
    }

    var cardBottomInset: CGFloat { stacksControls ? AppDefaults.TabIsland.clearance : 0 }
    var tabsTrailingInset: CGFloat { stacksControls ? 0 : AppDefaults.SessionCard.width + AppDefaults.SessionCard.margin }
}

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
///
/// The session card floats over the bottom right corner of the content, in a
/// hosting view of its own. That view takes the size of the pill or the card,
/// so a click anywhere else reaches the content.
@MainActor
final class DetailViewController: NSViewController {

    // MARK: - Properties

    private var hostingView: NSHostingView<AnyView>?
    private var overlayView: NSHostingView<AnyView>?
    private let layout = DetailPaneLayout()

    // MARK: - NSViewController

    override func loadView() {
        let container = NSView()
        let hosting = NSHostingView(rootView: AnyView(Color.clear))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // See HostingPaneViewController: the pane must not take the size of its content.
        hosting.sizingOptions = []
        let overlay = NSHostingView(rootView: AnyView(EmptyView()))
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.sizingOptions = [.intrinsicContentSize]
        container.addSubview(hosting)
        container.addSubview(overlay)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            overlay.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            overlay.heightAnchor.constraint(lessThanOrEqualTo: container.heightAnchor, multiplier: AppDefaults.SessionCard.paneFraction)
        ])
        hostingView = hosting
        overlayView = overlay
        view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if layout.width != view.bounds.width { layout.width = view.bounds.width }
    }

    // MARK: - API

    /// Replaces what the pane draws.
    func setContent(_ content: some View) {
        loadViewIfNeeded()
        hostingView?.rootView = AnyView(content.environment(layout))
    }

    /// Replaces what floats over the bottom right corner of the pane.
    func setOverlay(_ content: some View) {
        loadViewIfNeeded()
        overlayView?.rootView = AnyView(content.environment(layout))
    }
}

