import AppKit
import SwiftUI

/// Owns the detached session panel: the session card in a panel of its own,
/// over every app and on every Space.
///
/// The panel does not activate Piper, so the app under it stays in front.
/// Its close button collapses the card to the pill in the main window, and
/// Dock in the card returns the card to the main window.
@MainActor
final class SessionPanelController: NSWindowController {

    // MARK: - Properties

    private let model: AppModel

    // MARK: - Initialization

    init(model: AppModel) {
        self.model = model
        let panel = CapturePanel(
            contentRect: NSRect(origin: .zero, size: AppDefaults.SessionCard.panelSize),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Session"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = AppDefaults.SessionCard.panelMinimumSize
        panel.contentView = NSHostingView(rootView: SessionCard(model: model, detached: true).environment(DetailPaneLayout()))
        super.init(window: panel)
        panel.delegate = self
        if !panel.setFrameUsingName(NSWindow.FrameAutosaveName(AppDefaults.WindowName.sessionPanel)) {
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                let inset = AppDefaults.SessionCard.panelScreenInset
                panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - inset, y: frame.maxY - panel.frame.height - inset))
            }
        }
        panel.setFrameAutosaveName(NSWindow.FrameAutosaveName(AppDefaults.WindowName.sessionPanel))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - API

    /// Shows the panel and gives it the keyboard.
    func present() {
        window?.orderFrontRegardless()
        window?.makeKey()
    }

    /// Takes the panel off the screen without a change of the presentation.
    func dismiss() {
        window?.orderOut(nil)
    }
}

// MARK: - NSWindowDelegate

extension SessionPanelController: NSWindowDelegate {

    func windowWillClose(_ notification: Notification) {
        if model.sessionPresentation == .detached { model.sessionPresentation = .pill }
    }
}
