import AppKit
import SwiftUI

/// The keys of the paper with the focus, in a strip at the bottom of the screen.
///
/// The strip is a panel that never takes the focus or a click. It shows while
/// a paper has the focus, so it leaves when Piper is not the active app.
@MainActor
final class HintStrip {

    private let panel: NSPanel
    private let paper: FeedPaperModel

    init(paper: FeedPaperModel) {
        self.paper = paper
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.hidesOnDeactivate = !QA.isOn
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: HintStripView(paper: paper, marks: paper.marks))
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    /// Shows the strip on a screen while a paper has the focus, or hides it.
    func update(on screen: NSScreen?) {
        let marks = paper.marks
        guard marks.feedFocused || marks.focusedPaper != nil, let screen else {
            panel.orderOut(nil)
            return
        }
        let metrics = AppDefaults.Papers.self
        let frame = screen.visibleFrame
        panel.setFrame(NSRect(x: frame.minX, y: frame.minY + metrics.hintBottom,
                              width: frame.width, height: metrics.hintHeight), display: true)
        panel.orderFrontRegardless()
    }
}

/// One key and what it does, such as "esc put back".
struct Hint: Equatable {
    let keys: [String]
    let label: String

    /// The hints of the paper with the focus.
    ///
    /// - Parameters:
    ///   - index: True while the feed paper shows the index of its tab.
    ///   - tree: True while the feed paper shows the folder tree.
    ///   - today: True while the feed paper shows Today, which takes the verb keys and the lens numbers.
    ///   - paper: The item of the reader paper with the focus, or nil for the feed paper.
    ///   - article: True when that paper shows an article, which takes H and N.
    ///   - papersOpen: True while a reader paper is open.
    ///   - tabs: The number of tabs in the column.
    static func hints(index: Bool, tree: Bool = false, today: Bool = false, paper: PaperItem?, article: Bool,
                      papersOpen: Bool, tabs: Int) -> [Hint] {
        let tabKeys = "⌘1–\(min(tabs, 9))"
        if let paper {
            var keep: [Hint] = []
            if case .article = paper { keep = [Hint(keys: ["K"], label: "keep")] }
            return keep + (article ? [Hint(keys: ["H"], label: "highlight"), Hint(keys: ["N"], label: "note")] : [])
                + [Hint(keys: ["⌘`"], label: "next paper"), Hint(keys: ["esc"], label: "put back"), Hint(keys: ["T"], label: "tidy")]
        }
        if tree {
            return [Hint(keys: ["↑", "↓"], label: "move"), Hint(keys: ["→"], label: "open folder"),
                    Hint(keys: ["←"], label: "close folder"), Hint(keys: ["↵"], label: "open file"),
                    Hint(keys: [tabKeys], label: "tab")]
                + (papersOpen ? [Hint(keys: ["⌘`"], label: "next paper")] : [])
        }
        if index {
            return [Hint(keys: ["↑", "↓"], label: "move"), Hint(keys: ["↵"], label: "pick"),
                    Hint(keys: [tabKeys], label: "tab"), Hint(keys: ["esc"], label: "back to the list")]
        }
        if today {
            return [Hint(keys: ["↑", "↓"], label: "move"), Hint(keys: ["↵"], label: "open as a paper"),
                    Hint(keys: ["K"], label: "keep"), Hint(keys: ["E"], label: "done"), Hint(keys: ["F"], label: "file"),
                    Hint(keys: ["S"], label: "send"), Hint(keys: ["1–4"], label: "lens"), Hint(keys: ["⌘N"], label: "write")]
                + (papersOpen ? [Hint(keys: ["⌘`"], label: "next paper")] : [])
        }
        return [Hint(keys: ["↑", "↓"], label: "move"), Hint(keys: ["↵"], label: "open as a paper"),
                Hint(keys: ["⌘N"], label: "write"), Hint(keys: [tabKeys], label: "tab"), Hint(keys: ["←"], label: "index")]
            + (papersOpen ? [Hint(keys: ["⌘`"], label: "next paper")] : [])
    }
}

private struct HintStripView: View {
    let paper: FeedPaperModel
    let marks: DeskMarks

    var body: some View {
        let focused = marks.focusedPaper
        let hints = Hint.hints(index: paper.showsIndex && focused == nil,
                               tree: paper.state.tab.isFolder && !paper.showsIndex && focused == nil,
                               today: paper.state.scope.showsCaptures && !paper.showsIndex, paper: focused,
                               article: focused.map { paper.model.isArticle($0) } ?? false,
                               papersOpen: !marks.open.isEmpty, tabs: paper.tabs.count)
        HStack(spacing: 20) {
            ForEach(hints, id: \.label) { hint in
                HStack(spacing: 7) {
                    ForEach(Array(hint.keys.enumerated()), id: \.offset) { index, key in
                        if index > 0 { Text("or").foregroundStyle(PiperTheme.paperFaint) }
                        KeyCap(text: key)
                    }
                    Text(hint.label)
                }
            }
        }
        .font(PiperTheme.paperUI(.body))
        .foregroundStyle(PiperTheme.paperMuted)
        .padding(.horizontal, 16).padding(.vertical, 6)
        // The strip lies on the desktop of the user, so it has a plate of paper under it.
        .background(PiperTheme.paper.opacity(0.92), in: Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keyboard shortcuts")
    }
}

extension AppModel {
    /// True when the paper of an item shows an article, which takes H and N.
    func isArticle(_ item: PaperItem) -> Bool {
        switch item {
        case .article: return true
        case .note(let id): return store.notes.first { $0.id == id }?.isArticle == true
        case .file, .session, .newSession: return false
        }
    }
}
