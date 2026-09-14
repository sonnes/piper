import AppKit
import SwiftUI

/// A floating panel that does not take focus from the application in front.
final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the capture panel window.
///
/// Each window has an `NSWindowController` that owns its window, its frame
/// autosave name, and its toolbar. `AppDelegate` holds no window code.
@MainActor
final class CapturePanelController: NSWindowController {

    // MARK: - Properties

    private let model: AppModel

    // MARK: - Initialization

    init(model: AppModel) {
        self.model = model
        // The panel is as tall as the screen allows, and it keeps its aspect.
        let available = (NSScreen.main?.visibleFrame.height ?? 964) - 32
        let scale = min(1, available / AppDefaults.Window.capturePanelSize.height)
        let size = NSSize(width: AppDefaults.Window.capturePanelSize.width * scale,
                          height: AppDefaults.Window.capturePanelSize.height * scale)
        let panel = CapturePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        panel.title = "Piper"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // The panel floats over whatever the reader is working in, so it draws
        // that through a vibrant material and rounds its corners the way the
        // system panels do.
        let material = NSVisualEffectView()
        material.material = .sidebar
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerCurve = .continuous
        material.layer?.masksToBounds = true
        material.maskImage = Self.roundedMask(radius: 22 * scale)

        let content = NSHostingView(rootView: PanelView(model: model))
        content.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            content.topAnchor.constraint(equalTo: material.topAnchor),
            content.bottomAnchor.constraint(equalTo: material.bottomAnchor)
        ])
        panel.contentView = material

        if !panel.setFrameUsingName(NSWindow.FrameAutosaveName(AppDefaults.WindowName.capturePanel)),
           let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - size.width - 30,
                                         y: screen.visibleFrame.midY - size.height / 2))
        }
        panel.setContentSize(size)
        panel.setFrameAutosaveName(NSWindow.FrameAutosaveName(AppDefaults.WindowName.capturePanel))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - API

    func show() {
        window?.makeKeyAndOrderFront(nil)
    }

    /// Takes the panel off the screen. The draft and the notes stay as they are.
    func hide() {
        window?.orderOut(nil)
    }

    /// A rounded rectangle that masks the material to the shape of the panel.
    ///
    /// `NSVisualEffectView` draws its blur outside a layer mask, so the corners
    /// stay square with `cornerRadius` alone. The cap insets let one small image
    /// stretch to any size the panel takes.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// Closes an attached sheet, so that a modal alert can appear over the panel.
    func dismissAttachedSheet() {
        guard let window, let sheet = window.attachedSheet else { return }
        window.endSheet(sheet)
        sheet.orderOut(nil)
    }
}
