import AppKit
import SwiftUI

/// A floating panel that does not take focus from the application in front.
final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Moves the window when a drag starts on an empty part of the panel.
///
/// SwiftUI takes the mouse-down before `isMovableByWindowBackground` can
/// move a borderless panel, so this view starts the drag itself.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
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
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        panel.title = "Piper"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.minSize = AppDefaults.Window.capturePanelMinimumSize
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let corners = RoundedRectangle(cornerRadius: AppDefaults.Window.cornerRadius * scale, style: .continuous)
        let hosting = NSHostingView(rootView: CaptureView(model: model)
            .clipShape(corners)
            .overlay(corners.strokeBorder(PiperTheme.rule, lineWidth: 0.5)))
        // The panel sets its own size. The SwiftUI size would pin the panel
        // to the height of its content, and the reader could not resize it.
        hosting.sizingOptions = []
        panel.contentView = hosting

        // A saved frame keeps the size that the reader chose.
        if !panel.setFrameUsingName(NSWindow.FrameAutosaveName(AppDefaults.WindowName.capturePanel)),
           let screen = NSScreen.main {
            panel.setContentSize(size)
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - size.width - 30,
                                         y: screen.visibleFrame.midY - size.height / 2))
        }
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

    /// Closes an attached sheet, so that a modal alert can appear over the panel.
    func dismissAttachedSheet() {
        guard let window, let sheet = window.attachedSheet else { return }
        window.endSheet(sheet)
        sheet.orderOut(nil)
    }
}
