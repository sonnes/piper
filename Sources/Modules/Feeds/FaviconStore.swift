import Foundation
import ImageIO
import Observation

/// Finds and keeps the icon of each site, as NetNewsWire does.
///
/// The store reads the icon links of the home page of the site. If the page
/// names no icon that loads, it tries `/favicon.ico`. It keeps each icon as a
/// file, so a restart does not fetch it again.
@MainActor
@Observable
public final class FaviconStore {

    /// The image data of each host that has an icon.
    public private(set) var icons: [String: Data] = [:]

    @ObservationIgnored private let folder: URL
    @ObservationIgnored private let session: URLSession
    /// The hosts that this launch asked for. A host with no icon waits for the next launch.
    @ObservationIgnored private var asked: Set<String> = []

    public init(folder: URL? = nil, session: URLSession = .shared) {
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Piper/Favicons")
        self.session = session
    }

    /// The icon of the host. If the store has no icon, it starts to look for one,
    /// and `icons` changes when it finds one.
    public func icon(for host: String) -> Data? {
        let host = Self.normalized(host)
        if let data = icons[host] { return data }
        guard !host.isEmpty, !asked.contains(host) else { return nil }
        asked.insert(host)
        let file = folder.appendingPathComponent(host)
        let session = session
        let folder = folder
        // A view asks while it draws, so the answer arrives in a later update.
        Task {
            if let data = try? Data(contentsOf: file), Self.isImage(data) {
                icons[host] = data
                return
            }
            guard let data = await Self.find(host, session: session) else { return }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            icons[host] = data
        }
        return nil
    }

    // MARK: - Finding

    /// The first icon of the site that loads as an image.
    nonisolated static func find(_ host: String, session: URLSession) async -> Data? {
        for candidate in await candidates(host, session: session) {
            if let data = try? await get(candidate, session: session), isImage(data) { return data }
        }
        return nil
    }

    /// The icon links of the home page, then `/favicon.ico`, then the Apple touch icons.
    nonisolated static func candidates(_ host: String, session: URLSession) async -> [URL] {
        guard let home = URL(string: "https://\(host)/") else { return [] }
        var links: [String] = []
        var touchIcons: [String] = []
        if let page = try? await get(home, session: session) {
            let metadata = HTMLMetadataParser.htmlMetadata(with: ParserData(url: home.absoluteString, data: page))
            links = metadata.favicons.filter { !($0.type ?? "").contains("svg") }.compactMap(\.urlString)
                .filter { !$0.lowercased().hasSuffix(".svg") }
            touchIcons = metadata.appleTouchIcons.compactMap(\.urlString)
        }
        let all = links + ["https://\(host)/favicon.ico"] + touchIcons
        var seen = Set<String>()
        return all.filter { seen.insert($0).inserted }.compactMap(URL.init(string:))
    }

    nonisolated static func isImage(_ data: Data) -> Bool {
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    nonisolated static func normalized(_ host: String) -> String {
        let host = host.lowercased()
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private nonisolated static func get(_ url: URL, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: FeedFetch.timeout))
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw FeedError("The server answered \(status).")
        }
        return data
    }
}
