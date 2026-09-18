---
title: "Validate A Build"
summary: "Automated tests and manual acceptance checks for capture, the main window, and distribution"
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
| `PiperTests` | The app model: editing, refresh, read state, previews, and quit safety |

The tests do not cover the UI or the global shortcut path.

## Capture Checks

1. Run `make run`.
2. Save a note with Return, and edit it with Save.
3. Copy text in another app. Move the pointer over its row in the panel and select Keep.
4. Double-click another clipboard row. Make sure that the text pastes into the app in front.
5. Select each section tab. Make sure that the list scrolls to that section and the composer placeholder names it.
6. Select the Clipboard tab. Make sure that the rows show the source app and the time, and that Clear History empties the list.
7. Select notes, then use Merge, Move, Copy, Delete, Command-Shift-C, and Undo.
8. Restart Piper.
9. Make sure that the notes, sections, and composer draft are still there.

## Main-Window Inbox

1. Select Inbox in the main window. Make sure that every section shows in one list, and that the title shows the note count.
2. Select a section under Inbox. Make sure that the list scrolls to it.
3. Select New Section at the bottom of the sidebar. Make sure that the new section shows under Inbox.
4. Select several notes. Use Merge, Move, Copy, Delete, and Undo.
5. Search from the field at the top of the Inbox list. Make sure that results come from every section.
6. Select one note and type in the detail pane. Make sure that the change is saved after a pause.
7. Select text in the detail pane. Make sure that Command-C copies the text and Delete does not remove a note.
8. Select Mark as Done in the toolbar. Make sure that the note circle fills.
9. Select Clipboard in the sidebar. Make sure that the history shows.

## Claude Checks

Use a copy of a folder with skills, because a session changes files.

1. Add the copy to the sidebar. Make sure that Settings > Claude shows the folder and the path of `claude`.
2. Copy a URL. Open the capture panel and select Send on the clipboard row. Make sure that the note shows Running, then Done or Failed.
3. With Auto, send a link to a skill that fetches the page. Make sure that the note shows Done.
4. Select Ask Every Time in Settings > Claude. Send a link to a skill that needs a shell command. Make sure that the note shows Needs you.
5. Select the note. In the detail pane, select Deny on the card. Make sure that Claude continues and names the denied call.
6. Send the link again. Select Always in <folder> on the card. Make sure that `.claude/settings.local.json` in the folder has the rule.
7. Select the Done badge on a note. Make sure that the main window opens the file that the session wrote.
8. Press Option-Command-C. Make sure that the Claude pane opens with a chip for the file.
9. Type a question and press Return. Make sure that the transcript shows the tool calls and the answer. Send a second message in the same session.
10. Type `@` and a part of a file name. Make sure that the file list shows, and that Tab puts the path in the message.
11. Select the folder in the Claude group of the sidebar. Make sure that the list shows the sessions and the detail pane shows the selected one.
12. Type `/` in the composer. Make sure that the skill list shows. Press Tab, type a URL, and press Return.
13. Copy a URL in another app and press Control-Option-W. Make sure that a toast shows, and that Show opens the note.
14. Capture a selection with double Shift. Make sure that the toast shows a Send button, and that the button starts a session.
15. Start a turn and quit Piper. Make sure that Piper asks before it stops the turn. Open Piper again. Make sure that the session shows "Piper quit before the turn finished." and continues after a new message.

To test the idle timeout, set `AppDefaults.Sessions.idleTimeout` to 60 seconds in a debug build. Wait for 2 minutes after a turn, then send a message. Make sure that `ps` shows `--resume` in the new `claude` process.

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

## Main Window Checks

The middle-pane search filters the selected folder. A matching file in another folder must stay outside the results. Home search still finds files across the vault.

1. Add a disposable folder with Add Folder at the bottom of the sidebar.
2. Add, rename, and delete a file in Finder. Make sure that the tree and the file list update.
3. Search from Home and from the field over the list.
4. Open a file. Make sure that its unread dot goes away.
5. Follow a Wiki link, then use Command-[ and Command-].
6. Switch Markdown and HTML files between Preview and Source in the toolbar. Make sure that Source shows their text, and that long lines wrap.
7. Open a JSON file, an image, and a PDF. Make sure that each one shows a preview.
8. Control-click the added folder and select Remove Folder. Make sure that the folder stays on disk.

## Editing Checks

1. Edit a Markdown file that has frontmatter.
2. Make sure that the date line ends with Edited and the file on disk has not changed.
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
5. Select Reset to Defaults and make sure that the defaults return.
6. Switch the system appearance between Light and Dark. Make sure that both windows update.

## Inbox Reader Checks

1. Capture a note that contains only a URL, and a note that contains text with two URLs.
2. Select Inbox in the main window, then select each note. Select Open Reader on a link card.
3. Follow a redirect, use Back and Forward, and select Reload.
4. Load a page that fails, then select Try Again.
5. Select text on a page and select Capture in the reader bar. Make sure that a new Inbox note has the page title and URL.

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
