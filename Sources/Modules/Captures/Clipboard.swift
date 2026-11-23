import AppKit

/// Every text that Piper puts on the clipboard goes through `copy`.
public enum Clipboard {
    /// Writes the text with the marker that keeps it out of the clipboard tray.
    @discardableResult @MainActor
    public static func copy(_ text: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { return false }
        pasteboard.setData(Data(), forType: ClipboardInbox.copiedNoteType)
        return true
    }
}
