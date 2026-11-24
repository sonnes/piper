import AppKit
import Feeds

/// A key of a paper: the key, what it does, when it works, and its action.
///
/// `FeedPaperController` and `ReaderPaperController` each give a table of
/// these keys to their `PaperWindow`. The window runs the first key of the
/// table that matches and is on. The hint strip shows the keys that are on.
struct PaperKey {
    let key: CommandKey
    /// What the key does, as the hint strip shows it.
    let title: String
    /// True for a key that also works while a text, a page, or a sheet has the focus.
    var inText = false
    var isOn: () -> Bool = { true }
    let run: () -> Void

    /// T puts each reader paper back in its place of the cascade, on every paper.
    static func tidy(_ run: @escaping () -> Void) -> PaperKey {
        PaperKey(key: CommandKey("t", []), title: "tidy", run: run)
    }

    /// K keeps an article and B opens it in the browser, on its row of a
    /// feed and on its paper.
    @MainActor static func articleKeys(actions: ArticleActions, article: @escaping () -> Article?) -> [PaperKey] {
        [
            PaperKey(key: CommandKey("k", []), title: "keep", isOn: { article() != nil }) {
                if let article = article() { actions.keep([article]) }
            },
            PaperKey(key: CommandKey("b", []), title: "open in browser", isOn: { article() != nil }) {
                if let article = article() { actions.openInBrowser(article) }
            }
        ]
    }

    /// The same key, on only while `condition` is also true.
    func only(when condition: @escaping () -> Bool) -> PaperKey {
        var key = self
        let isOn = self.isOn
        key.isOn = { condition() && isOn() }
        return key
    }
}

extension CommandKey {
    static let up = CommandKey("\u{F700}", [])
    static let down = CommandKey("\u{F701}", [])
    static let left = CommandKey("\u{F702}", [])
    static let right = CommandKey("\u{F703}", [])
    static let enter = CommandKey("\r", [])
    static let escape = CommandKey("\u{1B}", [])
    static let delete = CommandKey("\u{7F}", [])
    static let space = CommandKey(" ", [])

    var shifted: CommandKey { CommandKey(character, modifiers.union(.shift)) }
}

extension Array where Element: Equatable {
    /// The element that an arrow key moves to from `current`, by `delta`
    /// rows. The move stops at the first and the last element. With no
    /// current element, Down gives the first element and Up the last.
    func step(from current: Element?, by delta: Int) -> Element? {
        guard !isEmpty else { return nil }
        guard let current, let index = firstIndex(of: current) else { return delta > 0 ? first : last }
        return self[Swift.max(0, Swift.min(count - 1, index + delta))]
    }
}
