---
title: "Use Your Wiki"
summary: "Browse Markdown and export captures into an OKF 0.2 bundle"
read_when:
  - Connecting Desktop/Wiki
  - Reading Wiki documents
  - Saving captures as Wiki drafts
---

# Use Your Wiki

## Choose And Browse

1. Select Wiki beside the capture search field, or press Command-2.
2. If your Wiki is elsewhere, open the folder menu at the bottom of the sidebar.
3. Select Choose Wiki Folder.
4. Expand a folder, then select a document.

The default folder is `~/Desktop/Wiki`. The file tree includes nested folders, indexes, and logs.

Command-O focuses Wiki search. Command-F searches within the open note. Search matches titles, paths, descriptions, and body text. It preserves the current document until you select a result.

The Wiki shows one document at a time.

Use Command-[ and Command-] to move through navigation history. Command-W closes the Wiki window.

## Read A Document

The page always shows the live Markdown editor in a bounded text column. The header contains navigation, the document title, and sidebar buttons.

The Document sidebar keeps Save and the saved status above its scrollable controls. It includes a document preview, Theme, Typography, and Appearance. Preferences apply to reading and editing without changing Markdown files.

Theme offers Paper, Sepia, and Slate. Paper uses the Graphite palette with Cobalt accents. Monospace uses bundled IBM Plex Mono. Size ranges from 13 to 24 points.

Appearance follows the system or uses Light or Dark. Reset restores Paper, Monospace, 18 points, and the system appearance.

On This Page, Backlinks, Note Details, and Sources expand within the same sidebar. The outline includes section headings at every level.

Select a heading to jump to it.

Wiki links support `[[Note]]`, `[[folder/Note|Label]]`, and `[[Note#Heading]]`. Relative Markdown links resolve from the current document.

The right sidebar button hides or restores document controls. The left sidebar button hides the file tree. The text column adapts to the available width.

Focus in the Document sidebar, or Option-Command-F, enters focus mode. Focus hides both sidebars. Press Escape or Option-Command-F to return.

Select code and press Command-C to copy it. Long code lines wrap within the reading column. Long documents use the native vertical scrollbar.

Browsing does not write files or load remote images.

## Edit A Document

1. Select a note and edit its text.
2. Select Save in the Document sidebar, or press Command-S.

Save keeps the same page, scroll position, and undo history. The sidebar shows Unsaved changes until you save or discard the edit.

Opening another note, changing Wiki folders, closing the Wiki window, or quitting Piper prompts for unsaved changes. Save writes the file. Discard leaves the file unchanged. Cancel keeps the current note open.

Outline headings scroll the current page without ending an edit. Footnote markers remain Markdown text in the editor.

The editor uses SwiftMarkdownEngine 0.12.0. Formatting appears as you type, and syntax markers appear near the caret. Command-Z reverses an edit.

Paste inserts plain text through AppKit and preserves whitespace. It does not convert rich HTML into Markdown.

YAML remains outside the editing surface. Saving preserves the original metadata bytes and Wiki link targets. Actions in the Document sidebar provides Discard Changes and Reveal in Finder. Discard Changes restores the version on disk after confirmation.

If another application changes the file, Piper refuses to overwrite it. The draft stays open, and navigation stops until you resolve the conflict.

## Create A Wiki

1. Open the Wiki window.
2. Select Create Wiki Here, or choose an empty folder first.
3. Select Create Wiki if the chosen folder is empty.

Piper creates an OKF 0.2 root index. It adds no sample documents. Existing nonempty folders remain unchanged.

Send captures to this Wiki to create its first draft. Existing Markdown folders remain available for reading and editing.

## Save Captures As A Draft

1. Open the separate capture panel with Command-1.
2. Click a note, then Command-click any additional notes.
3. Select Send to Wiki from the selection action menu.
4. Enter a title and description.
5. Select a destination.
6. If needed, enter an HTTP or HTTPS source URL.
7. Review the captured text.
8. Select Save Draft.
9. To open the saved document, select Read in Wiki.

Destinations are `sources`, `topics`, `projects`, and `decisions`. Export requires an OKF 0.2 root index and valid concept metadata.

Export creates a draft with capture IDs and provenance. It regenerates root and folder indexes, then appends a creation entry to `log.md`.

Existing captures remain in Piper. Existing concepts and `.raw` archives remain unchanged. Send to Wiki runs no Wiki scripts and creates no Git commits.

## Run A Wiki Command

1. Open the Wiki window.
2. Select the terminal button in the left ribbon.
3. Select a command from the menu.
4. If the command takes arguments, enter them in the field below the menu.
5. Select Run.
6. To stop a command before it finishes, select Stop.

Piper reads the command list from `.claude/commands` in the Wiki folder. A folder without that directory offers no commands.

Piper starts `claude --print` with the Wiki folder as the working directory. The command runs as Claude Code. It contacts the Anthropic API, and it can reach the network.

The run accepts file edits without a prompt. It permits Read, Write, Edit, Glob, Grep, WebFetch, and `python3` through Bash. Every other tool stops the run.

Piper saves an open edit before the command starts, and rescans the Wiki when the command stops. A command writes files outside the checks that Send to Wiki applies. Hooks in the Wiki folder still run, including a hook that creates Git commits.

Claude Code must be installed. Piper looks in `~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin`, and `/usr/local/bin`.

## Retry An Incomplete Export

If the draft saved but an index update failed, retry Send to Wiki with the same selected captures.

Piper finds the existing draft through its capture IDs and repairs the indexes and log. It does not apply revised review fields to that draft.

If another editor changed a Wiki file, wait for that edit to finish before retrying.

If a stale lock blocks export, first verify that no Piper export is active. Then remove `.piper-export.lock` from the Wiki root.

See [Wiki files](../concepts/wiki.md) for the write boundaries and concurrency limits.
