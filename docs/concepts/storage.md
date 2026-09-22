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

Piper writes a new snapshot before the UI shows the change. A save compares the stored snapshot with the snapshot that Piper loaded last. If they differ, the save fails. As a result, a second Piper instance cannot replace newer notes. Clipboard rows do not use this check.

If the database is locked, Piper waits three seconds. Then the save fails, the current notes stay, and you can try again.

The schema is version 1. Piper refuses to open a snapshot with an unknown version, and it does not overwrite that snapshot. Piper adds the `clipboard` and `sessions` tables the first time it opens a version 1 database. Piper has no general schema migration. The database uses the default SQLite journal mode.

### Undo

Piper keeps one earlier state in memory. Undo saves that state to the database. A restart clears the undo step.

Selecting an existing section does not replace the undo step. An editor save with no change adds no undo step.

## Claude Sessions

The `sessions` table in the capture database holds each Claude session. Each row has an `id`, the `folder`, an `updated_at` time, and a JSON `data` value with these fields:

| Field | Content |
| --- | --- |
| `folder` | The absolute path of the folder |
| `noteID` | The note that started the session, if a note started it |
| `command` | The skill of the first turn, if a skill started the session |
| `claudeSessionID` | The session id that `claude --resume` takes |
| `state` | `waiting`, `running`, `needsYou`, `idle`, or `failed` |
| `createdAt`, `updatedAt` | The start time and the time of the last change |
| `unread` | True when a turn ended after you last looked at the session |
| `blocks` | The transcript: messages, tool calls, cards, and turn results |

Piper writes a row at each change of state. Text and tool calls wait 250 milliseconds, so a fast stream writes less often. When Piper starts, it keeps the 500 most recently changed rows. A session that was in a turn at that time changes to `idle`, with the result "Piper quit before the turn finished." Undo does not change sessions.

An older version of Piper kept its runs in a `runs` table. Piper does not read that table and does not remove it.

Claude Code keeps its own copy of each conversation in `~/.claude`. Piper uses that copy only through `--resume`.

### Allow Rules

Always in <folder> on a permission card adds a rule to `permissions.allow` in `.claude/settings.local.json` in that folder. Piper creates the file if it does not exist. The other keys of the file stay the same. Claude Code reads this file with `.claude/settings.json`. If the folder is a Git repository, add the file to `.gitignore` to keep your rules out of commits.

## Clipboard History

The `clipboard` table in the capture database holds the clipboard history, so the history survives a restart. A text becomes a note only when you keep it. Clear History removes every row. Each row has these fields:

| Field | Content |
| --- | --- |
| `id` | A UUID |
| `text` | The copied text |
| `copied_at` | The time of the last copy, in seconds since 1970 |
| `source` | The app that was in front, or no value |

The history holds the 50 latest texts, each up to 500,000 UTF-8 bytes. Piper removes a text 7 days after its last copy. This check runs when Piper starts and each time Piper checks the clipboard. A text that leaves the history also leaves the table.

Piper checks the clipboard about every 0.6 seconds. If an app replaces the clipboard twice between checks, Piper sees only the last copy.

The table stores each text as plain text on disk. Piper does not store the texts that an app marks concealed or transient, such as passwords from a password manager.

## Drafts

The composer text is a preference, so it survives a restart. Edits to an existing note and edits to a Wiki file stay in memory until you save or discard them. If you quit with a changed draft, Piper asks what to do.

## Preferences

UserDefaults holds these keys:

| Key | Content |
| --- | --- |
| `wikiPath` | The active Wiki folder |
| `wikiPaths` | The Wiki folders in the sidebar |
| `captureShortcut` | `Shift, Shift` or `Control-Option-Space` |
| `captureFloating` | True by default. Keeps the capture panel above other apps. |
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
