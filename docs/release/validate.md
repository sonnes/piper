---
title: "Validate A Build"
summary: "Automated tests and manual acceptance checks for capture, the Wiki window, export, and distribution"
read_when:
  - Testing a build before regular use
  - Recording application compatibility
  - Preparing a release
---

# Validate A Build

Run the automated tests first. Then do the manual checks for the area that changed. Use a disposable Wiki folder for every manual check. Piper has no sample mode.

## Automated Tests

1. Open a terminal in the repository root.
2. Run `make test`.

The tests use temporary folders and temporary databases. Each module has a test target:

| Target | Covers |
| --- | --- |
| `PiperCoreTests` | Frontmatter parsing, line endings, and Home search |
| `PiperTreeTests` | Folder trees and counts |
| `CapturesTests` | The capture store, clipboard entries, and capture links |
| `VaultTests` | Scans, path safety, reads, writes, and the watcher |
| `PiperTests` | The app model: editing, refresh, read state, previews, export, and quit safety |

The tests do not cover the UI or the global shortcut path.

## Capture Checks

1. Run `make run`.
2. Save a note with Return, and edit it with Save Changes.
3. Copy text in another app, then Command-click its card in the panel.
4. Click another clipboard card, and make sure that the text pastes into the app in front.
5. Select notes, then use Merge, Move, Copy as List, and Undo.
6. Restart Piper.
7. Make sure that the notes, sections, and composer draft are still there.

## Selection Capture Checks

Before you start, allow Accessibility access. For each app in the table, do these steps:

1. Select text, then press Shift twice.
2. Make sure that the note has the exact text and the source app.
3. Make sure that the clipboard and the focus did not change.
4. Try an empty selection and a secure field. Make sure that no note appears.
5. Repeat with Control-Option-Space.

| Application | Text selection | Empty selection | Secure field | Focus kept | Result |
| --- | --- | --- | --- | --- | --- |
| Safari | Pending | Pending | Pending | Pending | Pending |
| Chrome | Pending | Pending | Pending | Pending | Pending |
| TextEdit | Pending | Pending | Pending | Pending | Pending |
| Terminal | Pending | Pending | Pending | Pending | Pending |

Record the macOS version, the app version, and the permission state with each result. No row claims compatibility yet.

Automated keystrokes go directly to an app. They do not test the macOS hotkey path or the double Shift gesture.

## Wiki Window Checks

1. Choose a disposable Wiki folder in the folder menu.
2. Add, rename, and delete a file in Finder. Make sure that the tree and the file list update.
3. Search from Home and from the toolbar.
4. Open a file. Make sure that its unread dot goes away.
5. Follow a Wiki link, then use Command-[ and Command-].
6. Switch Markdown and HTML files between Preview and Raw. Make sure that Raw shows their source text.
7. Open a JSON file, an image, and a PDF. Make sure that each one shows a preview.

## Editing Checks

1. Edit a Markdown file that has frontmatter.
2. Make sure that the status bar shows Unsaved and the file on disk has not changed.
3. Press Command-S. Compare the file: the frontmatter and Wiki links must be unchanged.
4. Make sure that Command-Z still reverses the edit after the save.
5. Edit again, open another file, and select Cancel. Make sure that the draft stays.
6. Open another file and select Discard. Make sure that the first file has not changed.
7. Edit again and close the window with Command-W. Select Save and compare the file.
8. Edit again, then change the file in another app. Save and make sure that Piper refuses.

## Reading Preference Checks

1. Open Settings > Reading.
2. Switch among Paper, Sepia, and Slate.
3. Change the font, the size, and the appearance.
4. Make sure that an unsaved edit keeps its text and scroll position.
5. Select Reset and make sure that the defaults return.
6. Switch Settings > Style between Vault and Page. Make sure that both windows update.

## Inbox Reader Checks

1. Capture a note that contains only a URL, and a note that contains text with two URLs.
2. Select Inbox in the Wiki window, then select each note.
3. Follow a redirect, use Back and Forward, and select Reload.
4. Load a page that fails, then select Retry.
5. Select text on a page and select Capture. Make sure that a new Inbox note has the page title and URL.

## Export Checks

1. Select notes with source URLs and select Wiki in the selection bar.
2. Save the file inside the Wiki folder.
3. Make sure that the Wiki window opens the file.
4. Make sure that the frontmatter has `title`, `created`, and `sources`.
5. Make sure that no other file in the folder changed.
6. Export again to a folder outside the Wiki. Make sure that only that file is written.

## Distribution Checks

1. Run `make release`.
2. Make sure that `notarytool` reports `Accepted`.
3. Make sure that `stapler` validates the DMG.
4. Make sure that Gatekeeper accepts the DMG.
5. Download the DMG on a clean Mac.
6. Install Piper in Applications.
7. Start Piper and allow Accessibility access.
8. Restart Piper and capture text from another app.

Record the macOS version and the SHA-256 checksum.

## Recorded Results

- Release 0.1.0 for Apple silicon passed Developer ID signature checks, notarization, stapling, and Gatekeeper on September 12, 2026. Artifact: `build/Piper_0.1.0_arm64.dmg`. SHA-256: `0f2e9a794ddc96971ad975fc7f748838cfa7d3f4961034d6d6f718af559f6917`.
- On the same date, Accessibility approval worked for the signed release and survived a replacement of the app.
- The global shortcut checks were skipped. The clean-Mac check is open.

These results are older than the module refactor. Repeat the checks for the next release.
