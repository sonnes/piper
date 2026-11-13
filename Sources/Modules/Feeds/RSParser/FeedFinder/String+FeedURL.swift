import CryptoKit
import Foundation

// Piper replacements for the RSCore and RSWeb helpers that RSParser and
// FeedFinder use in NetNewsWire.

extension String {

    /// The MD5 hash as lowercase hex. Feeds without a guid use it as an ID.
    var md5String: String {
        Insecure.MD5.hash(data: Data(utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The string as an http or https URL. A feed: scheme becomes https, and a
    /// string with no scheme gets https.
    var normalizedURL: String {
        var value = trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("feed:") {
            value = String(value.dropFirst(5))
            if value.hasPrefix("//") { value = String(value.dropFirst(2)) }
        }
        if !value.lowercased().hasPrefix("http://") && !value.lowercased().hasPrefix("https://") {
            value = "https://" + value
        }
        return value
    }

    func caseInsensitiveContains(_ other: String) -> Bool {
        range(of: other, options: .caseInsensitive) != nil
    }

    /// True if the host of the URL is one of the domains, or a subdomain of one.
    func matchesDomain(in domains: [String]) -> Bool {
        guard let host = URL(string: self)?.host?.lowercased() else { return false }
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
