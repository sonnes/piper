import Foundation

/// The lines of an Edit call, as removed, added, and unchanged lines.
public enum DiffText {

    public enum Line: Equatable, Sendable {
        case context(String)
        case removed(String)
        case added(String)
    }

    /// Keeps the lines that both texts start and end with, and marks the
    /// middle of each text as removed or added.
    public static func lines(old: String, new: String) -> [Line] {
        let before = old.components(separatedBy: "\n")
        let after = new.components(separatedBy: "\n")
        var prefix = 0
        while prefix < min(before.count, after.count), before[prefix] == after[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(before.count, after.count) - prefix,
              before[before.count - 1 - suffix] == after[after.count - 1 - suffix] { suffix += 1 }
        return before[..<prefix].map(Line.context)
            + before[prefix..<(before.count - suffix)].map(Line.removed)
            + after[prefix..<(after.count - suffix)].map(Line.added)
            + before[(before.count - suffix)...].map(Line.context)
    }
}
