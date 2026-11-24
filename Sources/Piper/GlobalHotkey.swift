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

    /// - Parameters:
    ///   - keyCode: The Carbon code of the key, such as `kVK_Space`.
    ///   - modifiers: The Carbon modifiers, such as `controlKey | optionKey`.
    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        Self.lastID += 1
        id = Self.lastID
        self.keyCode = UInt32(keyCode)
        self.modifiers = UInt32(modifiers)
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
}
