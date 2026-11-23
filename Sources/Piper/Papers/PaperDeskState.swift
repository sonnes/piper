import AppKit
import Feeds

/// The color of a tab on the edge of the feed paper. `PiperTheme` holds the
/// fill and the edge of each color.
enum TabColor: String, Codable, CaseIterable, Identifiable {
    case indigo, zinc, sky, emerald, plum, teal, rose, clay

    var id: String { rawValue }

    /// The name of the color, for its swatch.
    var name: String { rawValue.capitalized }

    /// The colors that a new pin takes, in order. A pin takes the first color
    /// that no other pin has.
    static let pinOrder: [TabColor] = [.teal, .rose, .clay, .sky, .emerald, .plum]
}

/// One tab on the left edge of the feed paper.
///
/// The five fixed tabs come first. A pinned folder follows them. Each tab
/// has its own color.
enum PaperTab: Codable, Hashable {
    case inbox
    case clipboard
    case feeds
    case folders
    /// The folders that have agent sessions. The tab shows only while a session exists.
    case agents
    /// A pinned folder, by its absolute path.
    case pinned(String)

    /// The fixed tabs, in the order of the column.
    static let fixed: [PaperTab] = [.inbox, .clipboard, .feeds, .folders, .agents]

    /// The name on the tab.
    var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .clipboard: return "Clipboard"
        case .feeds: return "Feeds"
        case .folders: return "Folders"
        case .agents: return "Agents"
        case .pinned(let path): return URL(fileURLWithPath: path).lastPathComponent
        }
    }

    /// True for a tab that has an index. Clipboard goes straight to its list.
    /// Folders and a pinned folder show their tree.
    var hasIndex: Bool {
        switch self {
        case .clipboard, .folders, .pinned: return false
        case .inbox, .feeds, .agents: return true
        }
    }

    /// True for Folders and a pinned folder, which show a tree of folders and files.
    var showsTree: Bool {
        switch self {
        case .folders, .pinned: return true
        case .inbox, .clipboard, .feeds, .agents: return false
        }
    }

    /// The color of the tab. A pinned folder has the color that the reader
    /// chose, or teal.
    func color(pins: [String: TabColor]) -> TabColor {
        switch self {
        case .inbox: return .indigo
        case .clipboard: return .zinc
        case .feeds: return .sky
        case .folders: return .emerald
        case .agents: return .plum
        case .pinned(let path): return pins[path] ?? .teal
        }
    }

    /// The tabs of the column, and the pinned folders that have no tab.
    ///
    /// The column holds `limit` tabs. The fixed tabs come first, and Agents
    /// shows only while a session exists. Each pinned folder takes the next
    /// place. A pinned folder past the limit shows at the top of the Folders
    /// index instead.
    static func column(pins: [String], showsAgents: Bool,
                       limit: Int = AppDefaults.Papers.tabLimit) -> (tabs: [PaperTab], overflow: [String]) {
        let fixed = Self.fixed.filter { $0 != .agents || showsAgents }
        let room = max(0, limit - fixed.count)
        return (fixed + pins.prefix(room).map(PaperTab.pinned), Array(pins.dropFirst(room)))
    }
}

/// What the list of the feed paper shows.
enum PaperScope: Codable, Equatable {
    /// The Inbox stream: one capture section, or every section when the section is nil.
    case inbox(section: String?)
    /// The captures that are done.
    case done
    /// The clipboard texts that the reader has not saved.
    case clipboard
    /// Discover, All Unread, Starred, or one feed.
    case feed(FeedFilter)
    /// The files of one folder, by its path from the root of the active folder.
    /// The empty path is the root.
    case folder(String)
    /// The sessions of one folder, by its absolute path.
    case sessions(String)

    /// True for the scopes that show captures or clipboard texts.
    var showsCaptures: Bool {
        switch self {
        case .inbox, .done, .clipboard: return true
        case .feed, .folder, .sessions: return false
        }
    }
}

/// What the feed paper restores when it opens again.
///
/// One type covers the feed paper: its tab, its scope, the open folders of
/// the folder tree, the pinned folders and their colors, and its frame.
struct PaperDeskState: Codable, Equatable {

    // MARK: - Properties

    /// The active tab. The paper opens on Inbox.
    var tab = PaperTab.inbox
    /// What the list shows.
    var scope = PaperScope.inbox(section: nil)
    /// The open folders of the folder tree, by their absolute paths. Folders
    /// and the pinned folder tabs share them.
    var expandedFolders: [String] = []
    /// The pinned folders, by their absolute paths, in the order of the tabs.
    var pinnedFolders: [String] = []
    /// The tab color of each pinned folder, by its absolute path.
    var pinColors: [String: TabColor] = [:]
    /// The frame of the feed paper window, from `NSStringFromRect`.
    var feedFrame: String?
    /// The file of the file paper, as a path from the root of the active folder.
    var selectedFile: String?

    // MARK: - API

    /// The scope that a click on a tab shows.
    func defaultScope(for tab: PaperTab, root: String, sessionFolders: [String]) -> PaperScope {
        switch tab {
        case .inbox: return .inbox(section: nil)
        case .clipboard: return .clipboard
        case .feeds: return .feed(.allUnread)
        case .folders: return .folder("")
        case .agents: return .sessions(sessionFolders.first ?? root)
        case .pinned(let path): return .folder(Self.relativePath(of: path, in: root) ?? "")
        }
    }

    /// What a pin or an unpin did.
    enum PinChange: Equatable {
        case pinned
        case unpinned
        /// The column has no room. The folder has no pin.
        case full
    }

    /// Pins a folder, or removes its pin.
    ///
    /// The column holds `limit` tabs. A pin that does not fit changes nothing.
    /// A new pin takes the first color of `TabColor.pinOrder` that no other
    /// pin has, or zinc.
    ///
    /// - Parameter fixedTabs: The number of fixed tabs in the column.
    @discardableResult
    mutating func togglePin(_ path: String, fixedTabs: Int, limit: Int = AppDefaults.Papers.tabLimit) -> PinChange {
        if let index = pinnedFolders.firstIndex(of: path) {
            pinnedFolders.remove(at: index)
            pinColors[path] = nil
            if tab == .pinned(path) { tab = .folders }
            return .unpinned
        }
        guard fixedTabs + pinnedFolders.count < limit else { return .full }
        let used = Set(pinnedFolders.compactMap { pinColors[$0] })
        pinColors[path] = TabColor.pinOrder.first { !used.contains($0) } ?? .zinc
        pinnedFolders.append(path)
        return .pinned
    }

    /// Sets the tab color of a pinned folder.
    mutating func setColor(_ color: TabColor, of path: String) {
        guard pinnedFolders.contains(path) else { return }
        pinColors[path] = color
    }

    /// Forgets the state that belongs to the previous folder. The pins and
    /// the open folders stay, because they hold absolute paths.
    mutating func resetForVault() {
        if case .folder = scope { scope = .folder("") }
        if case .pinned = tab { tab = .folders }
        selectedFile = nil
    }

    /// The path of a folder from a root, or nil when the folder is outside the root.
    static func relativePath(of path: String, in root: String) -> String? {
        let base = URL(fileURLWithPath: root).standardizedFileURL.path
        let folder = URL(fileURLWithPath: path).standardizedFileURL.path
        if folder == base { return "" }
        let prefix = base.hasSuffix("/") ? base : base + "/"
        guard folder.hasPrefix(prefix) else { return nil }
        return String(folder.dropFirst(prefix.count))
    }

    // MARK: - Persistence

    static func restore(from defaults: UserDefaults = .standard) -> PaperDeskState {
        guard let data = defaults.data(forKey: AppDefaults.Key.paperDeskState),
              let state = try? JSONDecoder().decode(PaperDeskState.self, from: data) else {
            return PaperDeskState()
        }
        return state
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: AppDefaults.Key.paperDeskState)
    }
}

// MARK: - Decodable

extension PaperDeskState {
    private enum CodingKeys: String, CodingKey {
        case tab, scope, expandedFolders, pinnedFolders, pinColors, feedFrame, selectedFile
    }

    /// Reads a saved state. A key that an older version did not save takes its default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tab = try container.decodeIfPresent(PaperTab.self, forKey: .tab) ?? .inbox
        scope = try container.decodeIfPresent(PaperScope.self, forKey: .scope) ?? .inbox(section: nil)
        expandedFolders = try container.decodeIfPresent([String].self, forKey: .expandedFolders) ?? []
        pinnedFolders = try container.decodeIfPresent([String].self, forKey: .pinnedFolders) ?? []
        pinColors = try container.decodeIfPresent([String: TabColor].self, forKey: .pinColors) ?? [:]
        feedFrame = try container.decodeIfPresent(String.self, forKey: .feedFrame)
        selectedFile = try container.decodeIfPresent(String.self, forKey: .selectedFile)
    }
}
