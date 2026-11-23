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
        /// The titles of the palette commands that the reader ran last.
        static let paletteRecents = "paletteRecents"
        static let wikiPaths = "wikiPaths"
        static let captureShortcut = "captureShortcut"
        static let captureFloating = "captureFloating"
        static let composerDraft = "composerDraft"
        static let migratedLocalPreferences = "migratedLocalPreferences"
        static let accessibilityTipDismissed = "accessibilityTipDismissed"
        /// True when the reader folded the clipboard strip of the capture panel.
        static let clipboardStripFolded = "clipboardStripFolded"
        static let showsFileSource = "showsFileSource"
        /// Turns on the QA hooks of a debug build. See `QA`.
        static let qaMode = "PiperQA"
        /// The file where `QAScripts` writes the result of a script.
        static let qaResultPath = "PiperQAResult"

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
        /// The height that the reader gave the session card.
        static let sessionCardHeight = "sessionCardHeight"
        /// The pill, the card, or the detached panel.
        static let sessionPresentation = "sessionPresentation"
        /// The folder that Save as File used last.
        static let articleExportFolder = "articleExportFolder"
        static let siteTabs = "articleSiteTabs"
        static let blockedSites = "blockedSites"
        static let disabledHistorySources = "disabledHistorySources"
        static let discoverLastScan = "discoverLastScan"
        /// The tab, the scope, the pins, and the frame of the feed paper. See `PaperDeskState`.
        static let paperDeskState = "paperDeskState"

        /// Keys carried over when the bundle identifier changed to `com.piper`.
        static let migrated = [
            vaultPath, captureShortcut, composerDraft, readerSize,
            "NSWindow Frame " + WindowName.capturePanel
        ]
    }

    /// Frame autosave names. A window controller reads its own name from here.
    enum WindowName {
        static let capturePanel = "PiperCapturePanel"
        static let sessionPanel = "PiperSessionPanel"
    }

    // MARK: Sizes

    /// The feed paper and the reader papers. The sizes of a reader paper come
    /// from the Write paper of September: a text column of 600 points with
    /// 56-point margins at the sides.
    enum Papers {
        /// The number of tabs on the edge of the feed paper. Pinned folders past this number show on the Folders index.
        static let tabLimit = 8
        static let feedSize = NSSize(width: 520, height: 760)
        static let feedMinimumSize = NSSize(width: 420, height: 440)
        static let readerSize = NSSize(width: 712, height: 860)
        static let noteSize = NSSize(width: 440, height: 420)
        static let sessionSize = NSSize(width: 480, height: 680)
        static let readerMinimumSize = NSSize(width: 380, height: 320)
        static let cornerRadius: CGFloat = 20
        /// The space around a paper in its window, for the shadow of the paper.
        static let shadowMargin = NSEdgeInsets(top: 16, left: 24, bottom: 36, right: 24)
        static let shadowInsets = EdgeInsets(top: shadowMargin.top, leading: shadowMargin.left,
                                             bottom: shadowMargin.bottom, trailing: shadowMargin.right)
        /// The card shadow of the paper with the keyboard focus: `0 8px 24px` in the mock.
        static let focusShadow = (radius: CGFloat(12), y: CGFloat(8))
        /// The shadow of another paper: `0 3px 12px` in the mock.
        static let restShadow = (radius: CGFloat(6), y: CGFloat(3))
        /// The thin line under the focused paper: `0 1px 0` in the mock.
        static let edgeShadowY: CGFloat = 1
        /// The tilts of the reader papers without the keyboard focus, in degrees, in the order the papers open.
        static let tilts: [CGFloat] = [-0.5, 0.45, -0.3, 0.6]
        /// The opacity of the content of a reader paper without the keyboard focus.
        static let restOpacity = 0.72
        /// A paper rises by this distance as it fades in.
        static let rise: CGFloat = 14
        /// The time of the flash of a row when its paper goes back.
        static let flash: Double = 1.4
        /// The space between the feed paper and the first reader paper.
        static let gap: CGFloat = 24
        /// The offset of each next reader paper, to the right and down.
        static let cascade: CGFloat = 24
        /// The number of places in the cascade before it starts again.
        static let cascadeSteps = 6
        /// The space that a paper keeps from the edges of the screen.
        static let screenInset: CGFloat = 24
        /// The cross-fade between the index and the list.
        static let fade: Double = 0.22

        static let tabWidth: CGFloat = 150
        static let activeTabWidth: CGFloat = 164
        static let tabHeight: CGFloat = 40
        static let tabSpacing: CGFloat = 6
        /// The part of a tab that lies under the paper.
        static let tabOverlap: CGFloat = 14
        static let tabCornerRadius: CGFloat = 14
        /// The space between the top of the paper and the first tab.
        static let tabsTop: CGFloat = 74
        /// The extra space over the first pinned folder.
        static let pinGap: CGFloat = 10
        static let tabShadowRadius: CGFloat = 2
        static let activeTabShadowRadius: CGFloat = 2.5
        /// The dashed + Folder tab at the end of the column.
        static let addTabWidth: CGFloat = 132
        static let tabShadowOffset: CGFloat = 1

        /// The smallest scale of the title of the feed paper before it truncates.
        static let titleMinimumScale: CGFloat = 0.7
        static let headerPadding = EdgeInsets(top: 28, leading: 32, bottom: 0, trailing: 24)
        static let indexPadding = EdgeInsets(top: 16, leading: 20, bottom: 20, trailing: 20)
        /// A group header of an index, such as Sections.
        static let indexHeaderPadding = EdgeInsets(top: 12, leading: 12, bottom: 4, trailing: 12)
        /// The folder outline of a row of an index.
        static let folderMark = CGSize(width: 15, height: 11)
        static let rowHeight: CGFloat = 48
        static let rowRadius: CGFloat = 12
        static let rowPadding: CGFloat = 12
        static let indent: CGFloat = 18
        static let iconSize: CGFloat = 18
        static let readerHeaderHeight: CGFloat = 48
        /// The grip of a reader paper. Its text starts at the side margin of the article.
        static let readerHeaderPadding = EdgeInsets(top: 14, leading: 56, bottom: 0, trailing: 16)
        /// The grip of a note paper, which has narrower margins.
        static let noteHeaderPadding = EdgeInsets(top: 14, leading: 28, bottom: 0, trailing: 16)
        static let noteBodyPadding = EdgeInsets(top: 4, leading: 28, bottom: 24, trailing: 28)
        /// The extra space between the lines of a note, for a line height of 1.6 at 18 points.
        static let noteLineSpacing: CGFloat = 4.5
        static let noteFootPadding = EdgeInsets(top: 10, leading: 28, bottom: 14, trailing: 20)
        /// A row of a list: a column for the mark, then the text and the time.
        static let listRowPadding = EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 20)
        static let listPadding = EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12)
        static let markColumn: CGFloat = 24
        static let rowLineHeight: CGFloat = 26
        /// The space between the lines of a title, for a line height of 26.
        static let rowLineSpacing: CGFloat = 4
        static let rowSpacing: CGFloat = 10
        /// The serif title of an article or a file in a list.
        static let serifRowSize: CGFloat = 17.5
        /// The quote of a note under a row.
        static let quoteSize: CGFloat = 15.5
        static let tickSize: CGFloat = 18
        static let dotSize: CGFloat = 9
        static let markLine: CGFloat = 1.5
        static let sheetMark = NSSize(width: 12, height: 15)
        static let selectionBarWidth: CGFloat = 3
        static let selectionBarInset: CGFloat = 8
        static let slotDash: [CGFloat] = [4, 3]
        static let groupHeaderPadding = EdgeInsets(top: 14, leading: 20, bottom: 2, trailing: 20)
        /// The notes under a row: the last two, then a count of the others.
        static let rowNoteLimit = 2
        static let rowNotesPadding = EdgeInsets(top: 8, leading: 12, bottom: 2, trailing: 0)
        static let quoteBarWidth: CGFloat = 2
        /// The capture field on the first line of the feed paper.
        static let composerHeight: CGFloat = 48
        static let composerPadding = EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20)
        static let composerTextInset: CGFloat = 40
        static let focusRingWidth: CGFloat = 3
        /// The line under the list with the latest copy of the clipboard.
        /// The strip of keys at the bottom of the screen.
        static let hintBottom: CGFloat = 18
        static let hintHeight: CGFloat = 40
        static let footPadding = EdgeInsets(top: 12, leading: 12, bottom: 10, trailing: 12)
        static let footMargin: CGFloat = 20
        /// The most a count on a tab shows. A larger count shows as this number and a plus sign.
        static let countLimit = 999
    }

    enum ListSearch {
        static let horizontalInset: CGFloat = 12
        static let verticalInset: CGFloat = 8
    }

    /// The icon at the start of a row.
    enum RowIcon {
        static let size: CGFloat = 18
        /// The corner radius of a tile, as a fraction of its side.
        static let tileCornerFraction: CGFloat = 0.28
        /// The diameter of a section dot, as a fraction of the icon side.
        static let dotFraction: CGFloat = 0.55
        /// The size of the symbol in a tile, as a fraction of its side.
        static let tileSymbolFraction: CGFloat = 0.62
    }

    /// The Feeds index, the article list, and Discover.
    enum Feeds {
        static let headerHeight: CGFloat = 38
        static let unreadDot: CGFloat = 7
        static let articleIconSize: CGFloat = 12
        static let addSheetWidth: CGFloat = 460
        static let discoverRowSpacing: CGFloat = 2
        /// Discover scans again when it opens, if the last scan is older than this.
        static let discoverInterval: TimeInterval = 86_400
        static let discoverParallelSites = 4
        static let settingsSize = NSSize(width: 600, height: 560)
    }

    enum Window {
        static let captureSettingsSize = NSSize(width: 560, height: 380)
        static let capturePanelSize = NSSize(width: 600, height: 960)
        static let capturePanelMinimumSize = NSSize(width: 340, height: 480)
        static let captureCornerRadius: CGFloat = 22
    }

    /// The command palette over a paper.
    enum Palette {
        static let size = NSSize(width: 560, height: 380)
        /// The space between the top of the paper and the palette.
        static let topInset: CGFloat = 90
        static let cornerRadius: CGFloat = 12
        static let queryFontSize = PiperTheme.TextSize.title
        static let fileLimit = 20
        static let commandLimit = 4
        static let recentLimit = 8
    }

    /// The Markdown editor in the file paper.
    enum Editor {
        /// Seconds after a Piper session wrote a file during which a change on
        /// disk names the session as its source.
        static let sessionWriteWindow: TimeInterval = 600
    }

    enum Reader {
        static let horizontalInset: CGFloat = 48
        static let topInset: CGFloat = 20
        /// The space over the byline at the top of a Markdown file.
        static let headerTopInset: CGFloat = 36
        /// The heading sizes of the reader page: 30, 21, and 18 points over a 16.5-point body.
        static let headingMultipliers: [CGFloat] = [1.8, 1.27, 1.1, 1, 1, 1]
        /// The extra line height as a part of the font size. The reader page uses a line height of 1.6.
        static let lineSpacing: CGFloat = 0.4
        static let defaultFont = WikiReadingFont.serif
        static let defaultSize = 18.0
        static let footnoteBaselineOffset: CGFloat = 6

        static let columnWidth: CGFloat = 640
        static let codeFontSize: CGFloat = 13
    }

    /// The Reader tab of a link capture.
    enum ArticleReader {
        /// The distance that Up Arrow or Down Arrow scrolls the Reader tab.
        static let arrowScrollStep: CGFloat = 40
        /// Seconds before Piper reads a page that has not finished loading.
        static let loadTimeout: Double = 20
        /// The wait after a load, for a page that draws its text with a script.
        static let settleMilliseconds = 300
        static let wordsPerMinute: Double = 230
        static let horizontalInset: CGFloat = 16
        /// The line over the article that says where it opened.
        static let resumeVerticalPadding: CGFloat = 10
        static let resumeMargin: CGFloat = 40
        /// The space between the Show Web Page button and the tabs under it.
        static let webPageButtonMargin: CGFloat = 16
        /// The size of the hidden web view that loads a page.
        static let loaderSize = NSSize(width: 1024, height: 768)
    }

    /// The session card in the corner of a reader paper, and its detached panel.
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
        /// The part of the reader paper that the card can cover at most.
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

    /// The tabs that float over the bottom of a reader paper.
    enum TabIsland {
        static let segmentHeight: CGFloat = 32
        static let segmentPadding: CGFloat = 14
        /// The space between the capsule and the segments.
        static let inset: CGFloat = 3
        static let shadowRadius: CGFloat = 5
        static let shadowOffset: CGFloat = 2
        static let bottomMargin: CGFloat = 14
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
        /// The column of the Notes tab.
        static let notebookWidth: CGFloat = 600
        /// The wait after the last scroll before Piper saves the position.
        static let positionSaveDelay = Duration.milliseconds(800)
        /// The part of the article above the screen that counts as finished.
        static let finishedProgress = 0.97
    }

    /// The Notes tab of a link capture, and its Save as File popover.
    enum Notebook {
        static let horizontalPadding: CGFloat = 56
        static let topPadding: CGFloat = 8
        static let summaryMinimumHeight: CGFloat = 70
        /// The serif of a quote: 17 points, with a line height of 1.55.
        static let quoteFontSize: CGFloat = 17
        static let quoteLineSpacing: CGFloat = 5
        /// The padding and the corner radius of the summary field, a question, and the file preview.
        static let fieldPadding: CGFloat = 10
        static let fieldRadius: CGFloat = 12
        static let labelTopPadding: CGFloat = 22
        static let colorBarWidth: CGFloat = 2
        static let formWidth: CGFloat = 360
        static let formPadding: CGFloat = 14
        static let previewHeight: CGFloat = 140
        static let previewFontSize: CGFloat = 11
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

    /// A row of the Inbox stream on the feed paper.
    enum InboxRow {
        static let controlSize: CGFloat = 18
        /// The column that holds the circle or the ring.
        static let controlColumn: CGFloat = 26
        static let columnSpacing: CGFloat = 8
        /// The space from the edge of the row to the text.
        static let textInset: CGFloat = padding.leading + controlColumn + columnSpacing
        static let padding = EdgeInsets(top: 9, leading: 8, bottom: 10, trailing: 10)
        static let cornerRadius: CGFloat = 8
        static let titleFontSize = PiperTheme.TextSize.body
        static let metaFontSize = PiperTheme.TextSize.secondary
        static let codeFontSize: CGFloat = 12
        static let sectionDot: CGFloat = 7
    }

    /// A highlight or a question under a link capture in the list.
    enum ChildNote {
        static let fontSize = PiperTheme.TextSize.body.rawValue
        static let lineSpacing: CGFloat = 1.5
        static let ruleWidth: CGFloat = 2
        static let tagFontSize = PiperTheme.TextSize.caption
        static let tagHeight: CGFloat = 16
        static let swatchSize: CGFloat = 7
    }

    /// Capture list metrics, shared by the panel and the Inbox pane.
    enum CaptureItem {
        static let cornerRadius: CGFloat = PiperTheme.cardRadius
        static let fontSize = PiperTheme.TextSize.body
        static let clipboardFontSize = PiperTheme.TextSize.body
        static let clipboardCodeFontSize: CGFloat = 12
        static let lineSpacing: CGFloat = 2
        static let circleSize: CGFloat = 18
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
        static let verticalPadding: CGFloat = 7
        static let minimumHeight: CGFloat = 32
        /// The height of a row in the clipboard strip of the panel.
        static let stripRowHeight: CGFloat = 26
        /// The height of a count chip, such as "2 notes".
        static let chipHeight: CGFloat = 18
        static let clipboardHeight: CGFloat = 42
        /// The space from the edge of a card to the text after the circle.
        static let textInset: CGFloat = horizontalPadding + buttonHitSize + 10
        /// The inset of the list from the edge of the pane.
        static let listInset: CGFloat = 14
        /// Lifts the panel hint line clear of the rounded bottom corners.
        static let hintBottomPadding: CGFloat = 6
        /// The number of clipboard items in the strip under the panel list.
        static let recentClipboardCount = 3
        /// The number of sections that show as tabs in the panel. The menu tab holds the others.
        static let sectionTabCount = 3
    }

    /// Composer metrics.
    ///
    /// The height of the card follows from the line height. A whole number of
    /// lines is therefore visible, and no line is cut at the bottom edge.
    enum Composer {
        /// The font of the add field.
        static let inboxFontSize = PiperTheme.TextSize.body
        /// The font of the session composer.
        static let fontSize = PiperTheme.TextSize.reading
        /// The most lines that the add field shows before it scrolls.
        static let maxLines = 5
        static let inboxLineHeight: CGFloat = 18
        /// The line and the insets of the capture field of the feed paper, 48 points high with one line.
        static let paperLineHeight: CGFloat = 22
        static let paperTextInset = NSSize(width: 0, height: 13)
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
        static let captureCompletionLimit = 4
        /// The files that Piper reads for the `@` list of a folder that is not on the Folders index.
        static let folderFileLimit = 5000
        /// The characters of a note or a title in a context chip or a mention.
        static let contextLabelLimit = 40
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
