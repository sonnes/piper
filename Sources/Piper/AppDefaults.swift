import AppKit

/// Every preference key the application reads, in one place.
///
/// No view holds a literal key or a literal size. A view that needs a stored
/// value reads it here.
@MainActor
final class AppDefaults {

    static let shared = AppDefaults()

    // MARK: Keys

    enum Key {
        static let vaultPath = "wikiPath"
        static let captureShortcut = "captureShortcut"
        static let composerDraft = "composerDraft"
        static let migratedLocalPreferences = "migratedLocalPreferences"
        static let style = "piperStyle"

        static let inspectorVisible = "wikiInspectorVisible"
        static let readerSize = "wikiReaderSize"
        static let readerTheme = "wikiReaderTheme"
        static let readerFont = "wikiReaderFont"
        static let readerAppearance = "wikiReaderAppearance"

        /// Keys carried over when the bundle identifier changed to `com.piper`.
        static let migrated = [
            vaultPath, captureShortcut, composerDraft, readerSize,
            "NSWindow Frame " + WindowName.capturePanel,
            "NSWindow Frame " + WindowName.mainWindow
        ]
    }

    /// Frame autosave names. A window controller reads its own name from here.
    enum WindowName {
        static let capturePanel = "PiperCapturePanel"
        static let mainWindow = "PiperLibrary"
    }

    // MARK: Sizes

    /// Timeline cell metrics.
    enum Timeline {
        static let cellPadding = NSEdgeInsets(top: 8, left: 4, bottom: 10, right: 4)
        static let unreadCircleDimension: CGFloat = 8
        static let unreadCircleMarginRight: CGFloat = 8
        static let boxLeftMargin: CGFloat = cellPadding.left + unreadCircleDimension + unreadCircleMarginRight
        static let titleBottomMargin: CGFloat = 1
        static let titleNumberOfLines = 3
        static let dateMarginLeft: CGFloat = 8
        static let starDimension: CGFloat = 13
        static let iconSize = NSSize(width: 48, height: 48)
        static let iconCornerRadius: CGFloat = 4
        static let iconMargin: CGFloat = 8
    }

    /// Sidebar cell metrics.
    enum Sidebar {
        static let imageSize = NSSize(width: 19, height: 19)
        static let imageMarginRight: CGFloat = 4
        static let countMarginLeft: CGFloat = 10
        static let countCornerRadius: CGFloat = 8
        static let countPadding = NSEdgeInsets(top: 1, left: 7, bottom: 1, right: 7)
        static let minimumThickness: CGFloat = 96
    }

    enum Window {
        static let mainSize = NSSize(width: 1240, height: 800)
        static let mainMinimumSize = NSSize(width: 850, height: 620)
        static let detailMinimumThickness: CGFloat = 384
        static let capturePanelSize = NSSize(width: 430, height: 932)
    }

    // MARK: Type

    /// The two font sizes every list row uses.
    ///
    /// The large size is `NSFont.systemFontSize + 1`. The small size is 90
    /// percent of it, rounded down.
    enum FontSize {
        static let large: CGFloat = NSFont.systemFontSize + 1
        static let small: CGFloat = (large * 0.90).rounded(.down)
    }

    // MARK: Stored values

    private let defaults = UserDefaults.standard

    var vaultPath: String {
        get {
            defaults.string(forKey: Key.vaultPath)
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Wiki").path
        }
        set { defaults.set(newValue, forKey: Key.vaultPath) }
    }

    var vaultURL: URL {
        URL(fileURLWithPath: (vaultPath as NSString).expandingTildeInPath).standardizedFileURL
    }

    /// Control-Option-C was an earlier alternative. A stored value that no
    /// longer matches a preset leaves the capture shortcut dead.
    var captureShortcut: String {
        get {
            let stored = defaults.string(forKey: Key.captureShortcut) ?? "Shift, Shift"
            return stored == "Control-Option-C" ? "Control-Option-Space" : stored
        }
        set { defaults.set(newValue, forKey: Key.captureShortcut) }
    }

    var inspectorVisible: Bool {
        get { defaults.object(forKey: Key.inspectorVisible) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.inspectorVisible) }
    }

    var readerSize: Double {
        get { defaults.object(forKey: Key.readerSize) as? Double ?? 18 }
        set { defaults.set(newValue, forKey: Key.readerSize) }
    }

    // MARK: Migration

    /// Carries preferences across the bundle identifier change to `com.piper`.
    func migrateLocalPreferencesIfNeeded(bundleIdentifier: String?) {
        guard bundleIdentifier == "com.piper", !defaults.bool(forKey: Key.migratedLocalPreferences) else { return }
        let previous = defaults.persistentDomain(forName: "local.piper") ?? [:]
        for key in Key.migrated where defaults.object(forKey: key) == nil {
            if let value = previous[key] { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: Key.migratedLocalPreferences)
    }
}
