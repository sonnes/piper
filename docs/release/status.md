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
| Composer draft that survives a restart | Implemented | Stored in UserDefaults. No automated test. |
| Note editing with Save Changes | Implemented | `ReleaseTests` (editor conflict), `QuitSafetyTests` |
| Selection capture with double Shift or Control-Option-Space | Implemented, compatibility unverified | `PiperTests` (gesture), `ReleaseTests` (selection range). The app matrix in [Validate a build](validate.md) is open. |
| Arbitrary capture shortcut | Not implemented | Two presets only |
| Capture Clipboard | Implemented | `ReleaseTests`, `CaptureStoreTests` |
| Clipboard cards: paste on click, save on Command-click | Implemented | `ClipboardInboxTests` in `CapturesTests` and `PiperTests` |
| Source URL from the source app | Partial | Only when the app exposes an HTTP or HTTPS `AXDocument` value |
| Local SQLite persistence | Implemented | `CaptureStoreTests`, `ReleaseTests` (locked database, invalid records, unknown version, stale writer) |
| Image and file attachments | Not implemented | Text only |

## Wiki Window

| Capability | Status | Evidence or limit |
| --- | --- | --- |
| Folder tree with any folder structure | Implemented | `VaultTests`, `PathTreeBuilderTests`, `TreeControllerTests` |
| Automatic refresh on file changes | Implemented | `VaultWatcherTests`, `WikiRefreshTests` |
| Home search with `/` commands and `>` actions | Implemented | `CommandParserTests` |
| Vault search across titles, paths, descriptions, and text | Implemented | `WikiWorkspaceTests` (multiple words) |
| Unread state and folder counts | Implemented | `FileReadStateTests` |
| Back and forward history | Implemented | `WikiWorkspaceTests` |
| Wiki links, heading anchors, and backlinks | Implemented | `WikiWorkspaceTests`, `WikiEditingTests` |
| Markdown editing with explicit save | Implemented | `WikiEditingTests`, `QuitSafetyTests` |
| Frontmatter bytes kept through a save | Implemented | `WikiEditingTests`, `FrontmatterTests` |
| Refusal to overwrite an external change | Implemented | `WikiEditingTests`, `PiperTests` |
| Previews for non-Markdown files | Implemented | `FilePreviewTests` |
| Markdown rendering | Partial | SwiftMarkdownEngine 0.12.0 with strikethrough. Not full CommonMark. |
| Find in the open file | Not implemented | Command-F does nothing in the Wiki window |
| Focus mode | Not implemented | The Focus action in the inspector does nothing |
| Create a new Wiki from the UI | Not implemented | `Vault.create()` exists and has tests, but no UI calls it |
| Concurrent external edits | Partial | A byte compare detects most changes. No shared lock. |

## Inbox Reader

| Capability | Status | Evidence or limit |
| --- | --- | --- |
| Web links in captures | Implemented | `CaptureLinksTests`, `ReleaseTests` (source URLs). Manual checks for redirects, history, new-window links, edits, and failed loads. |
| Capture from a web page | Implemented | Manual checks for selected text, page text, source metadata, empty pages, and the Capture button |

## Export And Commands

| Capability | Status | Evidence or limit |
| --- | --- | --- |
| Send to Wiki as one Markdown file | Implemented | `PiperTests` (one file, bad input, file names), `QuitSafetyTests` (export blocks quit) |
| Commands and skills through Claude Code | Implemented | `CommandIndexTests`, `SkillIndexTests`, `SymlinkedScopeTests`, `WikiAgentJobTests`. The `claude` process itself has no automated test. |

## Distribution

| Capability | Status | Evidence or limit |
| --- | --- | --- |
| Developer ID signing and notarization | Verified for 0.1.0 | Apple accepted the 0.1.0 arm64 DMG on September 12, 2026. Stapling and Gatekeeper checks passed. That build is older than the current source. |
| Installation on a clean Mac | Open | See [Release readiness](readiness.md) |
