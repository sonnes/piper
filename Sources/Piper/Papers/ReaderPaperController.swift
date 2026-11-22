import AppKit
import SwiftUI

/// What a reader paper reports to the desk.
@MainActor
protocol ReaderPaperControllerDelegate: AnyObject {
    func readerPaperDidBecomeKey(_ controller: ReaderPaperController)
    func readerPaperWillClose(_ controller: ReaderPaperController)
    /// The first message of a new session started the session.
    func readerPaper(_ controller: ReaderPaperController, didStart session: UUID)
}

/// Owns one reader paper: a frameless window with round corners for one item.
///
/// The session card floats over the bottom right corner of the paper while
/// the paper has the keyboard focus.
@MainActor
final class ReaderPaperController: NSWindowController, NSWindowDelegate {

    // MARK: - Properties

    weak var delegate: ReaderPaperControllerDelegate?
    private(set) var item: PaperItem
    private let model: AppModel
    private let viewController = ReaderPaperViewController()

    // MARK: - Initialization

    init(item: PaperItem, model: AppModel, frame: NSRect) {
        self.item = item
        self.model = model
        let window = PaperWindow(size: frame.size, minimumSize: AppDefaults.Papers.readerMinimumSize)
        window.title = "Paper"
        super.init(window: window)
        window.delegate = self
        window.escape = { [weak window] in window?.performClose(nil) }
        window.contentViewController = viewController
        window.setFrame(frame, display: false)
        let layer = viewController.view.layer
        layer?.cornerRadius = AppDefaults.Papers.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - API

    /// Shows the paper and gives it the keyboard.
    func focus() {
        window?.makeKeyAndOrderFront(nil)
        QA.activate()
    }

    /// Shows another item in the same paper.
    func replace(with item: PaperItem) {
        self.item = item
        refresh()
    }

    /// Shows or hides the session card, which floats only over the paper with the keyboard focus.
    func showsSessionCard(_ shown: Bool) {
        let sessions: Bool
        switch item {
        case .session, .newSession: sessions = true
        default: sessions = false
        }
        viewController.setOverlay(shown && !sessions ? AnyView(SessionOverlay(model: model)) : AnyView(EmptyView()))
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        delegate?.readerPaperDidBecomeKey(self)
    }

    func windowWillClose(_ notification: Notification) {
        delegate?.readerPaperWillClose(self)
    }

    // MARK: - Private

    private func refresh() {
        viewController.setContent(ReaderPaper(
            model: model, item: item,
            started: { [weak self] session in
                guard let self else { return }
                delegate?.readerPaper(self, didStart: session.id)
            },
            close: { [weak self] in self?.window?.performClose(nil) }
        ))
    }
}

/// The view of a reader paper: the content, and the session card in a
/// hosting view of its own over the bottom right corner. That view takes the
/// size of the pill or the card, so a click anywhere else reaches the content.
@MainActor
final class ReaderPaperViewController: NSViewController {

    // MARK: - Properties

    private var hostingView: NSHostingView<AnyView>?
    private var overlayView: NSHostingView<AnyView>?
    private let layout = PaperLayout()

    // MARK: - NSViewController

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        let hosting = NSHostingView(rootView: AnyView(Color.clear))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // The window sets its own size. The SwiftUI size would pin it to its content.
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

    func setContent(_ content: some View) {
        loadViewIfNeeded()
        hostingView?.rootView = AnyView(content.environment(layout))
    }

    func setOverlay(_ content: some View) {
        loadViewIfNeeded()
        overlayView?.rootView = AnyView(content.environment(layout))
    }
}

/// The width of a reader paper, which the session card and the tabs share.
@MainActor @Observable
final class PaperLayout {
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
