import AppKit
import WebKit

/// Hooks that let a test drive Piper while another app stays in front.
///
/// The hooks are in debug builds only. They are on when Piper starts with
/// `-PiperQA YES`. Then Piper opens the main window at launch, never makes itself
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
@MainActor
final class QAScripts: NSObject {
    static let name = Notification.Name("com.piper.qa.eval")
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        super.init()
        // An inactive app holds distributed notifications unless the observer asks for each one at once.
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(received(_:)), name: Self.name, object: nil, suspensionBehavior: .deliverImmediately)
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
            let value = try await model.editorPage.webView.callAsyncJavaScript(script, contentWorld: .page)
            result = "ok\n\(value as? String ?? "null")"
        } catch {
            result = "error\n\(error.localizedDescription)"
        }
        try? result.write(toFile: resultPath, atomically: true, encoding: .utf8)
    }
}
#endif
