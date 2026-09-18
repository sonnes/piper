import AppKit
import Carbon

/// Control-Option-W, a system hotkey that sends the clipboard to the default folder.
///
/// The hotkey is registered only while a folder has Claude skills, so the
/// keystroke stays free for other applications otherwise.
@MainActor
final class SendShortcut {

    // MARK: - Properties

    static let signature: OSType = 0x50697072
    static let identifier: UInt32 = 2
    static let glyphs = "⌃⌥W"

    var action: (() -> Void)?
    /// Reports a failed registration once.
    var failure: ((String) -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var failed = false

    // MARK: - API

    func update(enabled: Bool) {
        if enabled {
            if hotKey == nil && !failed { register() }
        } else {
            unregister()
        }
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    // MARK: - Private

    private func register() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                  identifier.signature == SendShortcut.signature,
                  identifier.id == SendShortcut.identifier else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<SendShortcut>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in shortcut.action?() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { fail(); return }
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_W), UInt32(controlKey | optionKey),
                                             EventHotKeyID(signature: Self.signature, id: Self.identifier),
                                             GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey)
        if registered != noErr {
            unregister()
            fail()
        }
    }

    private func fail() {
        failed = true
        failure?("\(Self.glyphs) is unavailable, because another application holds it. Use Send Clipboard in the menu bar icon.")
    }
}
