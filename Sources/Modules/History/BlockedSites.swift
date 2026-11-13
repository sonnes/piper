import Foundation

/// The sites that Discover never reads.
public enum BlockedSites {

    public static let defaults = [
        "mail.google.com", "docs.google.com", "drive.google.com", "sheets.google.com", "slides.google.com",
        "outlook.live.com", "outlook.office.com",
        "accounts.google.com", "login.microsoftonline.com",
        "chase.com", "paypal.com"
    ]

    /// Takes a list that the user typed, with one host or URL on each line.
    public static func normalized(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        return lines.compactMap { line in
            let value = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard !value.isEmpty, !value.hasPrefix("#") else { return nil }
            let bare = value.hasPrefix("*.") ? String(value.dropFirst(2)) : value
            guard let host = host(of: bare), seen.insert(host).inserted else { return nil }
            return host
        }
    }

    /// True for an http or https URL whose host the list does not block.
    public static func allows(_ url: String, list: [String]) -> Bool {
        guard let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""),
              let host = parsed.host else { return false }
        return !isBlocked(host, list: list)
    }

    /// Matches at a domain boundary, so a block also covers each subdomain.
    public static func isBlocked(_ value: String, list: [String]) -> Bool {
        guard let host = host(of: value) else { return true }
        if isPrivate(host) { return true }
        return list.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Loopback and private addresses, and names that only a local network resolves.
    public static func isPrivate(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 {
            let (a, b) = (parts[0], parts[1])
            return a == 0 || a == 10 || a == 127 || (a == 100 && (64...127).contains(b)) || (a == 169 && b == 254)
                || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168)
        }
        if host.contains(":") {
            let address = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            return address == "::" || address == "::1" || address.hasPrefix("fc") || address.hasPrefix("fd")
                || address.hasPrefix("fe8") || address.hasPrefix("fe9") || address.hasPrefix("fea")
                || address.hasPrefix("feb") || address.hasPrefix("::ffff:")
        }
        return !host.contains(".") || [".local", ".localhost", ".internal", ".lan", ".home.arpa"].contains { host.hasSuffix($0) }
    }

    /// The lowercase host of a URL or a bare host, without `www.` or a last dot.
    static func host(of value: String) -> String? {
        let text = value.contains("://") ? value : "https://" + value
        guard var host = URL(string: text)?.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if host.hasSuffix(".") { host.removeLast() }
        return host
    }
}
