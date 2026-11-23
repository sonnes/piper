import AppKit
import SwiftUI

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
        let window = PaperWindow(paperSize: size, minimumPaperSize: minimum)
        window.title = "Piper"
        super.init(window: window)
        window.delegate = self
        window.escape = { [weak paper] in paper?.showList() }
        window.focusChanged = { [weak paper] focused in paper?.marks.feedFocused = focused }

        let hosting = NSHostingView(rootView: FeedPaperView(paper: paper, model: model, window: { [weak window] in window }))
        // The window sets its own size. The SwiftUI size would pin it to its content.
        hosting.sizingOptions = []
        window.contentView = hosting

        if let saved = paper.state.feedFrame, let screen = NSScreen.main,
           screen.visibleFrame.intersects(NSRectFromString(saved)) {
            window.setPaperFrame(NSRectFromString(saved), display: false)
        } else if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            window.setPaperFrame(NSRect(x: frame.minX + AppDefaults.Papers.screenInset * 2, y: frame.midY - size.height / 2,
                                        width: size.width, height: size.height), display: false)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(vaultChanged),
                                               name: .vaultPathDidChange, object: model)
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

    /// Saves the frame of the paper, with its column of tabs.
    private func saveFrame() {
        guard let frame = (window as? PaperWindow)?.paperFrame else { return }
        paper.state.feedFrame = NSStringFromRect(frame)
    }

    @objc private func vaultChanged() {
        paper.vaultChanged()
    }
}
