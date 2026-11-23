import Foundation

/// The site of a link. Piper keys feeds, icons, tabs, and history by site.
public struct Site: Hashable, Sendable {

    /// The host in lowercase, without a leading `www.`.
    public let key: String

    public init(host: String) {
        let host = host.lowercased()
        key = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Nil when the link has no host.
    public init?(_ url: URL) {
        guard let host = url.host, !host.isEmpty else { return nil }
        self.init(host: host)
    }
}

public extension URL {
    /// True for an http or https link with a host.
    var isWeb: Bool {
        ["http", "https"].contains(scheme?.lowercased() ?? "") && host?.isEmpty == false
    }
}
