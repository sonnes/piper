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
| Notes, sections, and search in the capture panel | Implemented | `CaptureStoreTests`, `ReleaseTests` |
| Merge, copy as list, done, move, delete, and one-step undo | Implemented | `CaptureStoreTests` |
| One list for every section, with tabs that scroll to a section | Implemented | Manual checks in [Validate a build](validate.md). No automated UI test. |
| Composer draft that survives a restart | Implemented | Stored in UserDefaults. No automated test. |
| Note editing in a sheet, a window, or in place | Implemented | `ReleaseTests` (editor conflict), `QuitSafetyTests`. In-place saving has no automated test. |
| Selection capture with double Shift or Control-Option-Space | Implemented, compatibility unverified | `PiperTests` (gesture), `ReleaseTests` (selection range). The app matrix in [Validate a build](validate.md) is open. |
| Arbitrary capture shortcut | Not implemented | Two presets only |
| Capture Clipboard | Implemented | `ReleaseTests`, `CaptureStoreTests` |
| Clipboard history: 50 texts for 7 days in SQLite, with time and source app, Keep to Inbox, Clear History | Implemented | `ClipboardInboxTests` in `CapturesTests` and `PiperTests` |
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
| The session card, its pill and detached panel, the Sessions sidebar group, and the session list | Implemented | `MainWindowState` covered by `WikiRefreshTests`. The views have no automated UI test. |
| Send from a note, a clipboard row, the selection bar, and Command-Shift-Return | Implemented | `FolderAgentsTests`. The buttons have no automated UI test. |
| Slash commands in the composer | Implemented | `SlashCommandTests`, `FolderAgentsTests`. The skill list has no automated UI test. |
| Control-Option-W and the toast Send button | Implemented | Manual checks only |
| A per-session agent, model, and mode | Implemented | `ACPAgentTests`. The composer menus have no automated UI test. |
| Interrupt a turn and keep the process | Partial | An ACP agent keeps its process after Stop (`ACPAgentTests`). Claude Code ends its process, and the next message resumes the session. |
| Margin answers that read files and the web, and change nothing | Implemented | `ACPMessageTests` (the tools of Claude Code), `ACPAgentTests` (allows reads, denies edits) |
| A notice when a turn ends or needs you | Not implemented | The badges, the sidebar count, and the unread dot change. Piper shows no toast. |

## Main Window

| Capability | Status | Evidence or limit |
| --- | --- | --- |
| Folder tree with any folder structure | Implemented | `VaultTests`, `PathTreeBuilderTests`, `TreeControllerTests` |
| Automatic refresh on file changes | Implemented | `VaultWatcherTests`, `WikiRefreshTests` |
| Home file search and `>` actions | Implemented | `HomeSearchTests` |
| Vault search across titles, paths, descriptions, and text | Implemented | `WikiWorkspaceTests` (multiple words) |
| Unread state and folder counts | Implemented | `FileReadStateTests` |
| Back and forward history | Implemented | `WikiWorkspaceTests` |
| Wiki links and heading anchors | Implemented | `WikiWorkspaceTests`, `WikiEditingTests` |
| Markdown editing with explicit save | Implemented | `WikiEditingTests`, `QuitSafetyTests` |
| Frontmatter bytes kept through a save | Implemented | `WikiEditingTests`, `FrontmatterTests` |
| Refusal to overwrite an external change | Implemented | `WikiEditingTests`, `PiperTests` |
| Source view for Markdown and HTML | Implemented | `FilePreviewTests` (unsaved Markdown edits), `SourceViewTests` (line wrap) |
| Previews for non-Markdown files | Implemented | `FilePreviewTests` |
| Markdown rendering | Partial | SwiftMarkdownEngine 0.12.0 with strikethrough. Not full CommonMark. |
| Add and remove folders | Implemented | `WikiFoldersTests` |
| Find in the open file | Not implemented | Command-F does nothing in the main window |
| Create a new Wiki from the UI | Not implemented | `Vault.create()` exists and has tests, but no UI calls it |
| Concurrent external edits | Partial | A byte compare detects most changes. No shared lock. |

## Inbox Reader

| Capability | Status | Evidence or limit |
| --- | --- | --- |
| Web links in captures | Implemented | `CaptureLinksTests`, `ReleaseTests` (source URLs). Manual checks for redirects, history, new-window links, edits, and failed loads. |
| Capture from a web page | Implemented | Manual checks for selected text, page text, source metadata, empty pages, and the Capture button |
| Reader tab with highlights and questions | Partial | `CaptureStoreTests` (child notes), `NoteAnchorTests` (anchors and threads). The reader page was checked in WebKit on sqlite.org and paulgraham.com. Not checked in the app window with Claude Code answers. |
| Notes on highlights, reading position, and progress | Implemented | `ReadingTests` (reading state, comments). The reader page was checked in Chrome with sample notes. The saved position is not checked in the app window. |
| Inbox stream with day groups, chips, and section filters | Implemented | `InboxStreamTests`, `ReadingTests` (groups, archive after seven days). Rendered offscreen. Not checked in the app window. |
| Continue Reading on Home | Implemented | `ReadingTests`. Rendered offscreen. Not checked in the app window. |
| Notes tab, Save as File, and Update File | Implemented | `ReadingTests` (Markdown file and update). Rendered offscreen. Not checked in the app window. |
| Text style popover and Summary in the Reader tab | Not implemented | The reader has one font, one size, and no summary |

## Distribution

| Capability | Status | Evidence or limit |
| --- | --- | --- |
| Developer ID signing and notarization | Verified for 0.1.1 | Apple accepted the 0.1.1 arm64 DMG on September 22, 2026. Stapling and Gatekeeper checks passed. |
| Installation on a clean Mac | Open | See [Release readiness](readiness.md) |
