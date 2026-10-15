import AppKit
import ApplicationServices
import Carbon
import Captures
import PiperCore

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
    /// Reports what a capture saved.
    var didCapture: ((CaptureOutcome) -> Void)?
    /// The highlight that the toast shows, while the toast is on the screen. A
    /// second capture of the same text then asks for a note on it.
    var shownHighlight: (() -> (id: UUID, quote: String)?)?

    init(model: AppModel) { self.model = model }

    func start() {
        model.accessibilityEnabled = AXIsProcessTrusted()
        guard model.accessibilityEnabled else { stop(); return }
        guard monitoredShortcut != model.captureShortcut else { return }
        stop()
        monitoredShortcut = model.captureShortcut
        if model.captureShortcut == "Control-Option-Space" {
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
        let registered = RegisterEventHotKey(49, UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x50697072, id: 1), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey)
        if registered != noErr {
            model.store.report(PiperError("Control-Option-Space is unavailable. Choose Shift, Shift or release the shortcut in the other application."))
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
            didCapture?(.note(model.store.status, nil))
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
                    self.didCapture?(Self.save(selection, source: source, section: section,
                                               store: self.model.store, shown: self.shownHighlight?()))
                case .failure(let error):
                    self.model.store.status = error.localizedDescription
                    self.didCapture?(.note(error.localizedDescription, nil))
                }
            }
        }
    }

    /// Saves a selection. On a web page, the selection is a highlight under the
    /// article, and a capture with no selection saves the page to Reading.
    ///
    /// While the toast shows a highlight, a second capture on the page of that
    /// highlight asks for a note on it. The capture has no selection or the
    /// same text. A capture on another page saves as usual.
    static func save(_ selection: CapturedSelection, source: String, section: String,
                     store: CaptureStore, shown: (id: UUID, quote: String)?) -> CaptureOutcome {
        let quote = NoteAnchor.normalized(selection.text)
        if let shown, quote.isEmpty || quote == shown.quote,
           isOnPage(of: shown.id, selection.sourceURL, in: store) {
            return .comment(shown.id)
        }
        guard let url = selection.sourceURL.flatMap(URL.init(string:)) else {
            guard !quote.isEmpty else {
                store.status = "No readable selection. Copy the text, then choose Capture Clipboard."
                return .note(store.status, nil)
            }
            let saved = store.add(selection.text, source: source, sourceURL: nil, to: section, interpretSection: false)
            return .note(store.status, saved ? store.notes.last?.id : nil)
        }
        if let text = selection.pageText { store.savePageText(text, for: url) }
        if quote.isEmpty {
            let isNew = store.article(for: url) == nil
            guard let article = store.saveArticle(url, title: selection.title, source: source, to: section) else {
                return .note(store.status, nil)
            }
            if let minutes = selection.minutes { store.updateReading(article.id) { if $0.minutes == nil { $0.minutes = minutes } } }
            return .article(article.id, isNew: isNew)
        }
        guard let saved = store.saveHighlight(selection.text, in: url, title: selection.title, source: source, to: section,
                                              tags: [ReaderAssistant.highlightTag, ReaderAssistant.colors[0]]) else {
            return .note(store.status, nil)
        }
        if let minutes = selection.minutes { store.updateReading(saved.article.id) { if $0.minutes == nil { $0.minutes = minutes } } }
        return .highlight(article: saved.article.id, highlight: saved.highlight.id)
    }

    /// True when the link is the page of the article that holds the highlight.
    private static func isOnPage(of highlight: UUID, _ link: String?, in store: CaptureStore) -> Bool {
        guard let url = link.flatMap(URL.init(string:)),
              let parent = store.notes.first(where: { $0.id == highlight })?.parent,
              let page = store.notes.first(where: { $0.id == parent })?.articleURL else { return false }
        return CaptureLinks.canonical(url) == CaptureLinks.canonical(page)
    }

    /// Reads the selection of an application, and the web page that holds it.
    ///
    /// A web page needs no selection: the capture then saves the page. The
    /// text of the page comes along, for a page that Piper cannot load itself.
    nonisolated static func selection(pid: pid_t) -> Result<CapturedSelection, Error> {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.4)
        let element = axElement(attribute(kAXFocusedUIElementAttribute, on: app))
        if let element {
            AXUIElementSetMessagingTimeout(element, 0.4)
            guard attribute(kAXSubroleAttribute, on: element) as? String != kAXSecureTextFieldSubrole else {
                return .failure(PiperError("Secure text cannot be captured."))
            }
        }
        let text = element.flatMap(selectedText) ?? ""
        let window = axElement(attribute(kAXFocusedWindowAttribute, on: app))
        let area = webArea(from: element, in: window)
        let sourceURL = [element.flatMap { attribute(kAXDocumentAttribute, on: $0) }, area.flatMap { attribute("AXURL", on: $0) },
                         window.flatMap { attribute(kAXDocumentAttribute, on: $0) }]
            .compactMap { value -> String? in
                let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
                guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
                return url.absoluteString
            }.first
        guard sourceURL != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(PiperError(element == nil
                ? "Selection unavailable. Use Capture Clipboard."
                : "No readable selection. Copy the text, then choose Capture Clipboard."))
        }
        let title = window.flatMap { attribute(kAXTitleAttribute, on: $0) as? String }
        let page = sourceURL == nil ? nil : area.flatMap(pageText)
        return .success(CapturedSelection(text: text, sourceURL: sourceURL, title: title, pageText: page))
    }

    nonisolated private static func selectedText(of element: AXUIElement) -> String? {
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
        return text
    }

    /// The web area that holds the focus, or else the first web area in the window.
    nonisolated private static func webArea(from element: AXUIElement?, in window: AXUIElement?) -> AXUIElement? {
        var current = element
        for _ in 0..<60 {
            guard let node = current else { break }
            if attribute(kAXRoleAttribute, on: node) as? String == webAreaRole { return node }
            current = axElement(attribute(kAXParentAttribute, on: node))
        }
        guard let window else { return nil }
        var queue = [(window, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 400 {
            let (node, depth) = queue.removeFirst()
            visited += 1
            if attribute(kAXRoleAttribute, on: node) as? String == webAreaRole { return node }
            guard depth < 10, let children = attribute(kAXChildrenAttribute, on: node) as? [AXUIElement] else { continue }
            queue += children.map { ($0, depth + 1) }
        }
        return nil
    }

    /// The text of a whole web area, through the text markers of WebKit and Chromium.
    nonisolated private static func pageText(of area: AXUIElement) -> String? {
        AXUIElementSetMessagingTimeout(area, 1.5)
        var range: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(area, "AXTextMarkerRangeForUIElement" as CFString, area, &range) == .success,
              let range else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(area, "AXStringForTextMarkerRange" as CFString, range, &value) == .success,
              let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return String(text.prefix(pageTextLimit))
    }

    nonisolated private static let webAreaRole = "AXWebArea"
    /// The most page text that Piper keeps for one page.
    nonisolated private static let pageTextLimit = 400_000

    nonisolated private static func attribute(_ name: String, on element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    nonisolated private static func axElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
}

/// What one capture saved.
enum CaptureOutcome: Equatable {
    /// A plain note with its id, or a message and no id when nothing was saved.
    case note(String, UUID?)
    /// A highlight under the link capture of a web page.
    case highlight(article: UUID, highlight: UUID)
    /// A web page that the capture saved to Reading. A page that Reading
    /// already held is not new.
    case article(UUID, isNew: Bool)
    /// A second capture of the highlight on the toast: the reader wants to add a note.
    case comment(UUID)
}

struct CapturedSelection {
    let text: String
    let sourceURL: String?
    var title: String?
    /// The text of the whole web page, as the browser shows it.
    var pageText: String?

    /// The reading time of the page text.
    var minutes: Int? {
        guard let pageText else { return nil }
        let words = pageText.split(whereSeparator: \.isWhitespace).count
        return max(1, Int((Double(words) / AppDefaults.ArticleReader.wordsPerMinute).rounded()))
    }

    static func substring(_ text: String, range: CFRange) -> String? {
        let source = text as NSString
        guard range.location >= 0, range.length > 0,
              range.location <= source.length, range.length <= source.length - range.location else { return nil }
        return source.substring(with: NSRange(location: range.location, length: range.length))
    }
}
