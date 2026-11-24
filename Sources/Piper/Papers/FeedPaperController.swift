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
    /// Called when the paper takes the keyboard focus or loses it.
    var focusChanged: () -> Void = {}
    /// Called with the frame of the paper after the reader moves or resizes it.
    var moved: (NSRect) -> Void = { _ in }
    /// The reader page of an article on the paper, while its Reader tab shows.
    var readerPage: WebPageBridge? {
        guard let page = attachedPage, page.view?.window === window else { return nil }
        return page
    }
    private weak var attachedPage: WebPageBridge?

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
        window.keys = { [weak self] in self?.keys ?? [] }
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
            .environment(\.attachReaderPage) { [weak self] in self?.attachedPage = $0 }
        let hosting = NSHostingView(rootView: view)
        // The window sets its own size. The SwiftUI size would pin it to its content.
        hosting.sizingOptions = []
        window.contentView = hosting
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - API

    func show() {
        window?.makeKeyAndOrderFront(nil)
        QA.activate()
        model.library.start()
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

    /// The keys of the feed paper. The index, the folder tree, and the list
    /// that shows each have their keys. Escape goes from the index back to
    /// the list before the list takes it. The tabs that the menus do not
    /// number take Command and their number.
    var keys: [PaperKey] {
        let paper = paper
        let index = { paper.showsIndex }
        let tree = { paper.state.tab.isFolder && !paper.showsIndex }
        let list = { !paper.showsIndex && !paper.state.tab.isFolder }
        return [
            PaperKey(key: .escape, title: "back to the list", isOn: index) { paper.showList() },
            PaperKey(key: .up, title: "move", isOn: index) { paper.moveIndexCursor(-1) },
            PaperKey(key: .down, title: "move", isOn: index) { paper.moveIndexCursor(1) },
            PaperKey(key: .enter, title: "pick", isOn: index) { paper.pickIndexCursor() },
            PaperKey(key: .right, title: "pick", isOn: index) { paper.pickIndexCursor() },
            PaperKey(key: .up, title: "move", isOn: tree) { paper.treeKey(.up) },
            PaperKey(key: .down, title: "move", isOn: tree) { paper.treeKey(.down) },
            PaperKey(key: .right, title: "open folder", isOn: tree) { paper.treeKey(.right) },
            PaperKey(key: .left, title: "close folder", isOn: tree) { paper.treeKey(.left) },
            PaperKey(key: .enter, title: "open file", isOn: tree) { paper.treeKey(.enter) }
        ] + paper.listKeys.map { $0.only(when: list) } + [
            PaperKey(key: .left, title: "index", isOn: { list() && paper.state.tab.hasIndex }) { paper.showIndex() },
            PaperKey(key: CommandKey("[", []), title: "scope") { paper.cycleScope(-1) },
            PaperKey(key: CommandKey("]", []), title: "scope") { paper.cycleScope(1) },
            .tidy { paper.tidy() }
        ] + tabKeys
    }

    /// Command and the number of a tab shows the tab, for each tab that no menu command numbers.
    private var tabKeys: [PaperKey] {
        let paper = paper
        let tabs = paper.tabs
        return tabs.compactMap { tab in
            guard let number = PaperTab.number(of: tab, in: tabs), number <= 9 else { return nil }
            let key = CommandKey(String(number))
            guard !Command.allCases.contains(where: { $0.key == key }) else { return nil }
            return PaperKey(key: key, title: "tab", inText: true) { paper.numberKey(number) }
        }
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
