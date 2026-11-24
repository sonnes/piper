import Foundation

/// The preference keys of the application. A feature keeps its sizes, times,
/// and colors in a `Metrics` enum next to its views.
enum AppDefaults {
    enum Key {
        static let vaultPath = "wikiPath"
        /// The titles of the palette commands that the reader ran last.
        static let paletteRecents = "paletteRecents"
        static let wikiPaths = "wikiPaths"
        static let captureShortcut = "captureShortcut"
        static let composerDraft = "composerDraft"
        static let showsFileSource = "showsFileSource"
        /// Turns on the QA hooks of a debug build. See `QA`.
        static let qaMode = "PiperQA"
        /// The file where `QAScripts` writes the result of a script.
        static let qaResultPath = "PiperQAResult"
        /// The `host:port` of an HTTP proxy for the web views of `QAScripts`, so fictional hosts load from a local server.
        static let qaProxy = "PiperQAProxy"

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
        static let siteScanDate = "siteScanDate"
        /// What the feed paper restores when it opens again. See `PaperDeskState`.
        static let paperDeskState = "paperDeskState"
        /// The frame of each reader paper, by its item.
        static let readerFrames = "readerFrames"
        /// The frame autosave name of the detached session panel.
        static let sessionPanelFrame = "PiperSessionPanel"
    }
}
