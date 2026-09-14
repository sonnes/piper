import Foundation

/// One application action that the search bar can offer.
///
/// The parser holds no user interface code, so the caller supplies the actions
/// and the closure that each one runs.
public struct CommandAction: Identifiable {
    public let title: String
    /// The second line of the row.
    public let detail: String
    /// The keyboard equivalent, such as `⌘1`. Empty when the action has none.
    public let shortcut: String
    public let run: () -> Void

    public var id: String { title }

    // MARK: - Life Cycle

    public init(title: String, detail: String = "", shortcut: String = "", run: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.shortcut = shortcut
        self.run = run
    }
}
