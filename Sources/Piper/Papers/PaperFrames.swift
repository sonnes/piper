import AppKit

/// The kinds of reader paper. Each kind keeps its own last size.
enum PaperKind: String {
    /// An article, a link capture, or a file.
    case reader
    /// A note that is not a link.
    case note
    /// An agent session.
    case session
}

/// The saved frame of each reader paper, by its item, so that a paper that
/// opens again comes back to its last size and place.
///
/// The store keeps the newest `AppDefaults.Papers.savedFrameLimit` frames.
/// A paper without a saved frame takes its place in the cascade, at the last
/// size of a paper of its kind.
struct PaperFrames: Codable, Equatable {

    struct Entry: Codable, Equatable {
        let key: String
        let frame: String
    }

    /// The frames, the newest last.
    private(set) var entries: [Entry] = []
    /// The last size of a paper of each kind, by `PaperKind.rawValue`.
    private(set) var lastSizes: [String: String]? = nil

    // MARK: - API

    /// The saved frame of the paper of an item.
    func frame(of item: PaperItem) -> NSRect? {
        let key = Self.key(of: item)
        return entries.last { $0.key == key }.map { NSRectFromString($0.frame) }
    }

    /// The last size of a paper of a kind.
    func lastSize(of kind: PaperKind) -> NSSize? {
        lastSizes?[kind.rawValue].map(NSSizeFromString)
    }

    /// Saves the frame of the paper of an item, and its size as the last size
    /// of its kind. The oldest frame goes when the store is full.
    mutating func set(_ frame: NSRect, of item: PaperItem, kind: PaperKind) {
        var sizes = lastSizes ?? [:]
        sizes[kind.rawValue] = NSStringFromSize(frame.size)
        lastSizes = sizes
        let key = Self.key(of: item)
        entries.removeAll { $0.key == key }
        entries.append(Entry(key: key, frame: NSStringFromRect(frame)))
        if entries.count > AppDefaults.Papers.savedFrameLimit {
            entries.removeFirst(entries.count - AppDefaults.Papers.savedFrameLimit)
        }
    }

    /// The key of an item in the store.
    static func key(of item: PaperItem) -> String {
        switch item {
        case .note(let id): return "note:" + id.uuidString
        case .article(let id): return "article:" + id
        case .file: return "file"
        case .session(let id): return "session:" + id.uuidString
        case .newSession(let folder): return "newSession:" + folder
        }
    }

    // MARK: - Persistence

    static func restore(from defaults: UserDefaults = .standard) -> PaperFrames {
        guard let data = defaults.data(forKey: AppDefaults.Key.readerFrames),
              let frames = try? JSONDecoder().decode(PaperFrames.self, from: data) else { return PaperFrames() }
        return frames
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: AppDefaults.Key.readerFrames)
    }
}

/// The rules that keep a paper on the screen.
enum PaperPlacement {

    /// The frame of a paper that stays on a screen: the screen that holds the
    /// most of the paper, or the first screen when no screen holds any of it.
    /// A paper larger than its screen shrinks to the screen, down to `minimum`.
    nonisolated static func clamp(_ frame: NSRect, to screens: [NSRect], minimum: NSSize) -> NSRect {
        guard let first = screens.first else { return frame }
        let screen = screens.max { overlap(frame, $0) < overlap(frame, $1) }.flatMap { overlap(frame, $0) > 0 ? $0 : nil } ?? first
        let width = max(min(frame.width, screen.width), min(minimum.width, frame.width))
        let height = max(min(frame.height, screen.height), min(minimum.height, frame.height))
        let x = min(max(frame.minX, screen.minX), screen.maxX - width)
        let y = min(max(frame.minY, screen.minY), screen.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// The frame of a zoomed paper: the visible frame of its screen, less the
    /// inset that the papers keep from the edges of the screen.
    nonisolated static func zoomed(in screen: NSRect) -> NSRect {
        screen.insetBy(dx: AppDefaults.Papers.screenInset, dy: AppDefaults.Papers.screenInset)
    }

    private nonisolated static func overlap(_ a: NSRect, _ b: NSRect) -> CGFloat {
        let common = a.intersection(b)
        return common.isNull ? 0 : common.width * common.height
    }
}

/// What a double click on the header of a paper does. It follows the
/// setting "Double-click a window's title bar to" in System Settings > Desktop & Dock.
enum TitleBarDoubleClick: Equatable {
    case zoom, minimize, none

    /// The action for a value of `AppleActionOnDoubleClick`. With no value, the title bar zooms.
    nonisolated static func action(for value: String?) -> TitleBarDoubleClick {
        switch value {
        case "Minimize": return .minimize
        case "None", "Do Nothing": return .none
        default: return .zoom
        }
    }

    static var current: TitleBarDoubleClick {
        action(for: UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleActionOnDoubleClick"] as? String)
    }
}
