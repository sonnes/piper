import AppKit
import SwiftUI

/// The keys of the paper with the focus, in a strip at the bottom of the
/// screen: the key table of its window, then New Capture on the feed paper
/// and Next Paper while a reader paper is open.
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
        let hosting = NSHostingView(rootView: HintStripView(marks: paper.marks))
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
        let metrics = Metrics.self
        let frame = screen.visibleFrame
        panel.setFrame(NSRect(x: frame.minX, y: frame.minY + metrics.hintBottom,
                              width: frame.width, height: metrics.hintHeight), display: true)
        panel.orderFrontRegardless()
    }
}

extension HintStrip {
    enum Metrics {
        static let hintBottom: CGFloat = 18
        static let hintHeight: CGFloat = 40
        /// The side margin of the foot of a list over the strip.
        static let footMargin: CGFloat = 20
        /// The space between two hints, and between the keys and the label of one hint.
        static let hintSpacing: CGFloat = 20
        static let keySpacing: CGFloat = 7
        static let stripPadding = EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        /// The plate of paper under the strip.
        static let plate = PiperTheme.paper.opacity(0.92)
    }
}

/// One key and what it does, such as "esc put back".
struct Hint: Equatable {
    let keys: [String]
    let label: String

    /// The hints of a key table: one hint for each title of the keys that
    /// are on, in the order of the table. A run of number keys shows as a
    /// range, such as "1–4".
    @MainActor static func hints(_ table: [PaperKey]) -> [Hint] {
        var titles: [String] = []
        var glyphs: [String: [String]] = [:]
        for key in table where key.isOn() {
            if glyphs[key.title] == nil { titles.append(key.title) }
            if glyphs[key.title, default: []].contains(key.key.glyph) { continue }
            glyphs[key.title, default: []].append(key.key.glyph)
        }
        return titles.map { Hint(keys: range(glyphs[$0] ?? []), label: $0) }
    }

    /// The hint of an app command, such as "⌘` next paper".
    static func hint(_ command: Command) -> Hint {
        Hint(keys: [command.key?.glyph ?? ""], label: command.title.lowercased())
    }

    /// Three or more keys that differ only in a last digit that counts up, as one range.
    private static func range(_ glyphs: [String]) -> [String] {
        guard glyphs.count > 2, let first = glyphs.first, let last = glyphs.last,
              let start = first.last?.wholeNumberValue, let end = last.last?.wholeNumberValue else { return glyphs }
        let prefix = first.dropLast()
        let counted = glyphs.enumerated().allSatisfy { offset, glyph in
            glyph.dropLast() == prefix && glyph.last?.wholeNumberValue == start + offset
        }
        return counted ? ["\(first)–\(end)"] : glyphs
    }
}

private struct HintStripView: View {
    let marks: DeskMarks
    private typealias Metrics = HintStrip.Metrics

    var body: some View {
        let feed = marks.feedFocused && marks.focusedPaper == nil
        let table = (PaperWindow.focusedWindow as? PaperWindow)?.keys() ?? []
        let commands: [Command] = (feed ? [.newCapture] : []) + (marks.open.isEmpty ? [] : [.nextPaper])
        let hints = Hint.hints(table) + commands.map(Hint.hint)
        HStack(spacing: Metrics.hintSpacing) {
            ForEach(hints, id: \.label) { hint in
                HStack(spacing: Metrics.keySpacing) {
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
        .padding(Metrics.stripPadding)
        // The strip lies on the desktop of the user, so it has a plate of paper under it.
        .background(Metrics.plate, in: Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keyboard shortcuts")
    }
}
