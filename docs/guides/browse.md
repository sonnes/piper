---
title: "Browse And Edit Files"
summary: "Search, read, preview, and edit the files in your folders, and read captures in Inbox"
read_when:
  - Adding a folder
  - Searching, reading, or editing a file
  - Reading web links from captures
---

# Browse And Edit Files

The main window keeps one or more folders in the sidebar. The selected folder is the active vault. Any folder works: Piper needs no index, no frontmatter, and no folder names. See [Wiki files](../concepts/files.md) for the scan rules.

Open the window with Command-2. Command-0 opens it on the Home page.

## Add A Folder

The default folder is `~/Desktop/Wiki`.

1. Open the main window with Command-2.
2. Select the + button beside the Folders heading in the sidebar.
3. Select one or more folders.
4. Select Add.

Add Folder is also in the sidebar context menu, in the More menu of the toolbar, and in Settings > General.

Piper keeps the added folders across restarts. Select a folder in the sidebar to show its folder tree.

To take a folder out of the sidebar, Control-click it and select Remove Folder. You can also select it in Settings > General and select the minus button. The folder on disk does not change. The last folder cannot be removed.

Home search uses the selected folder. Switching folders clears the previous search and asks you to resolve unsaved edits.

## Find Your Way Around

The window has three panes:

| Pane | Content |
| --- | --- |
| Sidebar | Library (Home, Inbox with a row for each other section, Clipboard, and Archived) and Folders (every folder, and the tree of the active folder) |
| List | The files of the selected folder, the captures, or the clipboard history |
| Detail | The selected file, Home, or the selected capture |

The window title names the sidebar selection. The subtitle shows a count, or the folder path on Home.

The toolbar has these controls:

| Control | Action |
| --- | --- |
| Toggle Sidebar | Hides or shows the sidebar |
| New Capture | Moves the focus to the note composer in the main window |
| Back and Forward | Moves through the files you opened |
| Preview and Source | Shows the formatted file or its text |
| Mark as Done | Marks the selected capture as done, or opens it again |
| More | New Section, Add Folder, Reveal in Finder, Refresh, and Settings |

Select the vault root to see the files at the top level. The folder tree shows nested and empty folders. Files show only in the list.

Home hides the list. The window restores its frame, the pane widths, the selection, the open folders, and the last file.

## Search From Home

Home has one search field and a list of the six most recent files.

1. Press Command-0, or select Home in the sidebar.
2. Type text.
3. Use the Up and Down keys to select a result.
4. Press Return.

Plain text lists files that match by name, then files that match by text. Then it lists matching app actions. If nothing matches, the last row searches every file for the text.

Type `>` to list app actions: New Capture, Browse Files, Add Folder, Reveal in Finder, Capture Clipboard, and Settings.

## Search The Current List

The search field sits at the top of the list. In a folder, the sort menu sits next to it.

File search filters only the files in the selected folder. Each word must match a title, a path, a description, or the body text. Selecting another folder clears the file search.

In Inbox, search filters the notes of every section. In Clipboard, search filters the clipboard history.

Home searches the whole vault. Its Search All Files action opens an All Files list with the same search field. A leading `>` selects actions only in Home.

## Track Unread Files

A file you have not opened has a blue dot. A file becomes unread again when its modification time changes. A save that you make in Piper keeps the file read.

The window subtitle shows the number of files and the number of unread files in the folder. Sidebar counts include unread files in subfolders. A folder with no unread files shows no count. Read state is separate for each folder and survives a restart.

## Read A File

Select a file in the list. The sort menu next to the search field sorts by Name or by Date.

A Markdown file opens in the editor, in a centered column. The modification date shows above the text. After a change that is not saved, the date line ends with "Edited". If the file has no heading, its title shows under the date.

Wiki links use `[[Note]]`, `[[folder/Note|Label]]`, and `[[Note#Heading]]`. Relative Markdown links open from the current file. HTTP, HTTPS, and `mailto` links open in your default app.

To ask Claude about the open file, press Option-Command-C. See [Send notes to Claude](claude.md#talk-to-claude-in-a-session).

Use Command-[ and Command-] to go back and forward. To scan the folder again, press Command-R, or select Refresh in the More menu.

## Change Reading Preferences

Open Settings with Command-comma, then select Reading. The preferences change how Piper shows a Markdown file. They do not change the file.

| Preference | Values | Default |
| --- | --- | --- |
| Font | Mono, Serif, Sans | Sans |
| Size | 13 to 24 points | 18 points |
| Paper | Paper, Sepia, Slate | Paper |
| Appearance | System, Light, Dark | System |

Reset to Defaults restores the defaults.

## Preview Other Files

Piper opens every file in the vault, not only Markdown.

- HTML, RTF, images, PDFs, and other rich files use the macOS Quick Look preview.
- JSON, plain text, source code, and other text files show as read-only monospaced text.
- Open in Default App opens the file in another app. The folder button reveals the file in Finder.

A file larger than 4 MiB, or a file that is not UTF-8 text, uses the Quick Look preview. Piper cannot edit it, even if it is Markdown.

## View The Source

For a Markdown or HTML file, select Source in the toolbar. Source shows selectable, read-only text in a monospaced font. Long lines wrap at the width of the pane. The choice stays for the next file.

For Markdown, Source includes the frontmatter and your unsaved body edits. Select Preview to continue editing. For HTML, Preview shows the page and Source shows its markup. The control is off for a file that has no source text.

## Edit A Markdown File

1. Select a Markdown file.
2. Type in the page.
3. Press Command-S.

The editor is SwiftMarkdownEngine 0.12.0. Formatting shows as you type, and Markdown markers show near the caret. Paste inserts plain text. Command-Z reverses an edit.

The editor does not show frontmatter. A save keeps the frontmatter bytes, the Wiki link text, and the line endings of the file.

Piper asks you to Save, Discard, or Cancel when a change is unsaved and you do one of these actions:

- Open another file, go back, or go forward.
- Change the folder.
- Close the window or quit Piper.
- Run a command.

If another app changed the file after you opened it, Save refuses to write. Your draft stays open.

## Read Captures In Inbox

Select Inbox in the sidebar to see every section in one list. Inbox also becomes the section for new notes. Select a section under Inbox to scroll the list to it and make it the section for new notes. Select Clipboard to see the clipboard history. See [Capture notes](capture.md) for the list and its actions.

Select one capture to show it in the detail pane. The date shows at the top. Type in the text to change the note. Piper saves the change shortly after you stop typing. If the note looks like source code, the text uses a monospaced font. The editor does not change quotes or dashes while you type. The source app shows under the text.

A web link in a capture shows as a card with the host, the path, Open Reader, and Open in Browser. A capture that contains only a URL opens the page at once.

The reader bar has these controls: Note, Back, Forward, the address with Reload, Capture, and Open in Browser. If a page fails to load, select Try Again.

To save part of a page as a new capture:

1. Select text on the page.
2. Select Capture in the reader bar.

If no text is selected, Capture saves the whole page text. The new capture goes to Inbox with the page title and URL. The original capture does not change.

Piper loads HTTP and HTTPS pages only. A page needs a network connection.

For all shortcuts, see [Keyboard shortcuts](shortcuts.md).
