import AppKit
import SwiftUI
import WebKit

/// A paper window: frameless, with round corners, and moved by its background.
///
/// The window has a title bar for Close Window, but the bar is clear and its
/// buttons are hidden. The window draws the shadow of its paper itself, the
/// card shadow of the September Write paper, so the window is larger than its
/// paper by `PaperWindow.Metrics.shadowMargin`. `paperFrame` is the frame of
/// the paper. A band on each edge and corner of the paper resizes it, with
/// the resize pointers of macOS.
///
/// The window runs the keys of its paper from `keys`, after the views of the
/// responder chain pass a key on. A key with Command comes first to the
/// window, before the menus.
final class PaperWindow: NSWindow {

    // MARK: - Properties

    /// The key table of the paper. The controller of the window sets it.
    var keys: () -> [PaperKey] = { [] }
    /// Called when the window becomes key or stops being key.
    var focusChanged: (Bool) -> Void = { _ in }
    /// True while the window is the key window. A paper with the focus lies
    /// straight and has the deep shadow.
    private(set) var isFocused = false
    /// The frame of the paper before a zoom, which the next zoom restores.
    private var unzoomedFrame: NSRect?
    private let grips = PaperResizeView()

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - Initialization

    init(paperSize: NSSize, minimumPaperSize: NSSize) {
        let margin = PaperWindow.Metrics.shadowMargin
        super.init(contentRect: NSRect(origin: .zero, size: Self.windowSize(paperSize)),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        tabbingMode = .disallowed
        minSize = NSSize(width: minimumPaperSize.width + margin.left + margin.right,
                         height: minimumPaperSize.height + margin.top + margin.bottom)
    }

    override var contentView: NSView? {
        didSet { installGrips() }
    }

    // MARK: - API

    /// The frame of the paper, on the screen coordinates of AppKit.
    var paperFrame: NSRect { Self.paperFrame(of: frame) }

    func setPaperFrame(_ rect: NSRect, display: Bool, animate: Bool = false) {
        setFrame(Self.windowFrame(of: rect), display: display, animate: animate)
    }

    /// The window that has the keyboard focus. In QA mode no window is key,
    /// so the paper that has the focus stands in for it.
    @MainActor static var focusedWindow: NSWindow? {
        if let window = NSApp.keyWindow { return window }
        guard QA.isOn else { return nil }
        return NSApp.windows.first { ($0 as? PaperWindow)?.isFocused == true }
    }

    /// True while a text view, a web page, or a sheet has the keys. Then
    /// only the paper keys that work in text run.
    var editsText: Bool {
        if attachedSheet != nil || firstResponder is NSTextView { return true }
        guard let view = firstResponder as? NSView else { return false }
        return view is WKWebView || view.enclosingWebView != nil
    }

    /// Runs the paper key that matches `key` and is on, wherever the focus is.
    /// The reader page sends the letters that it does not use here.
    ///
    /// - Returns: True when a paper key ran.
    @discardableResult
    func perform(_ key: CommandKey) -> Bool {
        run { $0.key == key }
    }

    var minimumPaperSize: NSSize { Self.paperFrame(of: NSRect(origin: .zero, size: minSize)).size }

    /// Moves the paper back onto a screen, after a change of the displays.
    func keepOnScreen() {
        let screens = NSScreen.screens.map(\.visibleFrame)
        let frame = PaperPlacement.clamp(paperFrame, to: screens, minimum: minimumPaperSize)
        if frame != paperFrame { setPaperFrame(frame, display: true) }
    }

    /// A double click on the header: zoom, minimize, or nothing, as the
    /// setting of macOS for a double click on a title bar says.
    func titleBarDoubleClick() {
        switch TitleBarDoubleClick.current {
        case .zoom: zoom(nil)
        case .minimize: miniaturize(nil)
        case .none: break
        }
    }

    nonisolated static func windowFrame(of paper: NSRect) -> NSRect {
        let margin = PaperWindow.Metrics.shadowMargin
        return NSRect(x: paper.minX - margin.left, y: paper.minY - margin.bottom,
                      width: paper.width + margin.left + margin.right,
                      height: paper.height + margin.top + margin.bottom)
    }

    nonisolated static func paperFrame(of window: NSRect) -> NSRect {
        let margin = PaperWindow.Metrics.shadowMargin
        return NSRect(x: window.minX + margin.left, y: window.minY + margin.bottom,
                      width: window.width - margin.left - margin.right,
                      height: window.height - margin.top - margin.bottom)
    }

    // MARK: - NSWindow

    override func becomeKey() {
        super.becomeKey()
        setFocused(true)
    }

    override func resignKey() {
        super.resignKey()
        setFocused(false)
    }

    /// In QA mode Piper is never the active app, so no window becomes key.
    /// The paper that comes to the front takes the focus instead.
    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        guard QA.isOn else { return }
        for case let paper as PaperWindow in NSApp.windows where paper !== self { paper.setFocused(false) }
        setFocused(true)
    }

    override func keyDown(with event: NSEvent) {
        let text = editsText
        if !run(where: { $0.key.matches(event) && (!text || $0.inText) }) { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let text = editsText
        if event.modifierFlags.contains(.command), run(where: { $0.key.matches(event) && (!text || $0.inText) }) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        perform(.escape)
    }

    /// Fills the visible frame of the screen with the paper, or puts the
    /// paper back to its frame before the zoom.
    override func zoom(_ sender: Any?) {
        guard let screen = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let zoomed = PaperPlacement.zoomed(in: screen)
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if let unzoomedFrame, paperFrame == zoomed {
            self.unzoomedFrame = nil
            setPaperFrame(unzoomedFrame, display: true, animate: animate)
        } else {
            unzoomedFrame = paperFrame
            setPaperFrame(zoomed, display: true, animate: animate)
        }
    }

    // MARK: - Private

    private func run(where matches: (PaperKey) -> Bool) -> Bool {
        guard let key = keys().first(where: { matches($0) && $0.isOn() }) else { return false }
        key.run()
        return true
    }

    private static func windowSize(_ paper: NSSize) -> NSSize {
        windowFrame(of: NSRect(origin: .zero, size: paper)).size
    }

    private func setFocused(_ focused: Bool) {
        guard focused != isFocused else { return }
        isFocused = focused
        focusChanged(focused)
    }

    /// Puts the resize band over the content, in the frame view of the window.
    private func installGrips() {
        guard let frameView = contentView?.superview else { return }
        grips.removeFromSuperview()
        grips.frame = frameView.bounds
        grips.autoresizingMask = [.width, .height]
        frameView.addSubview(grips, positioned: .above, relativeTo: nil)
    }
}

private extension NSView {
    var enclosingWebView: WKWebView? {
        var view = superview
        while let current = view {
            if let web = current as? WKWebView { return web }
            view = current.superview
        }
        return nil
    }
}

// MARK: - Resize

/// The edges of a paper that a drag moves.
struct PaperEdges: OptionSet, Hashable {
    let rawValue: Int
    static let left = PaperEdges(rawValue: 1)
    static let right = PaperEdges(rawValue: 2)
    static let bottom = PaperEdges(rawValue: 4)
    static let top = PaperEdges(rawValue: 8)
}

/// The resize rules of a paper, apart from the window, so that tests can read them.
enum PaperResize {

    /// The edges under a point, or an empty set. The band of an edge lies
    /// `outside` points outside the paper and `inside` points inside it. A
    /// corner takes `corner` points along each of its edges.
    nonisolated static func edges(at point: NSPoint, paper: NSRect, outside: CGFloat = PaperWindow.Metrics.resizeOutside,
                                  inside: CGFloat = PaperWindow.Metrics.resizeInside,
                                  corner: CGFloat = PaperWindow.Metrics.resizeCorner) -> PaperEdges {
        let outer = paper.insetBy(dx: -outside, dy: -outside)
        guard outer.contains(point), !paper.insetBy(dx: inside, dy: inside).contains(point) else { return [] }
        var edges: PaperEdges = []
        if point.x < paper.minX + inside || (point.x < paper.minX + corner && nearY(point, paper, inside)) { edges.insert(.left) }
        if point.x > paper.maxX - inside || (point.x > paper.maxX - corner && nearY(point, paper, inside)) { edges.insert(.right) }
        if point.y < paper.minY + inside || (point.y < paper.minY + corner && nearX(point, paper, inside)) { edges.insert(.bottom) }
        if point.y > paper.maxY - inside || (point.y > paper.maxY - corner && nearX(point, paper, inside)) { edges.insert(.top) }
        return edges
    }

    /// The frame of a paper after a drag of `edges` by `delta`, on the
    /// coordinates of AppKit. The paper keeps `minimum` and stays inside `screen`.
    nonisolated static func frame(from start: NSRect, edges: PaperEdges, delta: CGSize, minimum: NSSize, screen: NSRect) -> NSRect {
        var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
        if edges.contains(.left) { minX = min(max(start.minX + delta.width, screen.minX), maxX - minimum.width) }
        if edges.contains(.right) { maxX = max(min(start.maxX + delta.width, screen.maxX), minX + minimum.width) }
        if edges.contains(.bottom) { minY = min(max(start.minY + delta.height, screen.minY), maxY - minimum.height) }
        if edges.contains(.top) { maxY = max(min(start.maxY + delta.height, screen.maxY), minY + minimum.height) }
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private nonisolated static func nearY(_ point: NSPoint, _ paper: NSRect, _ inside: CGFloat) -> Bool {
        point.y < paper.minY + inside || point.y > paper.maxY - inside
    }

    private nonisolated static func nearX(_ point: NSPoint, _ paper: NSRect, _ inside: CGFloat) -> Bool {
        point.x < paper.minX + inside || point.x > paper.maxX - inside
    }
}

/// The band around the edge of a paper that resizes it. The band takes
/// only the points near the edge, so a click inside the paper reaches the content.
final class PaperResizeView: NSView {

    private var drag: (start: NSPoint, frame: NSRect, edges: PaperEdges)?

    private var paper: NSRect {
        let margin = PaperWindow.Metrics.shadowMargin
        return NSRect(x: margin.left, y: margin.bottom,
                      width: bounds.width - margin.left - margin.right,
                      height: bounds.height - margin.top - margin.bottom)
    }

    /// Fills the band outside the paper with a color that the eye cannot see.
    /// The window server sends no click to a pixel that is fully clear.
    override func draw(_ dirtyRect: NSRect) {
        let outside = PaperWindow.Metrics.resizeOutside
        let band = NSBezierPath(rect: paper.insetBy(dx: -outside, dy: -outside))
        band.append(NSBezierPath(rect: paper))
        band.windingRule = .evenOdd
        PiperTheme.resizeBand.setFill()
        band.fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let local = convert(point, from: superview)
        return PaperResize.edges(at: local, paper: paper).isEmpty ? nil : self
    }

    override func resetCursorRects() {
        let paper = paper
        let outside = PaperWindow.Metrics.resizeOutside, inside = PaperWindow.Metrics.resizeInside
        let corner = PaperWindow.Metrics.resizeCorner, band = outside + inside
        let rects: [(NSRect, PaperEdges)] = [
            (NSRect(x: paper.minX - outside, y: paper.minY + corner, width: band, height: paper.height - 2 * corner), .left),
            (NSRect(x: paper.maxX - inside, y: paper.minY + corner, width: band, height: paper.height - 2 * corner), .right),
            (NSRect(x: paper.minX + corner, y: paper.minY - outside, width: paper.width - 2 * corner, height: band), .bottom),
            (NSRect(x: paper.minX + corner, y: paper.maxY - inside, width: paper.width - 2 * corner, height: band), .top),
            (NSRect(x: paper.minX - outside, y: paper.minY - outside, width: corner + outside, height: corner + outside), [.left, .bottom]),
            (NSRect(x: paper.maxX - corner, y: paper.minY - outside, width: corner + outside, height: corner + outside), [.right, .bottom]),
            (NSRect(x: paper.minX - outside, y: paper.maxY - corner, width: corner + outside, height: corner + outside), [.left, .top]),
            (NSRect(x: paper.maxX - corner, y: paper.maxY - corner, width: corner + outside, height: corner + outside), [.right, .top])
        ]
        for (rect, edges) in rects { addCursorRect(rect, cursor: Self.cursor(for: edges)) }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = window as? PaperWindow else { return }
        let edges = PaperResize.edges(at: convert(event.locationInWindow, from: nil), paper: paper)
        guard !edges.isEmpty else { return }
        drag = (NSEvent.mouseLocation, window.paperFrame, edges)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag, let window = window as? PaperWindow,
              let screen = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let now = NSEvent.mouseLocation
        let delta = CGSize(width: now.x - drag.start.x, height: now.y - drag.start.y)
        let frame = PaperResize.frame(from: drag.frame, edges: drag.edges, delta: delta,
                                      minimum: window.minimumPaperSize, screen: screen)
        window.setPaperFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard drag != nil else { return }
        drag = nil
        window?.invalidateCursorRects(for: self)
        if let window { window.delegate?.windowDidEndLiveResize?(Notification(name: NSWindow.didEndLiveResizeNotification, object: window)) }
    }

    /// The resize pointer of macOS for the edges.
    private static func cursor(for edges: PaperEdges) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch edges {
            case .left: position = .left
            case .right: position = .right
            case .top: position = .top
            case .bottom: position = .bottom
            case [.left, .top]: position = .topLeft
            case [.right, .top]: position = .topRight
            case [.left, .bottom]: position = .bottomLeft
            default: position = .bottomRight
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        return edges.contains(.left) || edges.contains(.right) ? .resizeLeftRight : .resizeUpDown
    }
}

/// The shadow of a paper, drawn by a layer behind the paper.
///
/// The focused paper has the deep card shadow of the September Write paper.
/// Another paper has a lighter shadow.
final class PaperShadowView: NSView {

    var focused = false {
        didSet { if focused != oldValue { needsDisplay = true } }
    }

    private let edge = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(edge)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        needsDisplay = true
    }

    override func updateLayer() {
        guard let layer else { return }
        let metrics = PaperWindow.Metrics.self
        let path = CGPath(roundedRect: bounds, cornerWidth: metrics.cornerRadius, cornerHeight: metrics.cornerRadius, transform: nil)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let shadow = focused ? metrics.focusShadow : metrics.restShadow
            layer.shadowPath = path
            layer.shadowColor = (focused ? PiperTheme.paperShadowNS : PiperTheme.paperRestShadowNS).cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = shadow.radius
            layer.shadowOffset = CGSize(width: 0, height: -shadow.y)
            edge.frame = bounds
            edge.shadowPath = path
            edge.shadowColor = PiperTheme.paperEdgeShadowNS.cgColor
            edge.shadowOpacity = focused ? 1 : 0
            edge.shadowRadius = 0
            edge.shadowOffset = CGSize(width: 0, height: -metrics.edgeShadowY)
        }
    }
}

extension View {
    /// The shadow of a paper sheet in SwiftUI, with the values of `PaperShadowView`.
    func paperShadow(focused: Bool) -> some View {
        let metrics = PaperWindow.Metrics.self
        let shadow = focused ? metrics.focusShadow : metrics.restShadow
        return self
            .shadow(color: focused ? PiperTheme.paperEdgeShadow : .clear, radius: 0, y: metrics.edgeShadowY)
            .shadow(color: focused ? PiperTheme.paperShadow : PiperTheme.paperRestShadow, radius: shadow.radius, y: shadow.y)
    }
}

/// Moves the window when a drag starts on an empty part of a paper.
///
/// SwiftUI takes the mouse-down before `isMovableByWindowBackground` can
/// move the window, so this view starts the drag itself. A double click
/// does what a double click on a title bar does.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2, let paper = window as? PaperWindow {
                paper.titleBarDoubleClick()
                return
            }
            window?.performDrag(with: event)
        }
    }
}

// MARK: - Metrics

extension PaperWindow {
    enum Metrics {
        /// The band around the edge of a paper that resizes it: its width
        /// outside the paper and inside it, and the length of a corner.
        static let resizeOutside: CGFloat = 6
        static let resizeInside: CGFloat = 3
        static let resizeCorner: CGFloat = 16
        static let cornerRadius: CGFloat = 20
        /// The space around a paper in its window, for the shadow of the paper.
        static let shadowMargin = NSEdgeInsets(top: 16, left: 24, bottom: 36, right: 24)
        static let shadowInsets = EdgeInsets(top: shadowMargin.top, leading: shadowMargin.left,
                                             bottom: shadowMargin.bottom, trailing: shadowMargin.right)
        /// The card shadow of the paper with the keyboard focus: `0 8px 24px` in the mock.
        static let focusShadow = (radius: CGFloat(12), y: CGFloat(8))
        /// The shadow of another paper: `0 3px 12px` in the mock.
        static let restShadow = (radius: CGFloat(6), y: CGFloat(3))
        /// The thin line under the focused paper: `0 1px 0` in the mock.
        static let edgeShadowY: CGFloat = 1
        /// The fade of a paper, and the cross-fade between the index and the list.
        static let fade: Double = 0.22
    }
}
