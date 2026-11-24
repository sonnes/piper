import AppKit
import Carbon

/// The system hotkey of Send Clipboard, which sends the clipboard to the default folder.
///
/// The hotkey is registered only while a folder has Claude skills, so the
/// keystroke stays free for other applications otherwise.
@MainActor
final class SendShortcut {

    // MARK: - Properties

    /// Reports a failed registration once.
    var failure: ((String) -> Void)?
    private let hotkey: GlobalHotkey
    private var failed = false

    // MARK: - Initialization

    init(action: @escaping () -> Void) {
        // Carbon names the key of Command.sendClipboard with its own codes.
        hotkey = GlobalHotkey(keyCode: kVK_ANSI_W, modifiers: controlKey | optionKey, action: action)
    }

    // MARK: - API

    func update(enabled: Bool) {
        guard enabled else { return hotkey.unregister() }
        guard !hotkey.isRegistered, !failed, !hotkey.register() else { return }
        failed = true
        failure?("\(Command.sendClipboard.key?.glyph ?? "") is unavailable, because another application holds it. Use Send Clipboard in the menu bar icon.")
    }

    func unregister() {
        hotkey.unregister()
    }
}
