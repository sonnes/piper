import AppKit
import Feeds
import SwiftUI

/// What a reader paper reports to the desk.
@MainActor
protocol ReaderPaperControllerDelegate: AnyObject {
    func readerPaperWillClose(_ controller: ReaderPaperController)
    /// The first message of a new session started the session.
    func readerPaper(_ controller: ReaderPaperController, didStart session: UUID)
    /// The paper moved or changed its size.
    func readerPaperDidMove(_ controller: ReaderPaperController)
}

/// Owns one reader paper: a frameless window with round corners for one item.
///
/// The paper with the keyboard focus lies straight and has the deep shadow.
/// Another paper tilts by less than one degree, and its content fades. The
/// session card floats over the bottom right corner of the paper while the
/// paper has the keyboard focus.
@MainActor
final class ReaderPaperController: NSWindowController, NSWindowDelegate {

    // MARK: - Properties

    weak var delegate: ReaderPaperControllerDelegate?
    /// Puts the reader papers back in their cascade, after T. `PaperDesk` sets it.
    var tidy: () -> Void = {}
    /// Called when the paper takes the keyboard focus or loses it.
    var focusChanged: (ReaderPaperController, Bool) -> Void = { _, _ in }
    private(set) var item: PaperItem
    private let model: AppModel
    private weak var desk: PaperDesk?
    private let viewController: ReaderPaperViewController
    private var shown = false
    private var closing = false

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: - Initialization

    /// Makes a paper with `frame` as the frame of its paper. `tilt` is the
    /// angle in degrees while the paper has no focus.
    init(item: PaperItem, model: AppModel, desk: PaperDesk, frame: NSRect, tilt: CGFloat) {
        self.item = item
        self.model = model
        self.desk = desk
        viewController = ReaderPaperViewController(tilt: tilt)
        let window = PaperWindow(paperSize: frame.size, minimumPaperSize: Metrics.minimumSize)
        window.title = "Paper"
        super.init(window: window)
        window.delegate = self
        window.keys = { [weak self] in self?.keys ?? [] }
        window.contentViewController = viewController
        window.setPaperFrame(frame, display: false)
        window.focusChanged = { [weak self, weak viewController] focused in
            viewController?.setFocused(focused)
            guard let self else { return }
            self.focusChanged(self, focused)
        }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - API

    /// The frame of the paper, without the margin of its shadow.
    var paperFrame: NSRect? { (window as? PaperWindow)?.paperFrame }

    /// Shows the paper and gives it the keyboard. The first time, the paper
    /// fades in and rises into its place.
    func focus() {
        guard let window = window as? PaperWindow else { return }
        if !shown {
            shown = true
            if !reduceMotion {
                let target = window.frame
                window.alphaValue = 0
                window.setFrameOrigin(NSPoint(x: target.minX, y: target.minY - Metrics.rise))
                window.makeKeyAndOrderFront(nil)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = PaperWindow.Metrics.fade
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().alphaValue = 1
                    window.animator().setFrame(target, display: true)
                }
                QA.activate()
                return
            }
        }
        window.makeKeyAndOrderFront(nil)
        QA.activate()
    }

    /// Moves the paper to a place, as Tidy does.
    func move(to frame: NSRect) {
        (window as? PaperWindow)?.setPaperFrame(frame, display: true, animate: !reduceMotion)
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

    // MARK: - Keyboard

    /// The keys of the paper. The arrows scroll the Reader tab. H highlights
    /// the selected text and N adds a note to it. An article of a feed takes
    /// K and B as its row on the list does. While the reader page has the
    /// focus, the page reads its own keys and sends back the letters that it
    /// does not use.
    var keys: [PaperKey] {
        let reader = { [weak self] in self?.readerPage }
        let page = { reader() != nil }
        return [
            PaperKey(key: .up, title: "scroll", isOn: page) { reader()?.scroll(by: -1) },
            PaperKey(key: .down, title: "scroll", isOn: page) { reader()?.scroll(by: 1) },
            PaperKey(key: CommandKey("h", []), title: "highlight", isOn: page) { reader()?.send("h") },
            PaperKey(key: CommandKey("n", []), title: "note", isOn: page) { reader()?.send("n") }
        ] + PaperKey.articleKeys(actions: model.articleActions) { [weak self] in self?.article } + [
            PaperKey(key: .escape, title: "put back") { [weak self] in self?.window?.performClose(nil) },
            .tidy { [weak self] in self?.tidy() }
        ]
    }

    private var article: Article? {
        guard case .article(let id) = item else { return nil }
        return model.feeds.article(id)
    }

    /// The page of the Reader tab of the paper, while that tab shows.
    private var readerPage: ReaderPage? {
        model.readerPages.allObjects.first { $0.view?.window === window }.map(ReaderPage.init)
    }

    // MARK: - NSWindowDelegate

    /// The paper fades out before it closes.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !closing, !reduceMotion else { return true }
        closing = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = PaperWindow.Metrics.fade
            sender.animator().alphaValue = 0
        }, completionHandler: { sender.close() })
        return false
    }

    /// Edit > Undo on a paper goes to the undo stack of the app. A text view
    /// with its own undo manager handles Undo before the window does. The file
    /// paper keeps the undo manager of its window, because WebKit can record
    /// the edits of the editor page there.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        item == .file ? nil : model.undoManager
    }

    func windowDidMove(_ notification: Notification) { frameChanged() }
    func windowDidEndLiveResize(_ notification: Notification) { frameChanged() }

    /// Reports a new frame once the paper is in its place. The rise of a new
    /// paper and its fade on close do not count.
    private func frameChanged() {
        guard shown, !closing, window?.inLiveResize != true else { return }
        delegate?.readerPaperDidMove(self)
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
        ).environment(\.paperDesk, desk))
    }
}

/// The reader page of a paper, for the keys that the paper sends to it.
@MainActor
private struct ReaderPage {
    let bridge: WebPageBridge

    /// H highlights the selected text, and N highlights it and opens its note.
    func send(_ key: String) {
        bridge.call("key", key)
    }

    /// Scrolls the page by one arrow step, down for 1 and up for -1.
    func scroll(by steps: Int) {
        bridge.call("scroll", ArticleReader.Metrics.arrowScrollStep * CGFloat(steps))
    }
}

extension ReaderPaperController {
    enum Metrics {
        static let minimumSize = NSSize(width: 420, height: 320)
        /// A paper rises by this distance as it fades in.
        static let rise: CGFloat = 14
    }
}

/// The view of a reader paper: the shadow, the sheet with the content, and
/// the session card in a hosting view of its own over the bottom right
/// corner. That view takes the size of the pill or the card, so a click
/// anywhere else reaches the content.
@MainActor
final class ReaderPaperViewController: NSViewController {

    // MARK: - Properties

    private var hostingView: NSHostingView<AnyView>?
    private var overlayView: NSHostingView<AnyView>?
    private var paperView: PaperContainerView?
    private let layout = PaperLayout()
    private let tilt: CGFloat

    init(tilt: CGFloat) {
        self.tilt = tilt
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - NSViewController

    override func loadView() {
        let paper = PaperContainerView(tilt: tilt)
        let container = paper.sheet
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
            overlay.heightAnchor.constraint(lessThanOrEqualTo: container.heightAnchor, multiplier: SessionCard.Metrics.paneFraction)
        ])
        hostingView = hosting
        overlayView = overlay
        paperView = paper
        view = paper
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let width = paperView?.sheet.bounds.width ?? 0
        if layout.width != width { layout.width = width }
    }

    /// Straightens the paper and gives it the deep shadow, or tilts it and fades its content.
    func setFocused(_ focused: Bool) {
        layout.focused = focused
        paperView?.focused = focused
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

/// The paper of a reader paper window: a shadow and a sheet with round
/// corners, inside the margin of the shadow. The sheet tilts while the paper
/// has no focus.
final class PaperContainerView: NSView {

    let sheet = NSView()
    var focused = false {
        didSet {
            guard focused != oldValue else { return }
            shadowView.focused = focused
            needsLayout = true
        }
    }

    private let card = NSView()
    private let shadowView = PaperShadowView()
    private let tilt: CGFloat

    init(tilt: CGFloat) {
        self.tilt = tilt
        super.init(frame: .zero)
        wantsLayer = true
        card.wantsLayer = true
        sheet.wantsLayer = true
        sheet.layer?.cornerRadius = PaperWindow.Metrics.cornerRadius
        sheet.layer?.cornerCurve = .continuous
        sheet.layer?.masksToBounds = true
        for view in [shadowView, sheet] {
            view.autoresizingMask = [.width, .height]
            card.addSubview(view)
        }
        addSubview(card)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        let margin = PaperWindow.Metrics.shadowMargin
        card.frameCenterRotation = 0
        card.frame = NSRect(x: margin.left, y: margin.bottom,
                            width: max(0, bounds.width - margin.left - margin.right),
                            height: max(0, bounds.height - margin.top - margin.bottom))
        shadowView.frame = card.bounds
        sheet.frame = card.bounds
        card.frameCenterRotation = focused || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : tilt
    }
}

/// The width of a reader paper, which the session card and the tabs share,
/// and whether the paper has the keyboard focus.
@MainActor @Observable
final class PaperLayout {
    var width: CGFloat = 0
    var focused = true

    var cardWidth: CGFloat {
        min(SessionCard.Metrics.width, max(0, width - 2 * SessionCard.Metrics.margin))
    }

    var stacksControls: Bool {
        width < SessionCard.Metrics.width + 2 * SessionCard.Metrics.margin + SessionCard.Metrics.tabsMinimumWidth
    }

    var cardBottomInset: CGFloat { stacksControls ? TabIslandMetrics.clearance : 0 }
    var tabsTrailingInset: CGFloat { stacksControls ? 0 : SessionCard.Metrics.width + SessionCard.Metrics.margin }
}
