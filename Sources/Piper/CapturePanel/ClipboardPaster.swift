import AppKit
import ApplicationServices
import Carbon

/// Sends earlier clipboard text back into the application the reader came from.
///
/// The capture panel does not activate Piper, so that application stays in
/// front. A synthetic Command-V therefore arrives there.
@MainActor
enum ClipboardPaster {

    // MARK: - API

    /// Writes the text, then sends Command-V to the application in front.
    ///
    /// The return value is false when the text reached the clipboard but the
    /// paste did not happen. Piper in front and Accessibility off are the two
    /// reasons. The reader can then paste by hand.
    @discardableResult
    static func paste(_ text: String) -> Bool {
        guard write(text) else { return false }
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
        sendPasteKey()
        return true
    }

    /// Puts the text on the clipboard as plain text.
    @discardableResult
    static func write(_ text: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    // MARK: - Private

    /// Posts Command-V as a keyboard event.
    ///
    /// The suppression filter lets the keys through while the reader still
    /// holds the mouse button down on the card.
    private static func sendPasteKey() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}
