import AppKit
import SwiftUI

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
        static let wikiPaths = "wikiPaths"
        static let captureShortcut = "captureShortcut"
        static let captureFloating = "captureFloating"
        static let composerDraft = "composerDraft"
        static let migratedLocalPreferences = "migratedLocalPreferences"
        static let accessibilityTipDismissed = "accessibilityTipDismissed"
        static let showsFileSource = "showsFileSource"

        static let agentDisabledFolders = "agentDisabledFolders"
        static let agentLastFolder = "agentLastFolder"
        static let agentDefaultSkills = "agentDefaultSkills"
        static let claudePath = "claudePath"
        static let claudePermissionMode = "claudePermissionMode"
        static let claudeModel = "claudeModel"
        /// The agents that speak ACP, as JSON.
        static let acpAgents = "acpAgents"
        static let sessionAgent = "sessionAgent"
        static let marginAgent = "marginAgent"
        static let marginModel = "marginModel"

        static let readerSize = "wikiReaderSize"
        static let readerTheme = "wikiReaderTheme"
        static let readerFont = "wikiReaderFont"
        static let readerAppearance = "wikiReaderAppearance"
        static let fileSort = "wikiFileSort"
        /// The height that the reader gave the session card.
        static let sessionCardHeight = "sessionCardHeight"
        /// The pill, the card, or the detached panel.
        static let sessionPresentation = "sessionPresentation"
        /// The folder that Save as File used last.
        static let articleExportFolder = "articleExportFolder"

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
        static let mainSplitView = "PiperMainSplitViewFourPane"
        static let sessionPanel = "PiperSessionPanel"
    }

    // MARK: Sizes

    enum ListSearch {
        static let horizontalInset: CGFloat = 12
        static let verticalInset: CGFloat = 8
    }

    /// File row metrics.
    enum Timeline {
        static let unreadCircleDimension: CGFloat = 8
        /// The column that holds the unread dot.
        static let gutterWidth: CGFloat = 16
        static let verticalPadding: CGFloat = 6
    }

    /// Sidebar cell metrics.
    ///
    /// The source list follows the macOS sidebar size preference.
    enum Sidebar {
        static func metrics(for style: NSTableView.RowSizeStyle) -> (fontSize: CGFloat, imageSize: CGFloat) {
            switch style {
            case .small: return (11, 16)
            case .large: return (15, 22)
            default: return (13, 18)
            }
        }

        static let imageMarginRight: CGFloat = 4
        static let countMarginLeft: CGFloat = 10
        static let countCornerRadius: CGFloat = 8
        static let countPadding = NSEdgeInsets(top: 1, left: 7, bottom: 1, right: 7)
        static let minimumThickness: CGFloat = 210

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
        static let addButtonSize: CGFloat = 20
        /// The corner radius of a folder tile, as a fraction of its side.
        static let tileCornerFraction: CGFloat = 0.28
        /// The diameter of a section dot, as a fraction of the icon side.
        static let dotFraction: CGFloat = 0.55
        /// The size of the symbol in a tile, as a fraction of its side.
        static let tileSymbolFraction: CGFloat = 0.62
        static let attentionPadding = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        static let actionSpacing: CGFloat = 6
        static let trailingInset: CGFloat = 4
        /// The space over a group header. The first header needs less, because
        /// the toolbar is already over it.
        static let headerTopMargin: CGFloat = 14
        static let firstHeaderTopMargin: CGFloat = 8
        static let headerBottomMargin: CGFloat = 4
    }

    enum Window {
        static let captureSettingsSize = NSSize(width: 560, height: 380)
        static let mainSize = NSSize(width: 1240, height: 800)
        static let mainMinimumSize = NSSize(width: 900, height: 620)
        static let listMinimumThickness: CGFloat = 300
        static let detailMinimumThickness: CGFloat = 384
        static let capturePanelSize = NSSize(width: 600, height: 960)
        static let capturePanelMinimumSize = NSSize(width: 340, height: 480)
        /// The corner radius of the main window.
        static let cornerRadius: CGFloat = 12
        static let captureCornerRadius: CGFloat = 22
    }

    enum Reader {
        static let horizontalInset: CGFloat = 48
        static let topInset: CGFloat = 20
        /// The space over the byline at the top of a Markdown file.
        static let headerTopInset: CGFloat = 36
        static let bylineFontSize: CGFloat = 12.5
        /// The heading sizes of the reader page: 30, 21, and 18 points over a 16.5-point body.
        static let headingMultipliers: [CGFloat] = [1.8, 1.27, 1.1, 1, 1, 1]
        /// The extra line height as a part of the font size. The reader page uses a line height of 1.6.
        static let lineSpacing: CGFloat = 0.4
        static let defaultFont = WikiReadingFont.serif
        static let defaultSize = 18.0
        static let footnoteFontSize: CGFloat = 11
        static let footnoteBaselineOffset: CGFloat = 6

        static let columnWidth: CGFloat = 640
        static let noteFontSize: CGFloat = 15
        static let codeFontSize: CGFloat = 13
    }

    /// The Reader tab of a link capture.
    enum ArticleReader {
        static let addressHeight: CGFloat = 28
        static let addressFontSize: CGFloat = 11.5
        /// Seconds before Piper reads a page that has not finished loading.
        static let loadTimeout: Double = 20
        /// The wait after a load, for a page that draws its text with a script.
        static let settleMilliseconds = 300
        static let wordsPerMinute: Double = 230
        static let horizontalInset: CGFloat = 16
        static let progressHeight: CGFloat = 2
        /// The line over the article that says where it opened.
        static let resumeFontSize: CGFloat = 12
        static let resumeVerticalPadding: CGFloat = 7
        /// The space between the Show Web Page button and the tabs under it.
        static let webPageButtonMargin: CGFloat = 16
        /// The size of the hidden web view that loads a page.
        static let loaderSize = NSSize(width: 1024, height: 768)
    }

    /// The session card in the corner of the detail pane, and its detached panel.
    enum SessionCard {
        static let width: CGFloat = 400
        static let height: CGFloat = 560
        static let minimumHeight: Double = 260
        static let maximumHeight: Double = 900
        static let cornerRadius: CGFloat = 16
        static let margin: CGFloat = 16
        static let headerHeight: CGFloat = 44
        static let pillHeight: CGFloat = 34
        static let pillMaximumWidth: CGFloat = 340
        /// The part of the detail pane that the card can cover at most.
        static let paneFraction: CGFloat = 0.85
        static let panelSize = NSSize(width: 420, height: 640)
        static let panelMinimumSize = NSSize(width: 340, height: 360)
        static let tabsMinimumWidth: CGFloat = 220
        static let headerPadding = EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 8)
        static let pillPadding = EdgeInsets(top: 0, leading: 11, bottom: 0, trailing: 14)
        /// The number of sessions that the session menu of the header shows.
        static let menuSessionLimit = 20
        /// The height of the strip at the top edge that changes the height of the card.
        static let resizeHandleHeight: CGFloat = 6
        static let cardShadowRadius: CGFloat = 22
        static let cardShadowOffset: CGFloat = 10
        static let pillShadowRadius: CGFloat = 12
        static let pillShadowOffset: CGFloat = 4
        /// The distance of a new detached panel from the top and the right of the screen.
        static let panelScreenInset: CGFloat = 30
    }

    /// The tabs that float over the bottom of the detail pane.
    enum TabIsland {
        static let segmentHeight: CGFloat = 26
        static let fontSize: CGFloat = 12.5
        static let segmentPadding: CGFloat = 12
        /// The space between the capsule and the segments.
        static let inset: CGFloat = 3
        static let segmentShadowRadius: CGFloat = 1
        static let segmentShadowOffset: CGFloat = 0.5
        static let shadowRadius: CGFloat = 12
        static let shadowOffset: CGFloat = 4
        static let bottomMargin: CGFloat = 16
        /// The space that content leaves free under its last line for the tabs.
        static let clearance: CGFloat = 64
    }

    /// The toast of a web page capture.
    enum ReadingToast {
        static let width: CGFloat = 360
        /// The space between the toast and the corner of the screen.
        static let margin: CGFloat = 30
        static let cornerRadius: CGFloat = 12
        static let padding = EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 12)
        static let checkSize: CGFloat = 16
        static let checkFontSize: CGFloat = 9
        static let badgeSize: CGFloat = 22
        static let buttonHeight: CGFloat = 24
        static let buttonPadding: CGFloat = 10
    }

    /// The Reading list and the Notes tab of a link capture.
    enum Reading {
        static let badgeSize: CGFloat = 26
        static let progressHeight: CGFloat = 3
        static let quoteRuleWidth: CGFloat = 2
        /// The column of the Notes tab.
        static let notebookWidth: CGFloat = 600
        /// The wait after the last scroll before Piper saves the position.
        static let positionSaveDelay = Duration.milliseconds(800)
        /// The part of the article above the screen that counts as finished.
        static let finishedProgress = 0.97
        /// The number of articles in the Continue Reading row of Home.
        static let homeCount = 3
        /// The space over the Continue Reading row of Home.
        static let homeTopInset: CGFloat = 44
    }

    /// The Notes tab of a link capture, and its Save as File popover.
    enum Notebook {
        static let horizontalPadding: CGFloat = 30
        static let topPadding: CGFloat = 26
        static let titleFontSize: CGFloat = 24
        static let summaryFontSize: CGFloat = 14
        static let summaryMinimumHeight: CGFloat = 70
        static let quoteFontSize: CGFloat = 15
        /// The padding and the corner radius of the summary field, a question, and the file preview.
        static let fieldPadding: CGFloat = 8
        static let fieldRadius: CGFloat = 8
        static let labelTopPadding: CGFloat = 22
        static let colorBarWidth: CGFloat = 4
        static let formWidth: CGFloat = 360
        static let formPadding: CGFloat = 14
        static let previewHeight: CGFloat = 140
        static let previewFontSize: CGFloat = 11
    }

    /// A chip over the Inbox stream, such as Reading.
    enum FilterChip {
        static let fontSize: CGFloat = 12
        static let countFontSize: CGFloat = 11
        static let countOpacity = 0.6
        static let spacing: CGFloat = 5
        static let horizontalPadding: CGFloat = 10
        static let height: CGFloat = 24
    }

    /// The ring of a link that fills with the reading progress.
    enum ProgressRing {
        static let lineWidth: CGFloat = 1.25
        static let progressLineWidth: CGFloat = 2.4
        static let progressInset: CGFloat = 1.2
        /// The smallest part of the ring that a started article fills, so the start shows.
        static let minimumProgress = 0.04
        static let checkFontSize: CGFloat = 8
    }

    /// A square with the first letter of a site.
    enum ArticleBadge {
        static let fontFraction: CGFloat = 0.5
        static let cornerFraction: CGFloat = 0.24
    }

    /// A row of the Inbox stream in the main window.
    enum InboxRow {
        static let controlSize: CGFloat = 18
        /// The column that holds the circle or the ring.
        static let controlColumn: CGFloat = 26
        static let columnSpacing: CGFloat = 8
        /// The space from the edge of the row to the text.
        static let textInset: CGFloat = padding.leading + controlColumn + columnSpacing
        static let badgeSize: CGFloat = 16
        static let unreadDot: CGFloat = 7
        static let padding = EdgeInsets(top: 9, leading: 8, bottom: 10, trailing: 10)
        static let cornerRadius: CGFloat = 8
        static let titleFontSize: CGFloat = 13
        static let metaFontSize: CGFloat = 11.5
        static let detailFontSize: CGFloat = 11
        static let quoteFontSize: CGFloat = 12
        static let codeFontSize: CGFloat = 12
        static let sectionDot: CGFloat = 7
        static let chevronSize: CGFloat = 8
    }

    /// A highlight or a question under a link capture in the list.
    enum ChildNote {
        static let fontSize: CGFloat = 12.5
        static let lineSpacing: CGFloat = 1.5
        static let ruleWidth: CGFloat = 2
        static let tagFontSize: CGFloat = 10.5
        static let tagHeight: CGFloat = 16
        static let swatchSize: CGFloat = 7
    }

    /// Capture list metrics, shared by the panel and the Inbox pane.
    enum CaptureItem {
        static let cornerRadius: CGFloat = PiperTheme.cardRadius
        static let fontSize: CGFloat = 15
        static let clipboardFontSize: CGFloat = 13
        static let clipboardCodeFontSize: CGFloat = 12
        static let lineSpacing: CGFloat = 2
        static let circleSize: CGFloat = 22
        static let buttonHitSize: CGFloat = 30
        static let tabHeight: CGFloat = 26
        static let panelHeaderHeight: CGFloat = 54
        static let rowSpacing: CGFloat = 6
        static let cardInset: CGFloat = 4
        static let actionSpacing: CGFloat = 8
        static let actionMinimumWidth: CGFloat = 72
        static let sectionMenuWidth: CGFloat = 280
        static let sectionMenuHeight: CGFloat = 320
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 10
        static let minimumHeight: CGFloat = 42
        static let clipboardHeight: CGFloat = 42
        /// The space from the edge of a card to the text after the circle.
        static let textInset: CGFloat = horizontalPadding + buttonHitSize + 10
        /// The inset of the list from the edge of the pane.
        static let listInset: CGFloat = 14
        /// Lifts the panel hint line clear of the rounded bottom corners.
        static let hintBottomPadding: CGFloat = 6
        /// The number of clipboard items that the capture list shows.
        static let recentClipboardCount = 5
    }

    /// Composer metrics.
    ///
    /// The height of the card follows from the line height. A whole number of
    /// lines is therefore visible, and no line is cut at the bottom edge.
    enum Composer {
        static let inboxHeight: CGFloat = 56
        static let inboxCircleSize: CGFloat = 16
        static let inboxFontSize: CGFloat = 13
        static let inboxLineHeight: CGFloat = 18
        static let lineHeight: CGFloat = 23
        static let visibleLines = 2
        /// The space between the edge of the text region and the first line.
        static let textInset = NSSize(width: 10, height: 7)
        /// The space between the edge of the card and the text region.
        static let regionInset: CGFloat = 5
        /// The space between the edge of the panel and the card.
        static let margin: CGFloat = 14
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

    /// Agent sessions in folders.
    enum Agents {
        /// A turn stops after this time. The time a card waits does not count.
        static let timeout: TimeInterval = 10 * 60
        /// The number of turns at the same time. More turns wait.
        static let concurrency = 2
        /// The number of skills the composer list shows.
        static let completionLimit = 6
        /// The model a run uses when the reader chose none.
        static let model = "sonnet"
        /// The model of a margin answer when the reader chose none. It is fast and costs little.
        static let marginModel = "haiku"
        /// How long a toast with a button stays.
        static let actionToastDuration: TimeInterval = 6
    }

    /// The session transcript.
    enum Sessions {
        static let composerLines = 3
        /// The number of files that the `@` list shows.
        static let fileCompletionLimit = 8
        /// The number of diff lines that an Edit row shows.
        static let diffLineLimit = 12
        /// The space between blocks of a transcript, and the inset of the transcript.
        static let blockSpacing: CGFloat = 10
        static let transcriptInset = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        /// A message of the reader is a bubble. Its corner at the bottom right is small, like a tail.
        static let bubbleRadius: CGFloat = 14
        static let bubbleTailRadius: CGFloat = 4
        static let bubblePadding = EdgeInsets(top: 7, leading: 11, bottom: 7, trailing: 11)
        /// The bubble leaves at least this much of the transcript width empty on its left.
        static let bubbleLeadingSpace: CGFloat = 64
        /// A tool row, a diff, and the fold.
        static let chipRadius: CGFloat = 8
        static let chipPadding = EdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9)
        /// The card of a request that waits.
        static let requestRadius: CGFloat = 10
        static let requestPadding = EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        /// The space around the card of a request, inside the session pane.
        static let requestMargin = EdgeInsets(top: 6, leading: 12, bottom: 0, trailing: 12)
        static let requestSpacing: CGFloat = 3
        /// The space over the diffs and the buttons of a request.
        static let requestSectionSpacing: CGFloat = 5
        static let requestButtonSpacing: CGFloat = 6
        static let requestDetailFontSize: CGFloat = 11.5
        static let requestDetailLineLimit = 6
        /// The agent, model, and mode menus in the composer footer.
        static let footerMenuSpacing: CGFloat = 2
        static let footerAgentSpacing: CGFloat = 3
        static let footerFontSize: CGFloat = 11
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

    var readerSize: Double {
        get { defaults.object(forKey: Key.readerSize) as? Double ?? Reader.defaultSize }
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
