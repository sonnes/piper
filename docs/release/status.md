---
title: "Capability Status"
summary: "What Piper implements, the tests or checks behind each feature, and the known gaps"
read_when:
  - Checking whether a feature exists
  - Choosing release validation work
---

# Capability Status

This table describes the source on September 15, 2026. Implemented means that the code exists and has the evidence shown. It does not mean that the feature is ready for distribution. Test names refer to files under `Tests/`.

## Capture

| Capability | Status | Evidence or limit |
| --- | --- | --- |
| Notes, sections, and search in Today | Implemented | `CaptureStoreTests`, `ReleaseTests`, `UnifiedStreamTests` (search) |
| Merge, copy as list, done, move, delete, and one-step undo | Implemented | `CaptureStoreTests` |
| Capture field draft that survives a restart | Implemented | Stored in UserDefaults. No automated test. |
| Note editing in a sheet, a window, or in place | Implemented | `ReleaseTests` (editor conflict), `QuitSafetyTests`. In-place saving has no automated test. |
| Command-1, New Capture, and the menu bar item open the capture field of Today | Implemented | `PaperDeskTests` (New Capture). The keys and the menu bar item are not checked in the app. |
| Selection capture with double Shift or Control-Option-Space | Implemented, compatibility unverified | `PiperTests` (gesture), `ReleaseTests` (selection range). The app matrix in [Validate a build](validate.md) is open. |
| Arbitrary capture shortcut | Not implemented | Two presets only |
| Capture Clipboard | Implemented | `ReleaseTests`, `CaptureStoreTests` |
| Clipboard history: 50 texts for 7 days in SQLite, with time and source app, in the tray of Today, with Keep, Done with Undo, and Clear Clipboard History | Implemented | `ClipboardInboxTests` in `CapturesTests` and `PiperTests`, `TodayModelTests` |
| Source URL from the source app | Partial | Only when the app exposes an HTTP or HTTPS `AXDocument` value, or an `AXURL` value on its web area |
| Highlight a web page, add a note, or save the page with double Shift | Implemented, compatibility unverified | `ReadingTests` (one article for each page, comments, canonical links), `NoteAnchorTests` (browser quotes). Not checked in Safari, Chrome, or Arc with Accessibility access. |
| Page text for a page behind a login | Implemented, compatibility unverified | `ReadingTests` (pages table), `ArticleReaderTests` (page text to article). The text marker attributes are not checked in a browser. |
| Share menu extension | Not implemented | See [Release readiness](readiness.md) |
| Local SQLite persistence | Implemented | `CaptureStoreTests`, `ReleaseTests` (locked database, invalid records, unknown version, stale writer) |
| Image and file attachments | Not implemented | Text only |

## Agent Sessions

| Capability | Status | Evidence or limit |
| --- | --- | --- |
| Skill discovery from `.claude/skills` | Implemented | `FolderSkillTests` |
| Sessions over stream-json input and output, with turns, resume after a stop or a restart, stop, turn timeout, and a limit of two turns | Implemented | `SessionRunnerTests` with a script in place of `claude`. A spike against Claude Code 2.1.276 confirmed the protocol. |
| The approval drawer with the options of the agent, and question cards for `AskUserQuestion` | Implemented | `SessionRunnerTests`, `ACPAgentTests`, `SessionHelperTests`. The drawer has no automated UI test. |
| ACP agents over stdio: `initialize`, `session/new`, `session/load` with no replay, `session/resume`, prompts, permission requests, cancel, modes, and models | Implemented | `ACPAgentTests` and `ACPMessageTests` with a script in place of the agent. A spike against OpenCode 1.2.27 confirmed `initialize` and `session/new`. Not checked with a full turn of a real ACP agent. |
| Settings > AI: agent health, Add ACP Agent, and the defaults of sessions and margin answers | Implemented | `AgentProbeTests`. The tab has no automated UI test. |
| Tool calls of a finished turn in one line, by tool kind | Implemented | `TranscriptFoldTests` |
| The JSON stream parser, allow rules, the diff, and `@` mentions | Implemented | `SessionEventTests`, `SessionHelperTests` |
| Sessions stored across restarts | Implemented | `SessionsTableTests`, `SessionRunnerTests` |
| The session card, its pill and detached panel, the Agents tab, and the session list | Implemented | `SessionCardTests`. The views have no automated UI test. |
| Send from a row of Today, the selection bar, and Command-Shift-Return | Implemented | `FolderAgentsTests`. The buttons have no automated UI test. |
| Slash commands in the composer | Implemented | `SlashCommandTests`, `FolderAgentsTests`. The skill list has no automated UI test. |
| Control-Option-W and the toast Send button | Implemented | Manual checks only |
| A per-session agent, model, and mode | Implemented | `ACPAgentTests`. The composer menus have no automated UI test. |
| Interrupt a turn and keep the process | Partial | An ACP agent keeps its process after Stop (`ACPAgentTests`). Claude Code ends its process, and the next message resumes the session. |
| Margin answers that read files and the web, and change nothing | Implemented | `ACPMessageTests` (the tools of Claude Code), `ACPAgentTests` (allows reads, denies edits) |
| A notice when a turn ends or needs you | Not implemented | The badges, the count on the Agents tab, and the unread dot change. Piper shows no toast. |

## Papers

| Capability | Status | Evidence or limit |
| --- | --- | --- |
| Feed paper with tabs, an index for each tab, and the scoped list | Implemented | `PaperDeskStateTests` (state, overflow, folder index). Checked in the app with agent-desktop. Keys not checked in the app. |
| Reader papers: placement, cascade, focus of an open item, Escape, and Next Paper | Implemented | `PaperDeskStateTests` (placement, free places), `PaperDeskTests` (the open file). Open, focus, Put Back, and placement checked in the app with agent-desktop. Escape and Command-` not checked in the app. |
| Move, resize, and zoom a paper, and keep its frame | Implemented | `PaperDeskStateTests` (saved frames, the frame limit, the clamp to the screens, the minimum sizes, the resize band and its math, zoom, the double-click setting, the cascade with no saved frame). A real drag of an edge, the pointers, and a change of displays are not checked in the app. |
| A tab for each folder, with its own color | Implemented | `PaperDeskStateTests` (column, colors, stubs), `PaperDeskTests` (active folder on a tab click) |
| Folder tree with any folder structure | Implemented | `VaultTests`, `PaperDeskTests` |
| Automatic refresh on file changes | Implemented | `VaultWatcherTests`, `WikiRefreshTests` |
| Feed parsing: RSS, Atom, RSS-in-JSON, JSON Feed, and OPML | Implemented | `FeedsTests` (the upstream parser tests of NetNewsWire, with their fixtures) |
| Feed subscriptions, refresh, read marks, and the mode of each feed | Implemented | `FeedStoreTests` (conditional GET, failure waits, prune, marks, mode on an old database). Not checked on a real build. |
| Copy of starred articles to kept link captures | Implemented | `StarMigrationTests` (one copy, no undo of the copy) |
| Import of NetNewsWire subscriptions and OPML files | Implemented | `FeedStoreTests` (OPML with folders). Not checked on a real NetNewsWire file. |
| Sources: the feed list with rates and modes, add by address, OPML import, and Sites You Read Often | Implemented | `SourcesTests`, `HistoryTests` (sources, digest, decay, blocked sites), `FeedStoreTests` (feed discovery, suggestions), `PaperDeskTests` (open Sources). Checked in the app with fictional data on November 23, 2026. Import and a real history scan not checked in the app. |
| Vault search across titles, paths, descriptions, and text | Implemented | `WikiWorkspaceTests` (multiple words) |
| Back and forward history | Implemented | `WikiWorkspaceTests` |
| Wiki links and heading anchors | Implemented | `WikiWorkspaceTests`, `WikiEditingTests`, `web/test/paths.test.ts` |
| Markdown editing with automatic save | Implemented | `WikiEditingTests`, `EditorPageTests`, `QuitSafetyTests` |
| Frontmatter kept through a save | Implemented | `EditorPageTests`, `FrontmatterTests` |
| Conflict with a change on disk | Implemented | `WikiEditingTests`, `WikiRefreshTests`, `QuitSafetyTests` |
| Read-only Preview for syntax that a save would drop | Implemented | `web/test/lossGuard.test.ts`, `EditorPageTests` |
| Source editing for Markdown, read-only source for HTML | Implemented | `EditorPageTests`, `FilePreviewTests`, `SourceViewTests` (line wrap) |
| Pasted images and HTML embeds | Implemented | `WikiEditingTests` (image files, asset scheme). Image paste checked in the app. Embeds not checked in the app. |
| Command palette | Implemented | `PaletteSearchTests`, `CommandPaletteTests` |
| Selection bar and margin cards in a file | Implemented | `EditorPageTests`, `web/test/highlight.test.ts`, `web/test/readerLayer.test.ts`. Ask, Explain, and Define not checked in the app. |
| Previews for non-Markdown files | Implemented | `FilePreviewTests` |
| Markdown rendering | Partial | The Hubble.md editor with GFM. Link titles and table alignment open read-only. |
| Add and remove folders | Implemented | `WikiFoldersTests` |
| Find in the open file | Implemented | The find bar of the editor. Not checked in the app. |
| Create a new folder from the UI | Not implemented | None |
| Concurrent external edits | Partial | A three-way compare before each save. No shared lock. |

## Today And The Reader

| Capability | Status | Evidence or limit |
| --- | --- | --- |
| Web links in captures | Implemented | `CaptureLinksTests`, `ReleaseTests` (source URLs). Manual checks for redirects, history, new-window links, edits, and failed loads. |
| Capture from a web page | Implemented | Manual checks for selected text, page text, source metadata, empty pages, and the Capture button |
| Reader tab with highlights and questions | Partial | `CaptureStoreTests` (child notes), `NoteAnchorTests` (anchors and threads). The reader page was checked in WebKit on sqlite.org and paulgraham.com. Not checked in the app window with Claude Code answers. |
| Notes on highlights, reading position, and progress | Implemented | `ReadingTests` (reading state, comments). The reader page was checked in Chrome with sample notes. The saved position is not checked in the app window. |
| Today: notes, links, articles, digests, and clipboard texts in one list, with lenses, day groups, and section scopes | Implemented | `UnifiedStreamTests` (merge, dedupe, lenses, states, expiry, day groups, search), `ReadingTests`. Checked in the app with fictional data on November 23, 2026. |
| Digest rows and the Every post, Best, Digest, and Off modes, with a local relevance score | Implemented | `UnifiedStreamTests` (digest grouping, modes, Best, score order, relevance, stats). Checked in the app with fictional data. |
| Row verbs: Keep, Done with Undo, File, and Send, as buttons, keys, and menu items | Implemented | `TodayModelTests` (each verb, Undo, File into a section, a folder, and a file). Keep, Done, and File checked in the app with agent-desktop. The keys need the user. |
| Selection of several rows and the selection bar | Implemented | `TodayModelTests` (selection, merge, copy). Rendered offscreen. Command-click needs the user. |
| Notes tab, Save as File, and Update File | Implemented | `ReadingTests` (Markdown file and update). Rendered offscreen. Not checked in the app window. |
| Text style popover and Summary in the Reader tab | Not implemented | The reader has one font, one size, and no summary |

## Distribution

| Capability | Status | Evidence or limit |
| --- | --- | --- |
| Developer ID signing and notarization | Verified for 0.1.1 | Apple accepted the 0.1.1 arm64 DMG on September 22, 2026. Stapling and Gatekeeper checks passed. |
| Installation on a clean Mac | Open | See [Release readiness](readiness.md) |
