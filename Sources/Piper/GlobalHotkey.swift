import AppKit
import Carbon

/// A system hotkey: a key that runs an action while another app is in front.
///
/// Each hotkey gets its own id under the signature of Piper, so the handler
/// of one hotkey ignores the presses of another.
@MainActor
final class GlobalHotkey {

    // MARK: - Properties

    /// "Pipr", the signature of every hotkey of Piper.
    private static let signature: OSType = 0x50697072
    private static var lastID: UInt32 = 0

    var isRegistered: Bool { hotKey != nil }
    private let id: UInt32
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let action: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    // MARK: - Initialization

    init(key: CommandKey, action: @escaping () -> Void) {
        Self.lastID += 1
        id = Self.lastID
        let carbon = Self.carbon(key)
        keyCode = carbon.keyCode
        modifiers = carbon.modifiers
        self.action = action
    }

    // MARK: - API

    /// Registers the hotkey. False when another app holds the key. A second call does nothing.
    @discardableResult
    func register() -> Bool {
        guard hotKey == nil else { return true }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(context).takeUnretainedValue()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                  identifier.signature == GlobalHotkey.signature,
                  identifier.id == hotkey.id else { return OSStatus(eventNotHandledErr) }
            Task { @MainActor in hotkey.action() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return false }
        let registered = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                             GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey)
        guard registered == noErr else {
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    /// The Carbon key code and modifiers of a key. Carbon names a key by its
    /// place on the keyboard, not by its character.
    static func carbon(_ key: CommandKey) -> (keyCode: UInt32, modifiers: UInt32) {
        guard let code = keyCodes[key.character] else { preconditionFailure("No Carbon key code for \(key.name)") }
        let flags: [(NSEvent.ModifierFlags, Int)] = [(.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey)]
        let modifiers = flags.filter { key.modifiers.contains($0.0) }.reduce(0) { $0 | $1.1 }
        return (UInt32(code), UInt32(modifiers))
    }

    /// The keys of the global hotkeys of Piper.
    private static let keyCodes = [" ": kVK_Space, "w": kVK_ANSI_W]
}
