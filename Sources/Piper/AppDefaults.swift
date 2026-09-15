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
        static let fileSort = "wikiFileSort"

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
        static let mainSplitView = "PiperMainSplitView"
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
        static var textHeight: CGFloat {
            let font = PiperTheme.uiNS(FontSize.large)
            return ceil(NSLayoutManager().defaultLineHeight(for: font)) * CGFloat(titleNumberOfLines)
        }
    }

    /// Sidebar cell metrics.
    ///
    /// The source list follows the macOS sidebar size preference.
    enum Sidebar {
        static func metrics(for style: NSTableView.RowSizeStyle) -> (fontSize: CGFloat, imageSize: CGFloat) {
            switch style {
            case .small: return (11, 16)
            case .large: return (15, 22)
            default: return (13, 19)
            }
        }

        static let imageMarginRight: CGFloat = 4
        static let countMarginLeft: CGFloat = 10
        static let countCornerRadius: CGFloat = 8
        static let countPadding = NSEdgeInsets(top: 1, left: 7, bottom: 1, right: 7)
        static let minimumThickness: CGFloat = 180

        static let rowCornerRadius: CGFloat = 6
        /// The inset of the selection fill from each edge of the sidebar.
        static let rowInset: CGFloat = 12
        /// The gutter that holds the disclosure triangle. A file reserves it, so
        /// that every icon of one level starts at the same place.
        static let disclosureWidth: CGFloat = 10
        static let indent: CGFloat = 13
        static let countFontSize: CGFloat = 13
        static let iconPointSize: CGFloat = 14
        static let disclosurePointSize: CGFloat = 9

        static let headerFontSize: CGFloat = 11
        /// The space over a group header. The first header needs less, because
        /// the toolbar is already over it.
        static let headerTopMargin: CGFloat = 14
        static let firstHeaderTopMargin: CGFloat = 8
        static let headerBottomMargin: CGFloat = 4
    }

    enum Window {
        static let mainSize = NSSize(width: 1240, height: 800)
        static let mainMinimumSize = NSSize(width: 850, height: 620)
        static let detailMinimumThickness: CGFloat = 384
        static let capturePanelSize = NSSize(width: 430, height: 932)
        static let captureCornerRadius: CGFloat = 22
    }

    enum Reader {
        static let horizontalInset: CGFloat = 48
        static let topInset: CGFloat = 20
        static let floatingActionInset: CGFloat = 20
        static let floatingActionSpacing: CGFloat = 8
        static let floatingActionShadow: CGFloat = 6
        static let headerHeight: CGFloat = 68
        static let titleSize: CGFloat = 29.6
        static let headingMultipliers: [CGFloat] = [1.65, 1.4, 1.2, 1, 1, 1]

        static let columnWidth: CGFloat = 44 * 16
    }

    enum CaptureItem {
        static let cornerRadius: CGFloat = 20
        static let fontSize: CGFloat = 16
        static let lineSpacing: CGFloat = 5
        static let spacing: CGFloat = 12
        static let circleSize: CGFloat = 18
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 12
    }

    /// Composer metrics.
    ///
    /// The height of the card follows from the line height. A whole number of
    /// lines is therefore visible, and no line is cut at the bottom edge.
    enum Composer {
        static let lineHeight: CGFloat = 23
        static let visibleLines = 2
        /// The space between the edge of the text region and the first line.
        static let textInset = NSSize(width: 14, height: 7)
        /// The space between the edge of the card and the text region.
        static let regionInset: CGFloat = 14
        /// The space between the edge of the panel and the card.
        static let margin: CGFloat = 10
        /// The space that holds the overlay scroller off the text.
        static let scrollerInset: CGFloat = 6

        /// The height of the text region that scrolls.
        static let textHeight = textInset.height * 2 + lineHeight * CGFloat(visibleLines)
        /// The height of the whole card.
        static let height = textHeight + regionInset * 2
        /// The width the panel gives the card.
        static let width = Window.capturePanelSize.width - margin * 2
        /// The width available to the text.
        static let textWidth = width - textInset.width * 2
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
        get { defaults.object(forKey: Key.inspectorVisible) as? Bool ?? false }
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
