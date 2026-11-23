import AppKit
import SwiftUI

/// Owns the feed paper window.
///
/// The window holds the column of tabs and the paper. Its tab and its scope
/// come back from `PaperDeskState`. `PaperDesk` places the window and saves its frame.
@MainActor
final class FeedPaperController: NSWindowController, NSWindowDelegate {

    // MARK: - Properties

    let paper: FeedPaperModel
    private let model: AppModel
    private var keyMonitor: Any?
    /// Called when the paper takes the keyboard focus or loses it.
    var focusChanged: () -> Void = {}
    /// Called with the frame of the paper after the reader moves or resizes it.
    var moved: (NSRect) -> Void = { _ in }

    /// The size of a new paper, with its column of tabs.
    nonisolated static let paperSize = NSSize(width: Metrics.feedSize.width + PaperTabs.Metrics.tabVisible,
                                              height: Metrics.feedSize.height)
    nonisolated static let minimumPaperSize = NSSize(width: Metrics.feedMinimumSize.width + PaperTabs.Metrics.tabVisible,
                                                     height: Metrics.feedMinimumSize.height)

    // MARK: - Initialization

    /// Makes the feed paper with `frame` as the frame of its paper.
    init(model: AppModel, paper: FeedPaperModel, desk: PaperDesk, frame: NSRect) {
        self.model = model
        self.paper = paper
        let window = PaperWindow(paperSize: frame.size, minimumPaperSize: Self.minimumPaperSize)
        window.title = "Piper"
        super.init(window: window)
        window.setPaperFrame(frame, display: false)
        window.delegate = self
        window.escape = { [weak paper] in paper?.showList() }
        window.focusChanged = { [weak self, weak paper, weak model] focused in
            paper?.marks.feedFocused = focused
            // An article that the reader finished a week ago leaves Reading
            // when the reader comes back to the paper.
            if focused, let model {
                do { try model.store.archiveFinishedReading() } catch { model.messages.report(error) }
            }
            self?.focusChanged()
        }

        let view = FeedPaperView(paper: paper, model: model, window: { [weak window] in window })
            .environment(\.paperDesk, desk)
        let hosting = NSHostingView(rootView: view)
        // The window sets its own size. The SwiftUI size would pin it to its content.
        hosting.sizingOptions = []
        window.contentView = hosting
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if Command.matching(event) == nil, let number = PaperKey.tabNumber(event), self.handleTab(number, in: event.window) { return nil }
            guard let key = PaperKey(event), self.handle(key, in: event.window) else { return event }
            return nil
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - API

    func show() {
        window?.makeKeyAndOrderFront(nil)
        QA.activate()
        model.library.reload()
    }

    /// Takes the paper off the screen. The list and the drafts stay as they are.
    func hide() {
        window?.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    /// Edit > Undo on a paper goes to the undo stack of the app. A text view
    /// with its own undo manager handles Undo before the window does.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { model.undoManager }

    func windowDidMove(_ notification: Notification) { frameChanged() }
    func windowDidEndLiveResize(_ notification: Notification) { frameChanged() }

    // MARK: - Keyboard

    /// Command and a number shows a tab of the column, while the feed paper
    /// has the focus. The menu takes the numbers of Today and Feeds.
    func handleTab(_ number: Int, in eventWindow: NSWindow?) -> Bool {
        guard let window, PaperKey.focusedWindow === window, eventWindow === window else { return false }
        paper.numberKey(number)
        return true
    }

    /// Reads a key on the feed paper. Today reads its own arrows, Return,
    /// letters, and the numbers of its lenses. The folder tree reads the
    /// arrow keys and Return.
    ///
    /// - Returns: True when the paper used the key.
    func handle(_ key: PaperKey, in eventWindow: NSWindow?) -> Bool {
        guard let window, PaperKey.focusedWindow === window, eventWindow === window,
              !PaperKey.editsText(window) else { return false }
        if paper.state.tab.isFolder, !paper.showsIndex, handleTree(key) { return true }
        switch key {
        case .previousScope:
            paper.cycleScope(-1)
        case .nextScope:
            paper.cycleScope(1)
        case .letter("t"):
            paper.tidy()
        case .left where !paper.showsIndex:
            guard paper.state.tab.hasIndex else { return false }
            paper.showIndex()
        case .up where paper.showsIndex:
            paper.moveIndexCursor(-1)
        case .down where paper.showsIndex:
            paper.moveIndexCursor(1)
        case .enter where paper.showsIndex, .right where paper.showsIndex:
            paper.pickIndexCursor()
        case .up, .down, .enter:
            guard !paper.state.scope.showsCaptures, let keys = paper.listKeys else { return false }
            if key == .enter { keys.open() } else { keys.move(key == .down ? 1 : -1) }
        case .letter(let character):
            guard !paper.showsIndex, let keys = paper.listKeys else { return false }
            return keys.letter(character)
        default:
            return false
        }
        return true
    }

    private func handleTree(_ key: PaperKey) -> Bool {
        switch key {
        case .up: paper.treeKey(.up)
        case .down: paper.treeKey(.down)
        case .left: paper.treeKey(.left)
        case .right: paper.treeKey(.right)
        case .enter: paper.treeKey(.enter)
        default: return false
        }
        return true
    }

    // MARK: - Private

    /// Reports the frame of the paper, with its column of tabs.
    private func frameChanged() {
        guard let frame = (window as? PaperWindow)?.paperFrame else { return }
        moved(frame)
    }
}

extension FeedPaperController {
    /// The size of the feed paper, without its column of tabs.
    enum Metrics {
        static let feedSize = NSSize(width: 520, height: 760)
        static let feedMinimumSize = NSSize(width: 420, height: 560)
    }
}
