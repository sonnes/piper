import AppKit
import Stream

/// The color of a tab on the edge of the feed paper. `PiperTheme` holds the
/// fill and the edge of each color.
enum TabColor: String, Codable, CaseIterable, Identifiable {
    case indigo, zinc, sky, emerald, plum, teal, rose, clay

    var id: String { rawValue }

    /// The name of the color, for its swatch.
    var name: String { rawValue.capitalized }

    /// The colors of the folder tabs, in the order that new folders take
    /// them. The fixed tabs use none of these colors.
    static let folderOrder: [TabColor] = [.teal, .rose, .clay, .emerald]
}

/// One tab on the left edge of the feed paper.
///
/// Today comes first, then Feeds and Agents. Each folder of the folder list follows
/// them, in the order that the reader added the folders. Each tab has its own color.
enum PaperTab: Codable, Hashable {
    /// The stream of notes, links, and feed articles.
    case today
    /// The feeds: Sources, where the reader adds a feed, and the articles of each feed.
    case feeds
    /// The folders that have agent sessions. The tab shows only while a session exists.
    case agents
    /// A folder of the folder list, by its path in the list.
    case folder(String)

    /// The fixed tabs, in the order of the column.
    static let fixed: [PaperTab] = [.today, .feeds, .agents]

    /// The name on the tab.
    var title: String {
        switch self {
        case .today: return "Today"
        case .feeds: return "Feeds"
        case .agents: return "Agents"
        case .folder(let path): return URL(fileURLWithPath: path).lastPathComponent
        }
    }

    /// True for a tab that has an index. A folder shows its tree.
    var hasIndex: Bool {
        switch self {
        case .folder: return false
        case .today, .feeds, .agents: return true
        }
    }

    /// True for the tab of a folder, which shows a tree of folders and files.
    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    /// The color of the tab. A folder has the color in `folders`, or teal.
    func color(folders: [String: TabColor]) -> TabColor {
        switch self {
        case .today: return .indigo
        case .feeds: return .sky
        case .agents: return .plum
        case .folder(let path): return folders[path] ?? .teal
        }
    }

    /// The tabs of the column: the fixed tabs, then one tab for each folder.
    /// Agents shows only while a session exists.
    static func column(folders: [String], showsAgents: Bool) -> [PaperTab] {
        fixed.filter { $0 != .agents || showsAgents } + folders.map(PaperTab.folder)
    }

    /// The number of the tab in a column, from 1, for Command and a number key.
    static func number(of tab: PaperTab, in column: [PaperTab]) -> Int? {
        column.firstIndex(of: tab).map { $0 + 1 }
    }
}

/// What the list of the feed paper shows.
enum PaperScope: Codable, Equatable {
    /// Today: one capture section, or everything when the section is nil.
    case today(section: String?)
    /// The captures that are done.
    case done
    /// The articles of one feed, by its feed address.
    case feed(String)
    /// The feeds, their settings, and the sites of browser history that have a feed.
    case sources
    /// The tree of the active folder.
    case folder
    /// The sessions of one folder, by its absolute path.
    case sessions(String)

    /// True for the scopes that show captures.
    var showsCaptures: Bool {
        switch self {
        case .today, .done: return true
        case .feed, .sources, .folder, .sessions: return false
        }
    }
}

/// What the feed paper restores when it opens again.
///
/// One type covers the feed paper: its tab, its scope, the open folders of
/// the folder tree, the color and the file count of each folder tab, and the
/// file of the file paper. `PaperFrames` keeps the frame.
struct PaperDeskState: Codable, Equatable {

    // MARK: - Properties

    /// The active tab. The paper opens on Today.
    var tab = PaperTab.today
    /// What the list shows.
    var scope = PaperScope.today(section: nil)
    /// The lens of Today: All, Notes, Reading, or Kept.
    var lens = UnifiedStream.Lens.all
    /// The open folders of the folder tree, by their absolute paths.
    var expandedFolders: [String] = []
    /// The tab color of each folder, by its path in the folder list.
    var folderColors: [String: TabColor] = [:]
    /// The number of files in each folder at its last scan, by its path in the
    /// folder list. Piper scans only the active folder, so the other tabs
    /// show the count of their last scan.
    var folderCounts: [String: Int] = [:]
    /// The file of the file paper, as a path from the root of the active folder.
    var selectedFile: String?

    // MARK: - API

    /// The scope that a click on a tab shows.
    func defaultScope(for tab: PaperTab, root: String, sessionFolders: [String]) -> PaperScope {
        switch tab {
        case .today: return .today(section: nil)
        case .feeds: return .sources
        case .agents: return .sessions(sessionFolders.first ?? root)
        case .folder: return .folder
        }
    }

    /// Gives each folder of the list a color, and forgets the colors and the
    /// counts of the folders that left the list.
    ///
    /// A new folder takes the first color of `TabColor.folderOrder` that no
    /// other folder has. When each color is in use, the colors go round in
    /// the order of the list.
    mutating func assignColors(to folders: [String]) {
        folderColors = folderColors.filter { folders.contains($0.key) }
        folderCounts = folderCounts.filter { folders.contains($0.key) }
        let order = TabColor.folderOrder
        for (index, folder) in folders.enumerated() where folderColors[folder] == nil {
            let used = Set(folderColors.values)
            folderColors[folder] = order.first { !used.contains($0) } ?? order[index % order.count]
        }
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
        case tab, scope, lens, expandedFolders, folderColors, folderCounts, selectedFile
    }

    /// Reads a saved state. A key that is missing or that this version cannot
    /// read takes its default, so the rest of the state stays. A feed scope
    /// shows on the Feeds tab, and the Feeds tab shows only a feed scope.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tab = (try? container.decodeIfPresent(PaperTab.self, forKey: .tab)) ?? .today
        scope = (try? container.decodeIfPresent(PaperScope.self, forKey: .scope)) ?? .today(section: nil)
        switch scope {
        case .feed, .sources: tab = .feeds
        default: if tab == .feeds { scope = .sources }
        }
        lens = (try? container.decodeIfPresent(UnifiedStream.Lens.self, forKey: .lens)) ?? .all
        expandedFolders = (try? container.decodeIfPresent([String].self, forKey: .expandedFolders)) ?? []
        folderColors = (try? container.decodeIfPresent([String: TabColor].self, forKey: .folderColors)) ?? [:]
        folderCounts = (try? container.decodeIfPresent([String: Int].self, forKey: .folderCounts)) ?? [:]
        selectedFile = try? container.decodeIfPresent(String.self, forKey: .selectedFile)
    }
}
