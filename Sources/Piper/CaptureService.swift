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

/// The keys that capture the selection of the app in front. Settings sets it.
enum CaptureShortcut: String, CaseIterable {
    case shiftShift = "Shift, Shift"
    case controlOptionSpace = "Control-Option-Space"

    /// Reads a stored value. Piper stored "Control-Option-C" before Control-Option-Space replaced it.
    init(stored: String?) {
        self = stored == "Control-Option-C" ? .controlOptionSpace : CaptureShortcut(rawValue: stored ?? "") ?? .shiftShift
    }

    /// The Carbon hotkey of Control-Option-Space.
    static let spaceKey = CommandKey(" ", [.control, .option])

    var glyph: String {
        switch self {
        case .shiftShift: return "⇧⇧"
        case .controlOptionSpace: return Self.spaceKey.glyph
        }
    }

    /// The name in a sentence, for example in an error message.
    var name: String {
        switch self {
        case .shiftShift: return "Shift twice"
        case .controlOptionSpace: return Self.spaceKey.name
        }
    }

    /// The title of the shortcut in Settings.
    var title: String {
        switch self {
        case .shiftShift: return "\(glyph) (\(name))"
        case .controlOptionSpace: return glyph
        }
    }
}

@MainActor
final class CaptureService {
    private var global: Any?
    private var local: Any?
    private lazy var hotkey = GlobalHotkey(keyCode: kVK_Space, modifiers: controlKey | optionKey) { [weak self] in self?.capture() }
    /// Checks the Accessibility access until Piper has it.
    private var accessibilityPoll: Timer?
    private var monitoredShortcut: CaptureShortcut?
    private var gesture = ShiftGesture()
    private let store: CaptureStore
    private let messages: Messages
    private let shortcut: () -> CaptureShortcut
    private let accessibilityChanged: (Bool) -> Void
    private let queue = DispatchQueue(label: "piper.capture")
    private var busy = false
    /// Reports what a capture saved.
    var didCapture: ((CaptureOutcome) -> Void)?
    /// The highlight that the toast shows, while the toast is on the screen. A
    /// second capture of the same text then asks for a note on it.
    var shownHighlight: (() -> (id: UUID, quote: String)?)?

    /// - Parameters:
    ///   - shortcut: The capture shortcut that Settings shows.
    ///   - accessibilityChanged: Takes the Accessibility access of Piper each time the service checks it.
    ///     Without access, the service checks it again every `accessibilityInterval` until Piper has it.
    init(store: CaptureStore, messages: Messages, shortcut: @escaping () -> CaptureShortcut, accessibilityChanged: @escaping (Bool) -> Void) {
        self.store = store
        self.messages = messages
        self.shortcut = shortcut
        self.accessibilityChanged = accessibilityChanged
    }

    /// The time between two checks of the Accessibility access.
    static let accessibilityInterval: TimeInterval = 4

    func start() {
        let trusted = AXIsProcessTrusted()
        accessibilityChanged(trusted)
        guard trusted else {
            stop()
            if accessibilityPoll == nil {
                accessibilityPoll = Timer.scheduledTimer(withTimeInterval: Self.accessibilityInterval, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.start() }
                }
            }
            return
        }
        accessibilityPoll?.invalidate()
        accessibilityPoll = nil
        let shortcut = shortcut()
        guard monitoredShortcut != shortcut else { return }
        stop()
        monitoredShortcut = shortcut
        if shortcut == .controlOptionSpace {
            if !hotkey.register() {
                messages.report(PiperError("\(CaptureShortcut.controlOptionSpace.name) is unavailable. Choose \(CaptureShortcut.shiftShift.name) or release the shortcut in the other application."))
            }
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
        hotkey.unregister()
        monitoredShortcut = nil
        gesture.cancel()
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.shift, .command, .control, .option])
        if event.type == .keyDown {
            gesture.cancel()
            return
        }
        guard shortcut() == .shiftShift, [56, 60].contains(event.keyCode) else { gesture.cancel(); return }
        if gesture.shift(down: flags.contains(.shift), time: event.timestamp, otherModifier: !flags.subtracting(.shift).isEmpty) { capture() }
    }

    func capture() {
        capture(trusted: AXIsProcessTrusted(), frontmost: NSWorkspace.shared.frontmostApplication)
    }

    /// Captures the selection of the application in front.
    ///
    /// - Parameters:
    ///   - trusted: True when Piper has Accessibility access.
    ///   - frontmost: The application in front. Piper itself has no selection to capture.
    func capture(trusted: Bool, frontmost: NSRunningApplication?) {
        guard !busy else { return }
        guard trusted else {
            accessibilityChanged(false)
            messages.show("Enable Accessibility in Settings")
            return
        }
        guard let app = frontmost, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            messages.show("Select text in another app first")
            return
        }
        busy = true
        let pid = app.processIdentifier
        let source = app.localizedName ?? app.bundleIdentifier ?? "Application"
        let section = store.activeSection
        queue.async { [weak self] in
            let result = Self.selection(pid: pid)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.busy = false
                do {
                    let outcome = try Self.save(result.get(), source: source, section: section,
                                                store: self.store, shown: self.shownHighlight?())
                    self.didCapture?(outcome)
                } catch {
                    self.messages.report(error)
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
                     store: CaptureStore, shown: (id: UUID, quote: String)?) throws -> CaptureOutcome {
        let quote = NoteAnchor.normalized(selection.text)
        if let shown, quote.isEmpty || quote == shown.quote,
           isOnPage(of: shown.id, selection.sourceURL, in: store) {
            return .comment(shown.id)
        }
        guard let url = selection.sourceURL.flatMap(URL.init(string:)) else {
            guard !quote.isEmpty else {
                throw PiperError("No readable selection. Copy the text, then choose Capture Clipboard.")
            }
            return .note(try store.add(selection.text, section: section, source: source))
        }
        if let text = selection.pageText { try store.savePageText(text, for: url) }
        if quote.isEmpty {
            let isNew = store.article(for: url) == nil
            let article = try store.saveArticle(url, title: selection.title, source: source, to: section)
            if let minutes = selection.minutes { try store.updateReading(article.id) { if $0.minutes == nil { $0.minutes = minutes } } }
            return .article(article.id, isNew: isNew)
        }
        let saved = try store.saveHighlight(selection.text, in: url, title: selection.title, source: source, to: section,
                                            tags: [NoteTag.highlight.rawValue, ReaderAssistant.colors[0]])
        if let minutes = selection.minutes { try store.updateReading(saved.article.id) { if $0.minutes == nil { $0.minutes = minutes } } }
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
                guard let url, url.isWeb else { return nil }
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
    /// A plain note.
    case note(Note)
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
        pageText.map { ReadingTime.minutes(words: ReadingTime.words(in: $0)) }
    }

    static func substring(_ text: String, range: CFRange) -> String? {
        let source = text as NSString
        guard range.location >= 0, range.length > 0,
              range.location <= source.length, range.length <= source.length - range.location else { return nil }
        return source.substring(with: NSRange(location: range.location, length: range.length))
    }
}
