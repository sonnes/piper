import Foundation

/// Web links in captured text. The attributed text preserves the original characters.
public struct CaptureLinks {

    // MARK: - Properties

    public let text: AttributedString
    public let urls: [URL]
    public let standaloneURL: URL?

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    // MARK: - Initialization

    public init(_ source: String) {
        var text = AttributedString(source)
        var urls: [URL] = []
        var seen: Set<URL> = []
        var standaloneURL: URL?
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = Self.detector?.matches(in: source, range: NSRange(source.startIndex..., in: source)) ?? []

        for match in matches {
            guard let sourceRange = Range(match.range, in: source), let detectedURL = match.url,
                  Self.isWebURL(detectedURL) else { continue }
            var label = source[sourceRange]

            // Data detection can include a closing Markdown delimiter in the URL.
            var excess = label.filter { $0 == ")" }.count - label.filter { $0 == "(" }.count
            while excess > 0, label.last == ")" {
                label = label.dropLast()
                excess -= 1
            }
            let url: URL
            if label.endIndex == sourceRange.upperBound {
                url = detectedURL
            } else {
                let suffixLength = source[sourceRange].count - label.count
                guard let corrected = URL(string: String(detectedURL.absoluteString.dropLast(suffixLength))) else { continue }
                url = corrected
            }
            guard let range = Range(NSRange(label.startIndex..<label.endIndex, in: source), in: text) else { continue }
            text[range].link = url
            if seen.insert(url).inserted { urls.append(url) }
            if label == trimmed { standaloneURL = url }
        }

        self.text = text
        self.urls = urls
        self.standaloneURL = standaloneURL
    }

    // MARK: - URL Validation

    public static func isWebURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false
    }

    /// The form of a web link that Piper compares. Two links to one article
    /// have the same form.
    ///
    /// The form has no fragment, no tracking parameters, no `www.`, and no
    /// slash at the end of the path. The scheme and the host are in lowercase.
    public static func canonical(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        parts.fragment = nil
        parts.scheme = "https"
        parts.host = parts.host.map { host in
            let host = host.lowercased()
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        if parts.port == 80 || parts.port == 443 { parts.port = nil }
        let items = parts.queryItems?.filter { item in
            let name = item.name.lowercased()
            return !name.hasPrefix("utm_") && !trackingParameters.contains(name)
        }
        parts.queryItems = items?.isEmpty == false ? items : nil
        while parts.path.count > 1, parts.path.hasSuffix("/") { parts.path.removeLast() }
        if parts.path == "/" { parts.path = "" }
        return parts.string ?? url.absoluteString
    }

    private static let trackingParameters: Set<String> = ["fbclid", "gclid", "dclid", "mc_cid", "mc_eid", "ref_src", "igshid"]
}
