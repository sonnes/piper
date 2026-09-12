import AppKit
import ApplicationServices
import Carbon

struct ShiftGesture {
    var pressTime: TimeInterval?
    var previousRelease: TimeInterval?
    var threshold: TimeInterval = 0.35

    mutating func cancel() { pressTime = nil; previousRelease = nil }

    mutating func shift(down: Bool, time: TimeInterval, otherModifier: Bool) -> Bool {
        if otherModifier { cancel(); return false }
        if down {
            if pressTime != nil { cancel(); return false }
            pressTime = time
            return false
        }
        guard let pressTime, time - pressTime < threshold else { cancel(); return false }
        self.pressTime = nil
        if let previousRelease, time - previousRelease < threshold {
            self.previousRelease = nil
            return true
        }
        previousRelease = time
        return false
    }
}

@MainActor
final class CaptureService {
    private var global: Any?
    private var local: Any?
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var monitoredShortcut: String?
    private var gesture = ShiftGesture()
    private let model: AppModel
    private let queue = DispatchQueue(label: "piper.capture")
    private var busy = false
    var didCapture: ((String) -> Void)?

    init(model: AppModel) { self.model = model }

    func start() {
        model.accessibilityEnabled = AXIsProcessTrusted()
        guard model.accessibilityEnabled else { stop(); return }
        guard monitoredShortcut != model.captureShortcut else { return }
        stop()
        monitoredShortcut = model.captureShortcut
        if model.captureShortcut == "Control-Option-C" {
            registerHotKey()
            return
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event)
        }
        local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.gesture.cancel()
            return event
        }
    }

    func stop() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil
        local = nil
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        hotKey = nil
        hotKeyHandler = nil
        monitoredShortcut = nil
        gesture.cancel()
    }

    private func registerHotKey() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                  identifier.signature == 0x50697072, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
            let service = Unmanaged<CaptureService>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in service.capture() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        guard installed == noErr else {
            model.store.report(PiperError("Cannot register the capture shortcut. Choose Shift, Shift in Settings."))
            return
        }
        let registered = RegisterEventHotKey(8, UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x50697072, id: 1), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey)
        if registered != noErr {
            model.store.report(PiperError("Control-Option-C is unavailable. Choose Shift, Shift or release the shortcut in the other application."))
        }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.shift, .command, .control, .option])
        if event.type == .keyDown {
            gesture.cancel()
            return
        }
        guard model.captureShortcut == "Shift, Shift", [56, 60].contains(event.keyCode) else { gesture.cancel(); return }
        if gesture.shift(down: flags.contains(.shift), time: event.timestamp, otherModifier: !flags.subtracting(.shift).isEmpty) { capture() }
    }

    func capture() {
        guard !busy else { return }
        guard AXIsProcessTrusted() else {
            model.accessibilityEnabled = false
            model.store.status = "Enable Accessibility in Settings"
            didCapture?(model.store.status)
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            model.store.status = "Select text in another app first"
            return
        }
        busy = true
        let pid = app.processIdentifier
        let source = app.localizedName ?? app.bundleIdentifier ?? "Application"
        let section = model.store.activeSection
        queue.async { [weak self] in
            let result = Self.selection(pid: pid)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.busy = false
                switch result {
                case .success(let selection):
                    _ = self.model.store.add(selection.text, source: source, sourceURL: selection.sourceURL, to: section, interpretSection: false)
                    self.didCapture?(self.model.store.status)
                case .failure(let error):
                    self.model.store.status = error.localizedDescription
                    self.didCapture?(error.localizedDescription)
                }
            }
        }
    }

    nonisolated static func selection(pid: pid_t) -> Result<CapturedSelection, Error> {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.4)
        guard let element = axElement(attribute(kAXFocusedUIElementAttribute, on: app)) else {
            return .failure(PiperError("Selection unavailable. Use Capture Clipboard."))
        }
        AXUIElementSetMessagingTimeout(element, 0.4)
        guard attribute(kAXSubroleAttribute, on: element) as? String != kAXSecureTextFieldSubrole else {
            return .failure(PiperError("Secure text cannot be captured."))
        }
        var text = attribute(kAXSelectedTextAttribute, on: element) as? String
        if text?.isEmpty != false,
           let value = attribute(kAXSelectedTextRangeAttribute, on: element), CFGetTypeID(value) == AXValueGetTypeID() {
            let axRange = unsafeBitCast(value, to: AXValue.self)
            var range = CFRange()
            if AXValueGetType(axRange) == .cfRange, AXValueGetValue(axRange, .cfRange, &range), range.length > 0 {
                var selected: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, value, &selected) == .success {
                    text = selected as? String
                } else if let fullText = attribute(kAXValueAttribute, on: element) as? String {
                    text = CapturedSelection.substring(fullText, range: range)
                }
            }
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(PiperError("No readable selection. Copy the text, then choose Capture Clipboard."))
        }
        let window = axElement(attribute(kAXFocusedWindowAttribute, on: app))
        let sourceURL = [attribute(kAXDocumentAttribute, on: element), window.flatMap { attribute(kAXDocumentAttribute, on: $0) }]
            .compactMap { value -> String? in
                let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
                guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
                return url.absoluteString
            }.first
        return .success(CapturedSelection(text: text, sourceURL: sourceURL))
    }

    nonisolated private static func attribute(_ name: String, on element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    nonisolated private static func axElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
}

struct CapturedSelection {
    let text: String
    let sourceURL: String?

    static func substring(_ text: String, range: CFRange) -> String? {
        let source = text as NSString
        guard range.location >= 0, range.length > 0,
              range.location <= source.length, range.length <= source.length - range.location else { return nil }
        return source.substring(with: NSRange(location: range.location, length: range.length))
    }
}
