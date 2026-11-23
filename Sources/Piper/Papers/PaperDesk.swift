import AppKit
import Agents
import Captures

/// Owns the feed paper and the open reader papers.
///
/// A new reader paper opens to the right of the feed paper. Each next paper
/// moves down and to the right by `AppDefaults.Papers.cascade`. An item that
/// opens again brings its paper to the front. Only one file paper exists,
/// because the editor page is shared, so a second file replaces the first.
///
/// A paper that the reader moved or resized opens again in that frame, from
/// `PaperFrames`. After a change of the displays, every paper moves back
/// onto a screen.
@MainActor
final class PaperDesk {

    // MARK: - Properties

    let paper: FeedPaperModel
    private let model: AppModel
    private var feed: FeedPaperController?
    private var readers: [ReaderPaperController] = []
    /// The number of papers that opened, which picks the tilt of the next paper.
    private var opened = 0
    private var frames: PaperFrames
    private let defaults: UserDefaults
    private lazy var hints = HintStrip(paper: paper)

    // MARK: - Initialization

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        frames = PaperFrames.restore(from: defaults)
        paper = FeedPaperModel(model: model, defaults: defaults)
        paper.open = { [weak self] item in self?.open(item) }
        paper.tidy = { [weak self] in self?.tidy() }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepOnScreen() }
        }
    }

    // MARK: - API

    /// The window of the feed paper, once it exists.
    var feedWindow: NSWindow? { feed?.window }

    /// True while the feed paper or a reader paper is on the screen.
    var isVisible: Bool {
        feed?.window?.isVisible == true || readers.contains { $0.window?.isVisible == true }
    }

    /// Shows the feed paper, with the reader papers that are open.
    func show() {
        if feed == nil {
            feed = FeedPaperController(model: model, paper: paper)
            feed?.focusChanged = { [weak self] in self?.updateHints() }
        }
        for reader in readers { reader.window?.orderFront(nil) }
        feed?.show()
    }

    /// Takes every paper off the screen. The papers stay open.
    func hide() {
        feed?.hide()
        for reader in readers { reader.window?.orderOut(nil) }
        updateHints()
    }

    /// Opens an item as a reader paper, or brings its open paper to the front.
    func open(_ item: PaperItem) {
        if feed?.window?.isVisible != true { show() }
        if item == .file {
            paper.state.selectedFile = model.selectedDocument
            paper.marks.openFile = model.selectedDocument
        }
        if let open = readers.first(where: { $0.item == item }) {
            open.focus()
            return
        }
        let kind = Self.kind(of: item, model: model)
        let size = frames.lastSize(of: kind) ?? Self.size(of: kind)
        let screen = feed?.window?.screen ?? NSScreen.main
        let frame = Self.frame(of: item, saved: frames, screens: NSScreen.screens.map(\.visibleFrame)) ??
            Self.frame(size: size, feed: feedPaperFrame,
                       screen: screen?.visibleFrame ?? NSRect(origin: .zero, size: size),
                       open: readers.compactMap(\.paperFrame))
        let tilts = AppDefaults.Papers.tilts
        let reader = ReaderPaperController(item: item, model: model, frame: frame, tilt: tilts[opened % tilts.count])
        opened += 1
        reader.delegate = self
        reader.tidy = { [weak self] in self?.tidy() }
        reader.focusChanged = { [weak self] reader, focused in
            guard let self else { return }
            if focused { paper.marks.focusedPaper = reader.item }
            else if paper.marks.focusedPaper == reader.item { paper.marks.focusedPaper = nil }
            updateHints()
        }
        readers.append(reader)
        paper.marks.open.insert(item)
        reader.focus()
    }

    /// Puts each reader paper back in its place of the cascade, in the order the papers opened.
    func tidy() {
        let screen = (feed?.window?.screen ?? NSScreen.main)?.visibleFrame
        for (index, reader) in readers.enumerated() {
            guard let size = reader.paperFrame?.size, let screen else { continue }
            reader.move(to: Self.frame(index: index, size: size, feed: feedPaperFrame, screen: screen))
        }
    }

    /// Opens a file in the file paper.
    func openFile(_ path: String) {
        model.openDocument(path)
        open(.file)
    }

    /// Opens a capture. A link capture opens in the opening tab of its site.
    func openNote(_ id: UUID, asArticle: Bool = false) {
        guard let note = model.store.notes.first(where: { $0.id == id }) else { return }
        if asArticle { model.chooseArticleTab(model.openingTab(for: note), for: note) }
        open(.note(id))
    }

    /// Opens a session in a paper of its own.
    func openSession(_ id: UUID) {
        model.selectedSession = id
        open(.session(id))
    }

    /// Puts the cursor in the add field of the Inbox list.
    func newCapture() {
        show()
        paper.newCapture()
    }

    /// Shows the feed paper with Sources.
    func showSources() {
        show()
        paper.showSources()
    }

    /// Opens the session card of the focused reader paper, or collapses it.
    /// With no reader paper focused, the newest one comes to the front with
    /// its card open. Returns false when no reader paper is open.
    func toggleSessionCard() -> Bool {
        if let reader = readers.first(where: { $0.window?.isKeyWindow == true }) {
            model.sessionPresentation = model.sessionPresentation == .card ? .pill : .card
            reader.showsSessionCard(true)
            return true
        }
        guard let reader = readers.last else { return false }
        if feed?.window?.isVisible != true { show() }
        reader.focus()
        model.sessionPresentation = .card
        return true
    }

    /// Closes the reader paper with the keyboard focus. Returns false when no reader paper has it.
    @discardableResult func closeFocused() -> Bool {
        guard let reader = readers.first(where: { $0.window === PaperKey.focusedWindow }) else { return false }
        reader.window?.performClose(nil)
        return true
    }

    /// Gives the keyboard focus to the next paper: the feed paper, then the
    /// reader papers in the order they opened.
    func cycle() {
        let windows = ([feed?.window] + readers.map(\.window)).compactMap { $0 }.filter(\.isVisible)
        guard !windows.isEmpty else { return show() }
        let current = windows.firstIndex { $0 === PaperKey.focusedWindow } ?? -1
        windows[(current + 1) % windows.count].makeKeyAndOrderFront(nil)
        QA.activate()
    }

    /// Closes a sheet on any paper, so that a modal alert can appear.
    func dismissAttachedSheet() {
        feed?.dismissAttachedSheet()
    }

    // MARK: - Placement

    /// The frame of a new reader paper, on the screen coordinates of AppKit.
    ///
    /// The paper opens `gap` to the right of the feed paper, with its top at
    /// the top of the feed paper. Each paper that is already open moves the
    /// new paper by `cascade` to the right and down. After `cascadeSteps`
    /// papers, the cascade starts again. The paper stays `screenInset` inside the screen,
    /// and it shrinks to fit a small screen.
    nonisolated static func frame(index: Int, size: NSSize, feed: NSRect?, screen: NSRect) -> NSRect {
        let inset = AppDefaults.Papers.screenInset
        let step = CGFloat(index % AppDefaults.Papers.cascadeSteps) * AppDefaults.Papers.cascade
        let width = min(size.width, screen.width - 2 * inset)
        let height = min(size.height, screen.height - 2 * inset)
        let left = feed.map { $0.maxX + AppDefaults.Papers.gap } ?? screen.midX - width / 2
        let top = feed?.maxY ?? screen.maxY - inset
        var x = min(left + step, screen.maxX - inset - width)
        x = max(x, screen.minX + inset)
        var y = min(top - step, screen.maxY - inset) - height
        y = max(y, screen.minY + inset)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// The frame of a new reader paper in the first free place of the cascade.
    ///
    /// A place is free when no open paper has its top left corner there. When
    /// every place is taken, the paper takes the place after the open papers.
    nonisolated static func frame(size: NSSize, feed: NSRect?, screen: NSRect, open: [NSRect]) -> NSRect {
        for index in 0..<AppDefaults.Papers.cascadeSteps {
            let frame = frame(index: index, size: size, feed: feed, screen: screen)
            if !open.contains(where: { $0.minX == frame.minX && $0.maxY == frame.maxY }) { return frame }
        }
        return frame(index: open.count, size: size, feed: feed, screen: screen)
    }

    /// The saved frame of the paper of an item, moved onto a screen, or nil
    /// when the paper has no saved frame. A paper without one takes a place in the cascade.
    nonisolated static func frame(of item: PaperItem, saved: PaperFrames, screens: [NSRect]) -> NSRect? {
        guard let frame = saved.frame(of: item) else { return nil }
        return PaperPlacement.clamp(frame, to: screens, minimum: AppDefaults.Papers.readerMinimumSize)
    }

    /// The size of a new paper for an item. An article and a file take the
    /// size of the Write paper. A short note and a session take less.
    static func kind(of item: PaperItem, model: AppModel) -> PaperKind {
        switch item {
        case .note(let id):
            let note = model.store.notes.first { $0.id == id }
            return note?.isArticle == true ? .reader : .note
        case .article, .file:
            return .reader
        case .session, .newSession:
            return .session
        }
    }

    /// The size of a new paper of a kind, before the reader resizes one.
    nonisolated static func size(of kind: PaperKind) -> NSSize {
        switch kind {
        case .reader: return AppDefaults.Papers.readerSize
        case .note: return AppDefaults.Papers.noteSize
        case .session: return AppDefaults.Papers.sessionSize
        }
    }

    /// Moves every paper back onto a screen, after a change of the displays.
    private func keepOnScreen() {
        (feed?.window as? PaperWindow)?.keepOnScreen()
        for reader in readers { (reader.window as? PaperWindow)?.keepOnScreen() }
    }

    /// Shows the strip of keys while a paper has the focus. A paper that
    /// loses the focus to another paper hands it over at once, so the strip
    /// waits for the next turn of the run loop.
    private func updateHints() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            hints.update(on: (PaperKey.focusedWindow ?? feed?.window)?.screen)
        }
    }

    /// The frame of the paper of the feed paper, without its column of tabs.
    private var feedPaperFrame: NSRect? {
        guard let window = feed?.window as? PaperWindow, window.isVisible else { return nil }
        var frame = window.paperFrame
        frame.origin.x += FeedPaperController.tabColumn
        frame.size.width -= FeedPaperController.tabColumn
        return frame
    }

    /// What the session card takes as context for an item.
    private func actionTarget(for item: PaperItem) -> SkillTarget {
        switch item {
        case .note(let id):
            guard let note = model.store.notes.first(where: { $0.id == id }) else { return .folder }
            return .text(note.text, noteID: note.id)
        case .article(let id):
            guard let article = model.feeds.article(id), let url = URL(string: article.url),
                  let note = model.store.article(for: url) else { return .folder }
            return .text(note.text, noteID: note.id)
        case .file:
            guard let document = model.currentDocument else { return .folder }
            return .page(model.vault.root.appendingPathComponent(document.relativePath).path)
        case .session, .newSession:
            return .folder
        }
    }
}

// MARK: - ReaderPaperControllerDelegate

extension PaperDesk: ReaderPaperControllerDelegate {

    func readerPaperDidBecomeKey(_ controller: ReaderPaperController) {
        model.actionTarget = actionTarget(for: controller.item)
        for reader in readers { reader.showsSessionCard(reader === controller) }
    }

    func readerPaperWillClose(_ controller: ReaderPaperController) {
        readers.removeAll { $0 === controller }
        if paper.marks.focusedPaper == controller.item { paper.marks.focusedPaper = nil }
        updateHints()
        paper.marks.open.remove(controller.item)
        paper.marks.flash = DeskMarks.Flash(item: controller.item)
        // The editor page stays, so the last edit of the file still saves.
        if controller.item == .file { Task { await model.flushEditor() } }
        guard feed?.window?.isVisible == true else { return }
        (readers.last?.window ?? feed?.window)?.makeKeyAndOrderFront(nil)
    }

    func readerPaper(_ controller: ReaderPaperController, didStart session: UUID) {
        model.selectedSession = session
        paper.marks.open.remove(controller.item)
        paper.marks.open.insert(.session(session))
        controller.replace(with: .session(session))
    }

    func readerPaperDidMove(_ controller: ReaderPaperController) {
        guard let frame = controller.paperFrame else { return }
        frames.set(frame, of: controller.item, kind: Self.kind(of: controller.item, model: model))
        frames.save(to: defaults)
    }
}
