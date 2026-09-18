import Foundation

/// What the main window shows: the page on the screen, the text of a note, or
/// the folder alone. The Claude pane takes a page as context.
public enum SkillTarget: Equatable, Sendable {

    /// A file in the folder. The argument is its path.
    case page(String)
    /// The text of a note, or the address of a page. A note also carries its id,
    /// so the run shows in the row of that note.
    case text(String, noteID: UUID?)
    /// Nothing is chosen. Only a skill that takes no argument runs.
    case folder

    /// What Piper puts after the skill name.
    public var argument: String {
        switch self {
        case .page(let path): return path
        case .text(let text, _): return text
        case .folder: return ""
        }
    }

    /// The note that the run belongs to, when the target is one.
    public var noteID: UUID? {
        if case .text(_, let id) = self { return id }
        return nil
    }
}
