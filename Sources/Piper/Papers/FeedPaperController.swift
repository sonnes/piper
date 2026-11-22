import AppKit
import SwiftUI

/// A paper window: frameless, with round corners, and moved by its background.
///
/// The window has a title bar for its shadow, its resize edges, and Close
/// Window, but the bar is clear and its buttons are hidden. Escape calls
/// `escape`.
final class PaperWindow: NSWindow {
    var escape: () -> Void = {}

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(size: NSSize, minimumSize: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        tabbingMode = .disallowed
        minSize = minimumSize
    }

    override func cancelOperation(_ sender: Any?) {
        escape()
    }
}

/// Owns the feed paper window.
///
/// The window holds the column of tabs and the paper. Its frame, its tab,
/// and its scope come back from `PaperDeskState`.
@MainActor
final class FeedPaperController: NSWindowController, NSWindowDelegate {

    // MARK: - Properties

    let paper: FeedPaperModel
    private let model: AppModel

    /// The width of the column of tabs beside the paper.
    static let tabColumn = AppDefaults.Papers.activeTabWidth - AppDefaults.Papers.tabOverlap

    // MARK: - Initialization

    init(model: AppModel, paper: FeedPaperModel) {
        self.model = model
        self.paper = paper
        let size = NSSize(width: AppDefaults.Papers.feedSize.width + Self.tabColumn, height: AppDefaults.Papers.feedSize.height)
        let minimum = NSSize(width: AppDefaults.Papers.feedMinimumSize.width + Self.tabColumn,
                             height: AppDefaults.Papers.feedMinimumSize.height)
        let window = PaperWindow(size: size, minimumSize: minimum)
        window.title = "Piper"
        super.init(window: window)
        window.delegate = self
        window.escape = { [weak paper] in paper?.showList() }

        let hosting = NSHostingView(rootView: FeedPaperView(paper: paper, model: model, window: { [weak window] in window }))
        // The window sets its own size. The SwiftUI size would pin it to its content.
        hosting.sizingOptions = []
        window.contentView = hosting

        if let saved = paper.state.feedFrame, let screen = NSScreen.main,
           screen.visibleFrame.intersects(NSRectFromString(saved)) {
            window.setFrame(NSRectFromString(saved), display: false)
        } else if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: frame.minX + AppDefaults.Papers.screenInset * 2,
                                          y: frame.midY - size.height / 2))
        }
        NotificationCenter.default.addObserver(self, selector: #selector(vaultChanged),
                                               name: .vaultPathDidChange, object: model)
        observeShape()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - API

    func show() {
        window?.makeKeyAndOrderFront(nil)
        QA.activate()
        model.reload()
    }

    /// Takes the paper off the screen. The list and the drafts stay as they are.
    func hide() {
        window?.orderOut(nil)
    }

    /// Closes a sheet, so that a modal alert can appear over the paper.
    func dismissAttachedSheet() {
        guard let window, let sheet = window.attachedSheet else { return }
        window.endSheet(sheet)
        sheet.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { saveFrame() }

    /// An article that the reader finished a week ago leaves Reading when the
    /// reader comes back to the paper.
    func windowDidBecomeKey(_ notification: Notification) {
        model.archiveFinishedReading()
    }

    // MARK: - Private

    private func saveFrame() {
        guard let frame = window?.frame else { return }
        paper.state.feedFrame = NSStringFromRect(frame)
    }

    @objc private func vaultChanged() {
        paper.vaultChanged()
    }

    /// The shadow follows the shape of the tabs, so it redraws when the tabs change.
    private func observeShape() {
        withObservationTracking {
            _ = paper.state.tab
            _ = paper.column
            _ = paper.showsIndex
        } onChange: { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + AppDefaults.Papers.fade) {
                self?.window?.invalidateShadow()
                self?.observeShape()
            }
        }
    }
}
