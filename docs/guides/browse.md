---
title: "Browse And Edit Your Wiki"
summary: "Search, read, preview, and edit the files in your Wiki folder, and read captures in Inbox"
read_when:
  - Choosing a Wiki folder
  - Searching, reading, or editing a file
  - Reading web links from captures
---

# Browse And Edit Your Wiki

The Wiki window shows one folder of files. Piper calls this folder the vault. Any folder works: Piper needs no index, no frontmatter, and no folder names. See [Wiki files](../concepts/files.md) for the scan rules.

Open the window with Command-2. Command-0 opens it on the Home page.

## Choose A Folder

The default folder is `~/Desktop/Wiki`.

1. Open the Wiki window with Command-2.
2. Open the folder menu in the toolbar.
3. Select Choose Wiki Folder.
4. Select a folder.

The folder menu also has Reveal Wiki in Finder and Settings. Settings > Wiki has the same folder choice.

## Find Your Way Around

The window has four panes:

| Pane | Content |
| --- | --- |
| Sidebar | Library (Home and Inbox) and Folders (the vault root and its folder tree) |
| File list | The files of the selected folder, or the captures in Inbox |
| Detail | The selected file, Home, or the selected capture |
| Inspector | Outline, Links, and Info for the selected file |

Select the vault root to see the files at the top level. The folder tree shows nested and empty folders. Files show only in the file list.

The toggle button at the left of the toolbar hides the sidebar. The Inspector button at the right shows or hides the inspector. Piper remembers the inspector choice. Home hides the file list and the inspector, and Inbox hides the inspector.

The window restores its frame, the pane widths, the selection, the open folders, and the last file.

## Search From Home

Home has one search field and a list of the six most recent files.

1. Press Command-0, or select Home in the sidebar.
2. Type text.
3. Use the Up and Down keys to select a result.
4. Press Return.

Plain text lists files that match by name, then files that match by text. Then it lists the commands, skills, and actions that match. If nothing matches, the last row searches every file for the text.

Type `/` to list commands and skills. Type `>` to list app actions: New Capture, Browse Files, Choose Wiki Folder, Reveal in Finder, Capture Clipboard, and Settings. See [Run commands and skills](commands.md).

## Search From The Toolbar

The search field at the right of the toolbar filters the file list. The filter reads the whole vault, not only the selected folder. Each word must match a title, a path, a description, or the body text.

If the text starts with `/` or `>`, the window shows Home and gives it the text. If Inbox is selected, the field filters captures.

## Track Unread Files

A file you have not opened has a blue dot and a heavier title. A file becomes unread again when its modification time changes. A save that you make in Piper keeps the file read.

Sidebar counts include unread files in subfolders. A folder with no unread files shows no count. Read state is separate for each Wiki folder and survives a restart.

## Read A File

Select a file in the file list. The file list sort menu sorts by Name or by Date.

A Markdown file opens in the editor, in a centered column. The header shows the folder, the file name, and the modification date. The status bar shows the path, the word count, and whether the file has unsaved changes.

The inspector has three tabs:

| Tab | Content |
| --- | --- |
| Outline | The headings. Select one to scroll to it. |
| Links | The files that link to this file |
| Info | Size, modification date, every frontmatter key, the path, and actions |

The Info actions are Reveal in Finder and Discard Changes.

Wiki links use `[[Note]]`, `[[folder/Note|Label]]`, and `[[Note#Heading]]`. Relative Markdown links open from the current file. HTTP, HTTPS, and `mailto` links open in your default app.

Use Command-[ and Command-] to go back and forward. Press Command-R, or select Refresh in the toolbar, to scan the folder again.

## Change Reading Preferences

Open Settings with Command-comma, then select Reading. The preferences change the page only. They do not change any file.

| Preference | Values | Default |
| --- | --- | --- |
| Paper | Paper, Sepia, Slate | Paper |
| Font | Monospace, Serif, Sans Serif | Sans Serif |
| Size | 13 to 24 points | 18 points |
| Appearance | System, Light, Dark | System |

Reset restores the defaults.

## Preview Other Files

Piper opens every file in the vault, not only Markdown.

- HTML, RTF, images, PDFs, and other rich files use the macOS Quick Look preview.
- JSON, plain text, source code, and other text files show as read-only monospaced text.
- Open in Default App opens the file in another app. The folder button reveals the file in Finder.

A file larger than 4 MiB, or a file that is not UTF-8 text, uses the Quick Look preview. Piper cannot edit it, even if it is Markdown.

## Edit A Markdown File

1. Select a Markdown file.
2. Type in the page.
3. Press Command-S, or select Save in the inspector.

The editor is SwiftMarkdownEngine 0.12.0. Formatting shows as you type, and Markdown markers show near the caret. Paste inserts plain text. Command-Z reverses an edit.

The editor does not show frontmatter. A save keeps the frontmatter bytes, the Wiki link text, and the line endings of the file.

Piper asks you to Save, Discard, or Cancel when a change is unsaved and you do one of these actions:

- Open another file, go back, or go forward.
- Change the Wiki folder.
- Close the window or quit Piper.
- Run a command.

If another app changed the file after you opened it, Save refuses to write. Your draft stays open.

## Read Captures In Inbox

1. Select Inbox in the sidebar.
2. Select a capture in the file list.

The capture shows its text, with Mark as Done and Edit. Web URLs in the text are links. A capture that contains only a URL opens the page at once.

Piper opens a web link inside the window. The page controls are Show Note, Back, Forward, Reload, and Open in Browser. If a page fails to load, select Retry.

To save part of a page as a new capture:

1. Select text on the page.
2. Select Capture at the bottom of the page.

If no text is selected, Capture saves the whole page text. The new capture goes to Inbox with the page title and URL. The original capture does not change.

Piper loads HTTP and HTTPS pages only. A page needs a network connection.

For all shortcuts, see [Keyboard shortcuts](shortcuts.md).
