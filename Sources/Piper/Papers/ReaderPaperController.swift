import AppKit
import SwiftUI
import WebKit

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
    private let viewController: ReaderPaperViewController
    private var shown = false
    private var closing = false
    private var keyMonitor: Any?

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: - Initialization

    /// Makes a paper with `frame` as the frame of its paper. `tilt` is the
    /// angle in degrees while the paper has no focus.
    init(item: PaperItem, model: AppModel, frame: NSRect, tilt: CGFloat) {
        self.item = item
        self.model = model
        viewController = ReaderPaperViewController(tilt: tilt)
        let window = PaperWindow(paperSize: frame.size, minimumPaperSize: AppDefaults.Papers.readerMinimumSize)
        window.title = "Paper"
        super.init(window: window)
        window.delegate = self
        window.escape = { [weak window] in window?.performClose(nil) }
        window.contentViewController = viewController
        window.setPaperFrame(frame, display: false)
        window.focusChanged = { [weak self, weak viewController] focused in
            viewController?.setFocused(focused)
            guard let self else { return }
            self.focusChanged(self, focused)
        }
        refresh()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let key = PaperKey(event), self.handle(key, in: event.window) else { return event }
            return nil
        }
        NotificationCenter.default.addObserver(self, selector: #selector(pageKey(_:)), name: .readerPageKey, object: window)
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
                window.setFrameOrigin(NSPoint(x: target.minX, y: target.minY - AppDefaults.Papers.rise))
                window.makeKeyAndOrderFront(nil)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = AppDefaults.Papers.fade
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

    /// Reads a key on the paper with the focus. Up Arrow and Down Arrow
    /// scroll an article. H highlights the selected text of an article and N
    /// adds a note to it. An article of a feed takes R, S, I, and B as its
    /// row on the list does. T tidies the desk.
    ///
    /// - Returns: True when the paper used the key.
    func handle(_ key: PaperKey, in eventWindow: NSWindow?) -> Bool {
        guard let window, PaperKey.focusedWindow === window, eventWindow == nil || eventWindow === window,
              !PaperKey.editsText(window) else { return false }
        // A reader page with the focus reads its own keys, and sends back the letters that it does not use.
        if let responder = window.firstResponder as? NSView, responder is WKWebView || responder.enclosingWebView != nil {
            return false
        }
        return perform(key, in: window)
    }

    @objc private func pageKey(_ notification: Notification) {
        guard let window, let name = notification.userInfo?["key"] as? String, let character = name.first,
              let key = PaperKey(keyCode: 0, characters: String(character), shift: false) else { return }
        _ = perform(key, in: window)
    }

    private func perform(_ key: PaperKey, in window: NSWindow) -> Bool {
        switch key {
        case .up, .down:
            return model.scrollReader(down: key == .down, in: window)
        case .letter("t"):
            tidy()
            return true
        case .letter("h"), .letter("n"):
            return model.sendReaderKey(key == .letter("h") ? "h" : "n", in: window)
        case .letter(let character):
            guard case .article(let id) = item, let article = model.feeds.article(id) else { return false }
            return model.articleKey(character, on: article)
        default:
            return false
        }
    }

    /// Stops reading keys, after the paper closes.
    func stopKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: - NSWindowDelegate

    /// The paper fades out before it closes.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !closing, !reduceMotion else { return true }
        closing = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = AppDefaults.Papers.fade
            sender.animator().alphaValue = 0
        }, completionHandler: { sender.close() })
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        delegate?.readerPaperDidBecomeKey(self)
    }

    func windowWillClose(_ notification: Notification) {
        stopKeys()
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
            overlay.heightAnchor.constraint(lessThanOrEqualTo: container.heightAnchor, multiplier: AppDefaults.SessionCard.paneFraction)
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
        sheet.layer?.cornerRadius = AppDefaults.Papers.cornerRadius
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
        let margin = AppDefaults.Papers.shadowMargin
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
        min(AppDefaults.SessionCard.width, max(0, width - 2 * AppDefaults.SessionCard.margin))
    }

    var stacksControls: Bool {
        width < AppDefaults.SessionCard.width + 2 * AppDefaults.SessionCard.margin + AppDefaults.SessionCard.tabsMinimumWidth
    }

    var cardBottomInset: CGFloat { stacksControls ? AppDefaults.TabIsland.clearance : 0 }
    var tabsTrailingInset: CGFloat { stacksControls ? 0 : AppDefaults.SessionCard.width + AppDefaults.SessionCard.margin }
}

private extension NSView {
    /// The web view that holds this view, if any.
    var enclosingWebView: WKWebView? {
        var view = superview
        while let current = view {
            if let web = current as? WKWebView { return web }
            view = current.superview
        }
        return nil
    }
}
