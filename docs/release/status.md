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
| Clipboard history: 50 texts with time and source app, Keep to Inbox, Clear History | Implemented | `ClipboardInboxTests` in `CapturesTests` and `PiperTests` |
| Source URL from the source app | Partial | Only when the app exposes an HTTP or HTTPS `AXDocument` value |
| Local SQLite persistence | Implemented | `CaptureStoreTests`, `ReleaseTests` (locked database, invalid records, unknown version, stale writer) |
| Image and file attachments | Not implemented | Text only |

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

## Distribution

| Capability | Status | Evidence or limit |
| --- | --- | --- |
| Developer ID signing and notarization | Verified for 0.1.0 | Apple accepted the 0.1.0 arm64 DMG on September 12, 2026. Stapling and Gatekeeper checks passed. That build is older than the current source. |
| Installation on a clean Mac | Open | See [Release readiness](readiness.md) |
