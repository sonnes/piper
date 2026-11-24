import AppKit
import WebKit

/// Hooks that let a test drive Piper while another app stays in front.
///
/// The hooks are in debug builds only. They are on when Piper starts with
/// `-PiperQA YES`. Then Piper opens the feed paper at launch, never makes itself
/// the active app, and runs the scripts that `QAScripts` receives.
@MainActor
enum QA {
    static var isOn: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: AppDefaults.Key.qaMode)
        #else
        false
        #endif
    }

    /// Makes Piper the active app. In QA mode, the app that the user works in stays active.
    static func activate() {
        if !isOn { NSApp.activate(ignoringOtherApps: true) }
    }
}

#if DEBUG
/// Runs JavaScript in the editor page for a test.
///
/// A test posts the distributed notification `com.piper.qa.eval` with the body
/// of an async function as its object. Piper writes the JSON of the return value
/// to the file that `-PiperQAResult` names. The first line of the file is `ok`
/// or `error`. macOS sends keys only to the active app, so a test inserts text
/// with this hook, for example with `document.execCommand("insertText")`.
///
/// The notification `com.piper.qa.do` runs one command on the papers, for a
/// test that cannot send keys or clicks:
///
/// - `key <name>`: a key on the paper with the focus, such as `key down`,
///   `key enter`, `key esc`, `key left`, `key 3`, `key ]`, or `key t`.
/// - `capture`: shows Today with the cursor in the capture field, as New
///   Capture does.
/// - `focus feed` or `focus <n>`: gives the focus to the feed paper or to
///   reader paper `n`, from 0.
/// - `open note <text>`, `open article <title>`, `open file <path>`: opens an
///   item whose text or title starts with the words.
/// - `reader <script>`: runs JavaScript in the reader page of the paper with the focus.
/// - `appearance light`, `appearance dark`, or `appearance system`: sets the appearance of Piper.
/// - `shot <path>`: draws the feed paper window into a PNG file on the desk
///   color of the mock. It works while the screen is locked, when a capture
///   of the screen fails.
@MainActor
final class QAScripts: NSObject {
    static let name = Notification.Name("com.piper.qa.eval")
    static let command = Notification.Name("com.piper.qa.do")
    private let model: AppModel
    private let desk: PaperDesk

    init(model: AppModel, desk: PaperDesk) {
        self.model = model
        self.desk = desk
        super.init()
        // An inactive app holds distributed notifications unless the observer asks for each one at once.
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(received(_:)), name: Self.name, object: nil, suspensionBehavior: .deliverImmediately)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(command(_:)), name: Self.command, object: nil, suspensionBehavior: .deliverImmediately)
    }

    @objc private func command(_ notification: Notification) {
        guard let line = notification.object as? String else { return }
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        guard let verb = parts.first else { return }
        let rest = parts.count > 1 ? parts[1] : ""
        var result = "ok"
        switch verb {
        case "key": result = key(rest)
        case "capture": desk.newCapture()
        case "focus": result = focus(rest)
        case "open": result = open(rest)
        case "appearance":
            NSApp.appearance = rest == "dark" ? NSAppearance(named: .darkAqua) : rest == "light" ? NSAppearance(named: .aqua) : nil
        case "shot": result = shot(rest)
        case "reader":
            guard let window = PaperWindow.focusedWindow,
                  let page = model.readerPages.allObjects.first(where: { $0.view?.window === window })?.view else {
                result = "error\nNo reader page has the focus."
                break
            }
            Task {
                let value = try? await page.callAsyncJavaScript("return JSON.stringify(await (async () => {\n\(rest)\n})()) ?? \"null\"",
                                                                contentWorld: .page)
                write("ok\n\(value as? String ?? "null")")
            }
            return
        default: result = "error\nUnknown command \(verb)."
        }
        write(result)
    }

    private func write(_ result: String) {
        guard let path = UserDefaults.standard.string(forKey: AppDefaults.Key.qaResultPath) else { return }
        try? result.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Sends a key to the paper with the focus, as if the reader pressed it.
    /// The name is up, down, left, right, enter, space, esc, or a letter.
    private func key(_ name: String) -> String {
        guard let window = PaperWindow.focusedWindow else { return "error\nNo paper has the focus." }
        let named: [String: CommandKey] = [
            "up": .up, "down": .down, "left": .left, "right": .right, "enter": .enter, "space": .space, "esc": .escape
        ]
        let key = named[name] ?? CommandKey(name, [])
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, characters: key.character,
                                           charactersIgnoringModifiers: key.character, isARepeat: false, keyCode: 0) else {
            return "error\nNo event."
        }
        window.sendEvent(event)
        return "ok"
    }

    /// Draws the feed paper window on the color of the desk.
    private func shot(_ path: String) -> String {
        guard let view = desk.feedWindow?.contentView,
              let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return "error\nNo feed paper." }
        view.wantsLayer = true
        let background = view.layer?.backgroundColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = PiperTheme.deskNS.cgColor
        }
        view.cacheDisplay(in: view.bounds, to: image)
        view.layer?.backgroundColor = background
        guard let png = image.representation(using: .png, properties: [:]),
              (try? png.write(to: URL(fileURLWithPath: path))) != nil else { return "error\nNo image." }
        return "ok"
    }

    private func focus(_ target: String) -> String {
        let papers = NSApp.windows.compactMap { $0 as? PaperWindow }.filter(\.isVisible)
        if target == "feed" {
            desk.feedWindow?.makeKeyAndOrderFront(nil)
            return "ok"
        }
        let readers = papers.filter { $0 !== desk.feedWindow }.sorted { $0.windowNumber < $1.windowNumber }
        guard let index = Int(target), readers.indices.contains(index) else { return "error\nNo paper \(target)." }
        readers[index].makeKeyAndOrderFront(nil)
        return "ok"
    }

    private func open(_ request: String) -> String {
        let parts = request.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return "error\nopen needs a kind and words." }
        let words = parts[1]
        switch parts[0] {
        case "note":
            guard let note = model.store.notes.first(where: { $0.text.hasPrefix(words) || $0.reading?.title?.hasPrefix(words) == true }) else {
                return "error\nNo note starts with \(words)."
            }
            desk.open(.note(note.id))
        case "article":
            guard let article = model.feeds.articles(.allUnread).first(where: { $0.title.hasPrefix(words) }) else {
                return "error\nNo article starts with \(words)."
            }
            desk.open(.article(article.id))
        case "file":
            desk.openFile(words)
        default:
            return "error\nUnknown kind \(parts[0])."
        }
        return "ok"
    }

    @objc private func received(_ notification: Notification) {
        guard let body = notification.object as? String,
              let path = UserDefaults.standard.string(forKey: AppDefaults.Key.qaResultPath) else { return }
        Task { await run(body, resultPath: path) }
    }

    private func run(_ body: String, resultPath: String) async {
        let script = "return JSON.stringify(await (async () => {\n\(body)\n})()) ?? \"null\""
        let result: String
        do {
            let value = try await model.files.editorPage.webView.callAsyncJavaScript(script, contentWorld: .page)
            result = "ok\n\(value as? String ?? "null")"
        } catch {
            result = "error\n\(error.localizedDescription)"
        }
        try? result.write(toFile: resultPath, atomically: true, encoding: .utf8)
    }
}
#endif
