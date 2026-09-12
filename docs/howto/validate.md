---
title: "Validate A Local Build"
summary: "Manual acceptance checks for permissions, windows, and Wiki export"
read_when:
  - Testing a build before regular use
  - Recording application compatibility
---

# Validate A Local Build

## Automated Tests

Run `make test` from the repository root.

The suite uses temporary Wiki folders. It covers capture state, YAML, exports, path safety, navigation history, file trees, link resolution, and reader parsing.

## Wiki Workspace Checks

Use an empty temporary folder or a disposable copy of your Wiki. The application has no sample mode.

1. Open Wiki and choose the temporary folder.
2. Select Create Wiki if the folder is empty.
3. Export a capture with headings, lists, code, and a link.
4. Select Read in Wiki.
5. Search for text in the exported document.
6. Open Document Sidebar and expand On This Page and Backlinks.
7. Select a heading and check its scroll position.
8. Follow a Wiki link and check Back/Forward navigation.
9. Scroll partway through a document and enter Markdown.
10. Check that the file remains unchanged and the sidebar shows Unsaved changes.
11. Select Save and compare the saved file, YAML, and Wiki aliases.
12. Check that Undo reverses the edit after Save.
13. Open another file and select Cancel in the save prompt.
14. Check that the current note and unsaved text remain open.
15. Open another file and select Discard.
16. Check that the first file remains unchanged.
17. Edit a note and close the Wiki window with Command-W.
18. Select Save in the prompt and compare the file.

All 52 automated tests pass. They cover manual Wiki saves, navigation choices, close protection, refresh, editing conflicts, capture, export, and database conflicts.

Native checks passed for immediate editing, sidebar Save, Command-S, Undo after Save, navigation Cancel, and Discard on close. Temporary files confirmed each write boundary. The user's Wiki files remained unchanged.

Release 0.1.0 passed native composer, capture editing, Cancel, and Delete checks on September 12, 2026. SQLite preserved Unicode text, tabs, and newlines exactly.

The verification note was removed after these checks. The installed app uses the user's Wiki folder and real clipboard.

Earlier native checks passed in the light appearance on September 12, 2026:

- Clipboard ghost cards save, disappear after saving, and return after Undo.
- Search filters clipboard previews.
- Focus mode hides and restores navigation panes.
- Backlinks, inline links, heading jumps, and Back/Forward navigation work.
- Code blocks and tables render within the reading column.
- Pasted Markdown preserves leading and trailing newlines.
- Command-S preserves YAML and Wiki aliases.
- Reading and editing retain the same text view, scroll position, and outline.

Check reading preferences before accepting a sidebar change:

1. Switch among Paper, Sepia, and Slate.
2. Change the font and text size.
3. Switch between Light, Dark, and System appearance.
4. Hide and restore each sidebar.
5. Check that text wraps within the reading column.
6. Enter text and change reading preferences.
7. Check that the note retains its unsaved text and page position.
8. Select Reset to restore the default preferences.

## Window And Capture Checks

The Graphite + Cobalt build passed visual checks in both Wiki appearances on September 12, 2026. The checks covered links, selections, typography, and the sidebar bird. The Capture panel showed the paper surface, monospace composer, and Cobalt focus border. The app bundle passed signature validation and includes the fonts, template mark, and macOS icon.

1. Run `make run`.
2. Open both windows with Command-1 and Command-2.
3. Verify that the capture panel floats separately from the Wiki browser.
4. Move both windows and resize the Wiki window.
5. Restart Piper.
6. Verify that each window restores its own frame.
7. Enter a capture and save an edit with Save Changes.
8. Restart Piper.
9. Verify the saved text.

After Accessibility approval, repeat selection capture in each target application:

| Application | Text Selection | Empty Selection | Secure Field | Focus Preserved | Result |
| --- | --- | --- | --- | --- | --- |
| Safari | Pending | Pending | Pending | Pending | Pending |
| Chrome | Pending | Pending | Pending | Pending | Pending |
| TextEdit | Pending | Pending | Pending | Pending | Pending |
| Terminal | Pending | Pending | Pending | Pending | Pending |

Record the macOS version, application version, and permission state with each result. No row currently claims compatibility.

Accessibility approval succeeded for the signed release and survived replacement of the app. Global-shortcut checks were skipped at the user's request.

The automation tool sends keystrokes directly to applications. Those events do not verify macOS global hotkey delivery or double-Shift behavior.

## Distribution Checks

1. Run `make release`.
2. Make sure that `notarytool` reports an `Accepted` status.
3. Make sure that `stapler` validates the DMG.
4. Make sure that Gatekeeper accepts the DMG.
5. Download the DMG on a clean Mac.
6. Install Piper in Applications.
7. Start Piper and approve Accessibility access.
8. Restart Piper and capture text from another application.

Record the macOS version and the SHA-256 checksum. The clean-Mac test remains incomplete until a separate Mac passes these checks.

Release 0.1.0 for Apple silicon passed Developer ID signature checks, Apple notarization, ticket stapling, and Gatekeeper assessment on September 12, 2026.

Artifact: `build/Piper_0.1.0_arm64.dmg`. SHA-256: `0f2e9a794ddc96971ad975fc7f748838cfa7d3f4961034d6d6f718af559f6917`.

## Export Checks

Use a disposable copy of an OKF 0.2 Wiki for these checks.

1. Choose the disposable folder in Settings.
2. Export selected captures with a title, description, and source URL.
3. Verify that the document has draft status and capture provenance.
4. Verify that existing concepts and `.raw` files remain unchanged.
5. Verify that root and folder indexes include the draft.
6. Verify that `log.md` contains one creation entry for the draft.
7. Export the same selection again.
8. Verify that Piper reuses the draft without a duplicate log entry.
9. Select Read in Wiki.
10. Verify that the separate browser opens the document.

The automated retry test covers a partial index error. Manual interruption and concurrent editor checks remain in the release plan.
