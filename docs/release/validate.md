---
title: "Validate A Build"
summary: "Automated tests and manual acceptance checks for capture, the papers, and distribution"
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
| `PiperCoreTests` | Frontmatter parsing and line endings |
| `HistoryTests` | Browser sources, history reads, the digest, the decay rank, and blocked sites |
| `FeedsTests` | The feed parser, the feed database, refresh, feed discovery, OPML import, and suggestions |
| `CapturesTests` | The capture store, clipboard entries, and capture links |
| `StreamTests` | The stream of Today, the feed rows and modes, and the relevance score |
| `VaultTests` | Scans, path safety, reads, writes, and the watcher |
| `PiperTests` | The app model: editing, refresh, previews, quit safety, the verbs of Today, and Sources |

The tests do not cover the UI or the global shortcut path.

## Capture Checks

1. Run `make run`.
2. Make another app active. Select New Capture in the menu bar icon. Make sure that the feed paper shows Today with the cursor in the capture field.
3. Select the Agents tab, then press Command-1. Make sure that the feed paper changes to Today with the cursor in the capture field.
4. Save a note with Return. Control-click it, select Edit, and select Save.
5. Paste a web link in the capture field and press Return. Make sure that the link shows in the Reading lens and the Kept lens.
6. Paste the home page of a site with a feed and press Return. Make sure that Sources opens and finds the feed. Paste it again and press Option-Return. Make sure that Piper saves it as a link.
7. Type `# Research` and press Return. Make sure that the section exists and the list shows it.
8. Copy text in another app. In the Clipboard part of Today, select the text and press K. Make sure that a kept note shows in Inbox.
9. Copy more text. Select it and press E. Make sure that it leaves the tray, and that Undo brings it back within 5 seconds.
10. Restart Piper.
11. Make sure that the notes, the sections, the lens, and the capture field draft are still there.

## Today And Sources Checks

1. Make sure that Today shows notes, links, feed articles, digest rows, and the clipboard tray in one list, in day groups.
2. Press 1, 2, 3, and 4. Make sure that the All, Notes, Reading, and Kept lenses show, and that each count matches the list.
3. Select a row with the keyboard. Make sure that Keep, Done, File, Send, and More show on the selected row without the pointer.
4. Press K, E, F, and S on a note, an article, a digest, and a clipboard text. Make sure that each verb acts as the capture guide says.
5. Press F. File a note into a section, an article into a folder, and a note into a file. Make sure of the result on disk.
6. Command-click two notes, then Shift-Down. Make sure that the selection bar shows. Use Keep, Done, File, Send, Merge, and Copy.
7. Turn on VoiceOver. Make sure that VoiceOver reads each row as one item, and reaches Keep, Done, File, Send, and More as separate buttons.
8. Open Sources from the More menu and from the command palette. Change the mode of a feed. Make sure that Today shows the new mode, and that the mode survives a restart.
9. On Sources, import an OPML file, add a feed by address, and add a site from Sites You Read Often.
10. Open an article on a paper and press K. Make sure that the article shows as one kept row in Today.
11. Select a section on the Today index. Make sure that the list shows only the captures of that section, and that the capture field saves to it.
12. Select Done on the Today index. Make sure that the completed notes show by month.

## Claude Checks

Use a copy of a folder with skills, because a session changes files.

1. Add the copy with Add Folder. Make sure that Settings > AI shows the folder, the path of `claude`, and a green dot for Claude Code.
2. Copy a URL. In the Clipboard part of Today, select it, then select a skill in the Send menu of the row. Send the draft. Make sure that the note shows Running, then Done or Failed.
3. With Auto, send a link to a skill that fetches the page. Make sure that the note shows Done.
4. Select Ask Every Time in Settings > AI > Claude Code > Permissions. Send a link to a skill that needs a shell command. Make sure that the note shows Needs you.
5. Select the note. On its reader paper, select Deny on the card. Make sure that Claude continues and names the denied call.
6. Send the link again. Select Always in <folder> on the card. Make sure that `.claude/settings.local.json` in the folder has the rule.
7. Select the Done badge on a note. Make sure that the file paper opens the file that the session wrote.
8. Press Option-Command-C. Make sure that the session card opens with a chip for the file. Select Pop Out, then Dock. Make sure that the card returns to the reader paper.
9. Type a question and press Return. Make sure that the transcript shows the tool calls and the answer. Send a second message in the same session.
10. Type `@` and a part of a file name. Make sure that the file list shows, and that Tab puts the path in the message.
11. Select the Agents tab, then the folder. Make sure that the list shows its sessions. Select a session. Make sure that it opens on a reader paper.
12. Type `/` in the composer. Make sure that the skill list shows. Press Tab, type a URL, and press Return.
13. Copy a URL in another app and press Control-Option-W. Make sure that a toast shows, and that Show opens the note.
14. Capture a selection with double Shift. Make sure that the toast shows a Send button, and that the button starts a session.
15. Start a turn and quit Piper. Make sure that Piper asks before it stops the turn. Open Piper again. Make sure that the session shows "Piper quit before the turn finished." and continues after a new message.

To test resume, start a turn and select Stop. Send another message. Make sure that `ps` shows `--resume` in the new `claude` process, and that Claude knows the earlier messages.

## ACP Agent Checks

Use a copy of a folder, because a session changes files. Install an ACP agent, such as OpenCode, and sign in to it in Terminal.

1. In Settings > AI, select Add ACP Agent, then OpenCode. Select Add. Make sure that the OpenCode row shows a green dot and a version.
2. Open the session card. In the composer footer, select OpenCode in the agent menu.
3. Send a message that needs a file edit. Make sure that the model and mode menus show the lists of OpenCode after the agent starts.
4. If the agent asks for approval, make sure that the drawer over the composer shows the buttons of OpenCode. Select the allow button.
5. Make sure that the finished turn shows one line for its tool calls. Select the line, and make sure that the tool calls show.
6. Select Stop during a turn. Make sure that the transcript shows "Stopped." and that the next message continues in the same process.
7. Quit Piper and open it again. Send a message in the same session. Make sure that the agent knows the earlier messages and that the transcript does not show them twice.

## Margin Answer Checks

1. Open a link capture in the Reader tab. Select a passage, then select Explain.
2. Make sure that the card names the model and the agent, for example "Haiku · Claude Code".
3. Ask a question that needs the web. Make sure that the card shows a line for the tools, and that no approval request shows.
4. Make sure that the Agents tab does not show the margin session.
5. Select Continue in Session. Make sure that a draft session opens with the question thread and the address of the page.

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

## Paper Checks

1. Add a disposable folder with the + Folder tab. Make sure that the folder gets a tab after the fixed tabs, and that the tab shows its tree.
2. Add, rename, and delete a file in Finder. Make sure that the tree updates.
3. Press Command-K and type a part of a file name. Make sure that Return opens the file on the file paper.
4. Select a folder in the folder tree. Make sure that it opens or closes. Press Right Arrow, Left Arrow, and Return on the tree. Make sure that they open, close, and step as in the browse guide.
5. Select each tab. Make sure that the tab comes to the front and joins the paper. Select the active tab of Today or Agents, then press Escape. Make sure that the paper moves between the index and the list. Turn on Reduce Motion. Make sure that the active tab does not slide.
6. Open a capture, an article, and a file. Make sure that each paper opens right of the feed paper, 24 points lower than the last one. Close the first paper and open another item. Make sure that the new paper takes the free place. Open the capture again. Make sure that its paper comes to the front.
7. Press Command-` several times. Make sure that the focus moves through every paper. Press Escape on a reader paper. Make sure that it closes.
8. Add two more folders. Make sure that their tabs take teal, rose, and clay in order. Select each folder tab. Make sure that the title and the tree change to that folder. Select a swatch. Make sure that the tab takes the color. Make the feed paper short. Make sure that the folder tabs show one letter.
9. Quit Piper and open it again. Make sure that the feed paper restores its frame, its tab, its scope, its tab colors, and its open folders.
10. Drag each edge and each corner of the feed paper and of a reader paper. Make sure that the pointer shows the resize arrows, that the paper keeps its minimum size, and that the column of tabs stays on the feed paper. Drag the body text of an article. Make sure that the drag selects text and does not move the paper.
11. Double-click the header of a reader paper. Make sure that it fills the screen, and that a second double-click puts it back. Close the paper and open its item again. Make sure that the paper opens in its last frame.
12. Follow a Wiki link, then use Command-[ and Command-].
13. Switch Markdown and HTML files between Preview and Source in the tabs at the bottom of the paper. Make sure that Source shows their text, and that long lines wrap.
14. Open a JSON file, an image, and a PDF. Make sure that each one shows a preview.
15. Control-click the tab of the added folder and select Remove Folder. Make sure that its tab leaves the column. Make sure that the folder stays on disk.

## Editing Checks

1. Edit a Markdown file that has frontmatter.
2. Wait one second. Make sure that the byline shows Saved and that the file on disk has the edit.
3. Compare the file: the frontmatter and Wiki links must be unchanged.
4. Press Command-Z, Command-B, and Command-V in the editor. Make sure that each key edits the page, and that a pasted image saves in `<note name>.assets`.
5. Type Japanese text with the macOS input method. Make sure that the text is correct on disk.
6. Edit, then open another file within one second. Make sure that the first file has the edit.
7. Edit, then quit with Command-Q within one second. Make sure that the file has the edit.
8. Change the open file in another app. Make sure that the page shows the new text.
9. Edit, then change the file in another app before the save. Make sure that the bar shows, and that Keep Mine and Reload work.
10. Open a file with a footnote. Make sure that Preview shows the number and the note. Edit the note, and make sure that the file keeps `[^1]` and `[^1]: `.
11. Press Command-F and find a word. Press Command-K with no text selected, and open a file.
12. Select text in a file. Select each color, Note, and Explain. Make sure that the file has the highlights, and that the margin shows the note and the answer.

## Reading Preference Checks

1. Open Settings > Reading.
2. Switch among Paper, Sepia, and Slate.
3. Change the font, the size, and the appearance. Make sure that Serif shows a serif font.
4. Make sure that an unsaved edit keeps its text and scroll position.
5. Select Reset to Defaults and make sure that the defaults return.
6. Switch the system appearance between Light and Dark. Make sure that both windows update.

## Link Reader Checks

1. Capture a note that contains only a URL, and a note that contains text with two URLs.
2. In Today, open each note. Make sure that the note with only a URL opens in the Reader tab, and that the other note opens in the editor. Control-click the other note and select Add Link to Reading.
3. Follow a redirect, use Back and Forward, and select Reload.
4. Load a page that fails, then select Try Again.
5. Select text on a page and select Capture in the reader bar. Make sure that a new note in Inbox has the page title and URL.

## Reading Checks

Before you start, allow Accessibility access. Do these steps in Safari, Chrome, and Arc:

1. Open an article. Select one sentence, then press Shift twice.
2. Make sure that the toast shows the page title and "1 on this page". Make sure that the browser keeps the focus.
3. Press Shift twice again. Type a note, then press Return. Make sure that the browser gets the focus back.
4. Select text that runs over two paragraphs, then press Shift twice.
5. Select Continue in Piper. Make sure that the Reader tab opens at the highlight, and that the note shows as a card.
6. Open another page with no selection, then press Shift twice. Make sure that it shows in Up Next.
7. Open a page behind a login, then press Shift twice. Open it in Piper. Make sure that the Reader tab shows its text.
8. Scroll the article, select another capture, then select the article again. Make sure that it opens at the same place.
9. In the Notes tab, type a summary and select Save as File. Make sure that the file has the source, the summary, and the highlights.
10. Add a highlight, then select Update File. Make sure that the file has the new highlight at its end.

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

- On September 18, 2026, `make test` passed 220 tests with no failures on macOS 27.0 (26A428), Apple silicon.
- On the same date, `make build` completed. An isolated app copy displayed fictional captures, Markdown architecture notes, and Claude sessions for the README screenshots.
- These local checks do not cover selection shortcuts, Claude authentication, notarization of the current source, or installation on a clean Mac.

- Release 0.1.0 for Apple silicon passed Developer ID signature checks, notarization, stapling, and Gatekeeper on September 12, 2026. Artifact: `build/Piper_0.1.0_arm64.dmg`. SHA-256: `0f2e9a794ddc96971ad975fc7f748838cfa7d3f4961034d6d6f718af559f6917`.
- On the same date, Accessibility approval worked for the signed release and survived a replacement of the app.
- The global shortcut checks were skipped. The clean-Mac check is open.

- On September 22, 2026, `make release` passed the tests and built Piper 0.1.1 on macOS 27.0 (26A428), Apple silicon.
- Apple accepted the 0.1.1 DMG. Developer ID signature checks, stapling, and Gatekeeper passed. Artifact: `build/Piper_0.1.1_arm64.dmg`. SHA-256: `319cca3fc017ab6ce664343ba0c5d079cf744af0b394c53a0ba9270c18725d72`.
- Installation on a clean Mac remains unverified for 0.1.1.
