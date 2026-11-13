import Foundation

/// How a source stores its data.
public enum HistorySourceFormat: String, Sendable {
    case chromium
    case firefox
    case safari
}

/// One browser profile on this Mac.
public struct HistorySource: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let profile: String?
    /// The database file. Nil when macOS refuses access to the source.
    public let database: URL?
    public let format: HistorySourceFormat

    public var needsAccess: Bool { database == nil }
}

/// Finds each source under the Library folder of the user.
public enum BrowserCatalog {

    // MARK: - Properties

    private struct BrowserFolder {
        let name: String
        let path: String
        let format: HistorySourceFormat
    }

    private static let folders = [
        BrowserFolder(name: "Chrome", path: "Google/Chrome", format: .chromium),
        BrowserFolder(name: "Arc", path: "Arc/User Data", format: .chromium),
        BrowserFolder(name: "Dia", path: "Dia/User Data", format: .chromium),
        BrowserFolder(name: "Brave", path: "BraveSoftware/Brave-Browser", format: .chromium),
        BrowserFolder(name: "Edge", path: "Microsoft Edge", format: .chromium),
        BrowserFolder(name: "Chromium", path: "Chromium", format: .chromium),
        BrowserFolder(name: "Firefox", path: "Firefox/Profiles", format: .firefox),
        BrowserFolder(name: "Zen", path: "zen/Profiles", format: .firefox)
    ]

    // MARK: - Finding

    public static func sources(library: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")) -> [HistorySource] {
        let support = library.appendingPathComponent("Application Support")
        return folders.flatMap { browser(in: support.appendingPathComponent($0.path), $0) }
            + safari(in: library)
    }

    private static func browser(in folder: URL, _ browser: BrowserFolder) -> [HistorySource] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return [HistorySource(id: browser.name, name: browser.name, profile: nil, database: nil, format: browser.format)]
        }
        switch browser.format {
        case .chromium:
            let titles = chromiumProfileNames(in: folder)
            return names.filter { $0 == "Default" || $0.hasPrefix("Profile ") }.sorted().compactMap { name in
                source(browser, profile: titles[name] ?? name, database: folder.appendingPathComponent(name).appendingPathComponent("History"))
            }
        default:
            return names.sorted().compactMap { name in
                let profile = name.split(separator: ".", maxSplits: 1).last.map(String.init) ?? name
                return source(browser, profile: profile, database: folder.appendingPathComponent(name).appendingPathComponent("places.sqlite"))
            }
        }
    }

    private static func source(_ browser: BrowserFolder, profile: String, database: URL) -> HistorySource? {
        guard FileManager.default.fileExists(atPath: database.path) else { return nil }
        return HistorySource(id: database.path, name: browser.name, profile: profile,
                           database: isReadable(database) ? database : nil, format: browser.format)
    }

    /// The profile names that a Chromium browser shows, by folder name.
    private static func chromiumProfileNames(in folder: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("Local State")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: [String: Any]] else { return [:] }
        return cache.compactMapValues { $0["name"] as? String }
    }

    private static func safari(in library: URL) -> [HistorySource] {
        let database = library.appendingPathComponent("Safari/History.db")
        guard FileManager.default.fileExists(atPath: database.path) else { return [] }
        return [HistorySource(id: database.path, name: "Safari", profile: nil,
                            database: isReadable(database) ? database : nil, format: .safari)]
    }

    /// An open is the test, because macOS can show a file and refuse to read it.
    private static func isReadable(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        try? handle.close()
        return true
    }
}
