import AppKit
import Agents
import Captures
import SwiftUI

/// Owns the feed paper, the open reader papers, and the detached session panel.
///
/// `open(_:)` is the one way to open a paper. The desk follows the open file
/// of `FileEditor`, so the "on the desk" mark and the file that the file
/// paper restores at launch name the file that shows.
///
/// A new reader paper opens to the right of the feed paper. Each next paper
/// moves down and to the right by `Metrics.cascade`. An item that
/// opens again brings its paper to the front. Only one file paper exists,
/// because the editor page is shared, so a second file replaces the first.
///
/// A paper that the reader moved or resized opens again in that frame, from
/// `PaperFrames`. The feed paper keeps its frame there too. After a change of
/// the displays, every paper moves back onto a screen.
@MainActor
final class PaperDesk {

    // MARK: - Properties

    let paper: FeedPaperModel
    private let model: AppModel
    private var feed: FeedPaperController?
    private var readers: [ReaderPaperController] = []
    private var sessionPanel: SessionPanelController?
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
        // The first scan opens the file that the file paper had open when Piper last quit.
        model.files.initialDocument = paper.state.selectedFile
        model.desk = self
        model.files.desk = self
        paper.tidy = { [weak self] in self?.tidy() }
        paper.marks.identity = { [weak model] item in model.map { item.identity(in: $0) } ?? item }
        model.sessionPresentationChanged = { [weak self] presentation in
            if presentation == .detached { self?.showSessionPanel() } else { self?.sessionPanel?.dismiss() }
        }
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
            let frame = Self.feedFrame(saved: frames.feedFrame, screens: NSScreen.screens.map(\.visibleFrame),
                                       main: NSScreen.main?.visibleFrame)
            let feed = FeedPaperController(model: model, paper: paper, desk: self, frame: frame)
            feed.focusChanged = { [weak self] in self?.updateHints() }
            feed.moved = { [weak self] frame in
                guard let self else { return }
                frames.setFeedFrame(frame)
                frames.save(to: defaults)
            }
            self.feed = feed
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
    /// A session goes to the detached panel while the reader keeps the
    /// session card there.
    func open(_ item: PaperItem) {
        if case .session(let id) = item {
            model.selectedSession = id
            if model.sessionPresentation == .detached { return showSessionPanel() }
        }
        if feed?.window?.isVisible != true { show() }
        let identity = item.identity(in: model)
        if let open = readers.first(where: { $0.item.identity(in: model) == identity }) {
            open.focus()
            return
        }
        let kind = Self.kind(of: item, model: model)
        let size = frames.lastSize(of: kind) ?? Self.size(of: kind)
        let screen = feed?.window?.screen ?? NSScreen.main
        let frame = Self.frame(of: identity, saved: frames, screens: NSScreen.screens.map(\.visibleFrame)) ??
            Self.frame(size: size, feed: feedPaperFrame,
                       screen: screen?.visibleFrame ?? NSRect(origin: .zero, size: size),
                       open: readers.compactMap(\.paperFrame))
        let tilts = Metrics.tilts
        let reader = ReaderPaperController(item: item, model: model, desk: self, frame: frame, tilt: tilts[opened % tilts.count])
        opened += 1
        reader.delegate = self
        reader.tidy = { [weak self] in self?.tidy() }
        reader.focusChanged = { [weak self] reader, focused in
            guard let self else { return }
            if focused {
                paper.marks.focusedPaper = reader.item
                model.actionTarget = actionTarget(for: reader.item)
                for other in readers { other.showsSessionCard(other === reader) }
            } else if paper.marks.focusedPaper == reader.item {
                paper.marks.focusedPaper = nil
            }
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
        model.files.openDocument(path)
        open(.file)
    }

    /// Keeps the open file of `FileEditor` for the "on the desk" mark and for the next launch.
    func fileChanged(to path: String?) {
        paper.state.selectedFile = path
        paper.marks.openFile = path
    }

    /// Puts the cursor in the capture field of Today.
    func newCapture() {
        show()
        paper.newCapture()
    }

    /// Shows the feed paper on the Feeds tab, with Sources.
    func showSources() {
        show()
        paper.showSources()
    }

    /// Shows Sources with the cursor in its address field.
    func addFeed() {
        show()
        paper.addFeed()
    }

    /// Opens the session card of the focused reader paper, or collapses it.
    /// With no reader paper focused, the newest one comes to the front with
    /// its card open. With no reader paper open, or with a detached card,
    /// the detached panel comes to the front.
    func toggleSessionCard() {
        if model.sessionPresentation == .detached { return showSessionPanel() }
        if let reader = readers.first(where: { $0.window?.isKeyWindow == true }) {
            model.sessionPresentation = model.sessionPresentation == .card ? .pill : .card
            reader.showsSessionCard(true)
            return
        }
        guard let reader = readers.last else { return showSessionPanel() }
        if feed?.window?.isVisible != true { show() }
        reader.focus()
        model.sessionPresentation = .card
    }

    /// Shows the detached session panel and gives it the keyboard.
    func showSessionPanel() {
        if sessionPanel == nil { sessionPanel = SessionPanelController(model: model) }
        sessionPanel?.present()
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

    /// Closes a sheet on the feed paper, so that a modal alert can appear.
    func dismissAttachedSheet() {
        guard let window = feed?.window, let sheet = window.attachedSheet else { return }
        window.endSheet(sheet)
        sheet.orderOut(nil)
    }

    // MARK: - Placement

    /// The frame of the feed paper: its saved frame moved onto a screen, or
    /// else its default size at the left of the main screen.
    nonisolated static func feedFrame(saved: NSRect?, screens: [NSRect], main: NSRect?) -> NSRect {
        let size = FeedPaperController.paperSize
        if let saved { return PaperPlacement.clamp(saved, to: screens, minimum: FeedPaperController.minimumPaperSize) }
        guard let main else { return NSRect(origin: .zero, size: size) }
        return NSRect(x: main.minX + Metrics.screenInset * 2, y: main.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// The frame of a new reader paper, on the screen coordinates of AppKit.
    ///
    /// The paper opens `gap` to the right of the feed paper, with its top at
    /// the top of the feed paper. Each paper that is already open moves the
    /// new paper by `cascade` to the right and down. After `cascadeSteps`
    /// papers, the cascade starts again. The paper stays `screenInset` inside the screen,
    /// and it shrinks to fit a small screen.
    nonisolated static func frame(index: Int, size: NSSize, feed: NSRect?, screen: NSRect) -> NSRect {
        let inset = Metrics.screenInset
        let step = CGFloat(index % Metrics.cascadeSteps) * Metrics.cascade
        let width = min(size.width, screen.width - 2 * inset)
        let height = min(size.height, screen.height - 2 * inset)
        let left = feed.map { $0.maxX + Metrics.gap } ?? screen.midX - width / 2
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
        for index in 0..<Metrics.cascadeSteps {
            let frame = frame(index: index, size: size, feed: feed, screen: screen)
            if !open.contains(where: { $0.minX == frame.minX && $0.maxY == frame.maxY }) { return frame }
        }
        return frame(index: open.count, size: size, feed: feed, screen: screen)
    }

    /// The saved frame of the paper of an item, moved onto a screen, or nil
    /// when the paper has no saved frame. A paper without one takes a place in the cascade.
    nonisolated static func frame(of item: PaperItem, saved: PaperFrames, screens: [NSRect]) -> NSRect? {
        guard let frame = saved.frame(of: item) else { return nil }
        return PaperPlacement.clamp(frame, to: screens, minimum: ReaderPaperController.Metrics.minimumSize)
    }

    /// The kind of a new paper for an item, which sets its size. An article and
    /// a file take the size of the Write paper. A short note and a session take less.
    static func kind(of item: PaperItem, model: AppModel) -> PaperKind {
        switch item {
        case .note, .article: return item.isArticle(in: model) ? .reader : .note
        case .file: return .reader
        case .session, .newSession: return .session
        }
    }

    /// The size of a new paper of a kind, before the reader resizes one.
    nonisolated static func size(of kind: PaperKind) -> NSSize {
        switch kind {
        case .reader: return Metrics.readerSize
        case .note: return Metrics.noteSize
        case .session: return Metrics.sessionSize
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
        frame.origin.x += PaperTabs.Metrics.tabVisible
        frame.size.width -= PaperTabs.Metrics.tabVisible
        return frame
    }

    /// What the session card takes as context for an item.
    private func actionTarget(for item: PaperItem) -> SkillTarget {
        switch item {
        case .note, .article:
            guard let note = item.note(in: model) else { return .folder }
            return .text(note.text, noteID: note.id)
        case .file:
            guard let document = model.files.currentDocument else { return .folder }
            return .page(model.library.vault.root.appendingPathComponent(document.relativePath).path)
        case .session, .newSession:
            return .folder
        }
    }
}

// MARK: - ReaderPaperControllerDelegate

extension PaperDesk {
    enum Metrics {
        static let readerSize = NSSize(width: 712, height: 860)
        static let noteSize = NSSize(width: 440, height: 420)
        static let sessionSize = NSSize(width: 480, height: 680)
        /// The tilts of the reader papers without the keyboard focus, in degrees, in the order the papers open.
        static let tilts: [CGFloat] = [-0.5, 0.45, -0.3, 0.6]
        /// The space between the feed paper and the first reader paper.
        static let gap: CGFloat = 24
        /// The offset of each next reader paper, to the right and down.
        static let cascade: CGFloat = 24
        /// The number of places in the cascade before it starts again.
        static let cascadeSteps = 6
        /// The space that a paper keeps from the edges of the screen.
        static let screenInset: CGFloat = 24
    }
}

extension PaperDesk: ReaderPaperControllerDelegate {

    func readerPaperWillClose(_ controller: ReaderPaperController) {
        readers.removeAll { $0 === controller }
        if paper.marks.focusedPaper == controller.item { paper.marks.focusedPaper = nil }
        updateHints()
        paper.marks.open.remove(controller.item)
        paper.marks.flash = DeskMarks.Flash(item: controller.item)
        // The editor page stays, so the last edit of the file still saves.
        if controller.item == .file { Task { await model.files.flushEditor() } }
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
        frames.set(frame, of: controller.item.identity(in: model), kind: Self.kind(of: controller.item, model: model))
        frames.save(to: defaults)
    }
}

extension EnvironmentValues {
    /// The desk, for the views of the papers that open a paper.
    @Entry var paperDesk: PaperDesk? = nil
}
