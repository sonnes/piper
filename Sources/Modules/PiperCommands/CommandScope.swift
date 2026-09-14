import Foundation

/// Where a command or a skill comes from.
///
/// `claude` reads both folders when it starts in the Wiki folder, so Piper
/// lists both. A row from the Wiki folder shows no tag, because that is the
/// common case and the tag would be noise on every line.
public enum CommandScope: String, CaseIterable, Hashable, Sendable {
    /// `.claude` inside the Wiki folder.
    case wiki
    /// `.claude` inside the home folder.
    case personal

    // MARK: - Properties

    /// The text a suggestion row shows beside the title. Empty for the Wiki scope.
    public var tag: String {
        switch self {
        case .wiki: return ""
        case .personal: return "personal"
        }
    }

    // MARK: - Functions

    /// The `.claude` directory of this scope.
    ///
    /// - Parameters:
    ///   - wikiRoot: The Wiki folder.
    ///   - homeRoot: The home folder. Tests give a temporary folder here.
    public func claudeDirectory(
        wikiRoot: URL,
        homeRoot: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        switch self {
        case .wiki: return wikiRoot.appendingPathComponent(".claude")
        case .personal: return homeRoot.appendingPathComponent(".claude")
        }
    }
}
