---
title: "Local Storage"
summary: "Where Piper keeps captures, preferences, and read state, and the limits of each store"
read_when:
  - Locating local data
  - Backing up Piper
  - Changing persistence, preferences, or undo behavior
---

# Local Storage

Piper keeps captures in a SQLite database and preferences in UserDefaults. Wiki files stay in their folder. Piper never copies them into the database.

## Capture Database

The database is `~/Library/Application Support/Piper/notes.sqlite`. Settings > Local Data > Show in Finder opens its folder.

The `state` table holds one versioned JSON snapshot. The snapshot contains the notes, the sections, and the active section. Each note has these fields:

| Field | Content |
| --- | --- |
| `id` | A UUID |
| `text` | The note text |
| `section` | The section name |
| `sources` | Source app names, `Clipboard`, or a web page title |
| `sourceURLs` | HTTP and HTTPS URLs |
| `isDone` | The done state |
| `createdAt`, `modifiedAt` | Creation and modification times |

A new database has the Inbox section and no notes.

### Write Safety

Piper writes a new snapshot before the UI shows the change. A save compares the stored snapshot with the snapshot that Piper loaded last. If they differ, the save fails. As a result, a second Piper instance cannot replace newer notes.

If the database is locked, Piper waits three seconds. Then the save fails, the current notes stay, and you can try again.

The schema is version 1. Piper refuses to open a snapshot with an unknown version, and it does not overwrite that snapshot. Piper has no general schema migration. The database uses the default SQLite journal mode.

### Undo

Piper keeps one earlier state in memory. Undo saves that state to the database. A restart clears the undo step.

Selecting an existing section does not replace the undo step. An editor save with no change adds no undo step.

## Clipboard History

Clipboard texts stay in memory until Piper quits or you select Clear History. They do not go into SQLite or UserDefaults. A text becomes a note only when you keep it. Each text records the time of the last copy and the app that was in front.

Piper checks the clipboard about every 0.6 seconds. If an app replaces the clipboard twice between checks, Piper sees only the last copy. The history holds 50 texts, each up to 500,000 UTF-8 bytes.

## Drafts

The composer text is a preference, so it survives a restart. Edits to an existing note and edits to a Wiki file stay in memory until you save or discard them. If you quit with a changed draft, Piper asks what to do.

## Preferences

UserDefaults holds these keys:

| Key | Content |
| --- | --- |
| `wikiPath` | The active Wiki folder |
| `wikiPaths` | The Wiki folders in the sidebar |
| `captureShortcut` | `Shift, Shift` or `Control-Option-Space` |
| `composerDraft` | The unsaved composer text |
| `accessibilityTipDismissed` | True after you close the Accessibility tip in the capture panel |
| `showsFileSource` | True while the main window shows the Source view of a file |
| `wikiReaderTheme`, `wikiReaderFont`, `wikiReaderSize`, `wikiReaderAppearance` | Reading preferences |
| `wikiFileSort` | Name or Date |
| `mainWindowState` | The sidebar selection, open file, open folders, and pane widths |
| `wikiReadTimestamps` | Read state |
| `NSWindow Frame PiperCapturePanel`, `NSWindow Frame PiperLibrary` | Window frames |

### Read State

`wikiReadTimestamps` stores, for each Wiki folder and relative path, the modification time of the file when you last opened it. A file is unread when it has no stored time or its time differs. A change that keeps the modification time does not make a file unread.

### Bundle ID Migration

The release bundle ID is `com.piper`. On the first launch, Piper copies missing keys from the earlier `local.piper` domain. It copies `wikiPath`, `captureShortcut`, `composerDraft`, `wikiReaderSize`, and the two window frames. The database path does not change.

## Back Up Piper

1. Quit Piper.
2. Copy `~/Library/Application Support/Piper`.
3. If you want the preferences, copy `~/Library/Preferences/com.piper.plist`.

