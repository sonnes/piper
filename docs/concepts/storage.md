---
title: "Local Storage"
summary: "Capture records, preferences, and persistence limits"
read_when:
  - Locating local data
  - Changing persistence or undo behavior
---

# Local Storage

## Capture Database

Piper stores captures in `~/Library/Application Support/Piper/notes.sqlite`. SQLite holds one versioned JSON snapshot in the `state` table.

The snapshot includes notes, sections, and the active section. Notes contain UUIDs, text, source applications, source URLs, completion status, and timestamps.

State changes save before the UI adopts them. Unsupported database versions produce an error without overwriting the saved state.

New databases contain Inbox and no notes. Existing databases retain their saved sections and captures.

Writes compare the stored snapshot with the last loaded snapshot. A stale app instance cannot replace newer notes. Database locks leave changes unsaved and available for retry.

The current schema is version 1. General schema migration is not implemented. The database uses SQLite's default journal behavior.

## Clipboard Previews

Clipboard previews remain in memory until Piper quits. The buffer holds up to ten recent text entries, each limited to 500,000 UTF-8 bytes.

Clicking a preview saves a normal capture through the database. Preview text does not enter SQLite or UserDefaults before that click.

Piper checks clipboard changes approximately every 0.6 seconds. Copies replaced between checks are unavailable to the observer.

## Preferences And Undo

UserDefaults stores `wikiPath`, `captureShortcut`, and `composerDraft`. Wiki preferences store the theme, font, text size, appearance, and right sidebar visibility.

Window frame preferences retain window positions separately. Reading preferences do not change Wiki files.

The release bundle ID is `com.piper`. First launch copies missing preferences from the previous `local.piper` domain. The capture database path stays unchanged.

Undo keeps one previous state in memory. Undo saves that restored state to the database. Restarting Piper clears the undo history.

Selecting an existing section does not replace note undo history. Unchanged editor saves do not create an undo step.

Capture editor drafts remain in memory until saved or discarded. Conflicting editors cannot overwrite each other's text. Quitting prompts for changed captures and Wiki notes. Wiki edits remain in memory until an explicit save or discard.

## Wiki Independence

Wiki documents remain ordinary Markdown files in the selected folder. Browsing them does not import them into the capture database.

Export copies selected note content into a draft. Deleting a capture does not remove an exported Wiki file.

For a database backup, quit Piper before copying the application support folder. Preferences require a separate backup.
