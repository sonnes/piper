import AppKit
import SwiftUI

/// A paper window: frameless, with round corners, and moved by its background.
///
/// The window has a title bar for its resize edges and Close Window, but the
/// bar is clear and its buttons are hidden. The window draws the shadow of
/// its paper itself, the card shadow of the September Write paper, so the
/// window is larger than its paper by `AppDefaults.Papers.shadowMargin`.
/// `paperFrame` is the frame of the paper. Escape calls `escape`.
final class PaperWindow: NSWindow {

    // MARK: - Properties

    var escape: () -> Void = {}
    /// Called when the window becomes key or stops being key.
    var focusChanged: (Bool) -> Void = { _ in }
    /// True while the window is the key window. A paper with the focus lies
    /// straight and has the deep shadow.
    private(set) var isFocused = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - Initialization

    init(paperSize: NSSize, minimumPaperSize: NSSize) {
        let margin = AppDefaults.Papers.shadowMargin
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

    // MARK: - API

    /// The frame of the paper, on the screen coordinates of AppKit.
    var paperFrame: NSRect { Self.paperFrame(of: frame) }

    func setPaperFrame(_ rect: NSRect, display: Bool, animate: Bool = false) {
        setFrame(Self.windowFrame(of: rect), display: display, animate: animate)
    }

    /// The frame of a window around a paper.
    nonisolated static func windowFrame(of paper: NSRect) -> NSRect {
        let margin = AppDefaults.Papers.shadowMargin
        return NSRect(x: paper.minX - margin.left, y: paper.minY - margin.bottom,
                      width: paper.width + margin.left + margin.right,
                      height: paper.height + margin.top + margin.bottom)
    }

    /// The frame of the paper in a window.
    nonisolated static func paperFrame(of window: NSRect) -> NSRect {
        let margin = AppDefaults.Papers.shadowMargin
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

    override func cancelOperation(_ sender: Any?) {
        escape()
    }

    // MARK: - Private

    private static func windowSize(_ paper: NSSize) -> NSSize {
        windowFrame(of: NSRect(origin: .zero, size: paper)).size
    }

    private func setFocused(_ focused: Bool) {
        guard focused != isFocused else { return }
        isFocused = focused
        focusChanged(focused)
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
        let metrics = AppDefaults.Papers.self
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
        let metrics = AppDefaults.Papers.self
        let shadow = focused ? metrics.focusShadow : metrics.restShadow
        return self
            .shadow(color: focused ? PiperTheme.paperEdgeShadow : .clear, radius: 0, y: metrics.edgeShadowY)
            .shadow(color: focused ? PiperTheme.paperShadow : PiperTheme.paperRestShadow, radius: shadow.radius, y: shadow.y)
    }
}
