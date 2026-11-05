import Foundation

/// Compares the links of briefs.
public enum BriefLinks {

    /// True if the set from `BriefStore.linksBefore` holds this link.
    public static func isSeen(_ url: String, in seen: Set<String>) -> Bool {
        seen.contains(normalized(url))
    }

    /// Two forms of one link compare as equal: the fragment and a last slash do not count.
    public static func normalized(_ url: String) -> String {
        var value = url
        if let fragment = value.firstIndex(of: "#") { value = String(value[..<fragment]) }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }
}
