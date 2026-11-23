---
title: "Capture Notes"
summary: "Use Today to save notes and links, keep clipboard texts, capture a selection or a web page, and act on rows with Keep, Done, File, and Send"
read_when:
  - Saving a note or a link to read later
  - Reading the Today list and its lenses
  - Keeping a clipboard text
  - Capturing a selection from another application
  - Highlighting a web page or saving it to read later
  - Filing, sending, merging, or copying notes
---

# Capture Notes

Today is the first tab of the feed paper. It holds your notes, your links to read later, the new articles of your feeds, and the texts that you copy. Piper saves each note in a local database. See [Local storage](../concepts/storage.md) for the details.

## Today

Today has these parts, from the top:

| Part | Content |
| --- | --- |
| Capture field | Write a note, or paste a link to read later |
| Lenses | All, Notes, Reading, and Kept, each with a count |
| Continue Reading | The links that you started to read, up to 3. See All shows the Reading lens. |
| Day groups | Today, Yesterday, This Week, and Earlier |
| Done today | A fold at the end with the items that you marked as done today |
| Clipboard | The latest 3 clipboard texts. Show All shows the others. |

A lens filters the list:

| Lens | Rows |
| --- | --- |
| All | Notes, links, feed articles, and digests |
| Notes | Notes that are not links |
| Reading | Link captures |
| Kept | Each item that you kept, and each link with highlights or notes |

Press 1, 2, 3, or 4 to choose a lens, or select it. The rows of a note show a circle. The rows of a link, an article, and a digest show the icon of the site, with a dot while the item is new. The highlights and notes of a link show under its row.

A feed article shows in Today for 7 days. A link capture and its article show as one row. To choose how each feed reaches Today, see [Read feeds](feeds.md#choose-how-a-feed-reaches-today).

## Save A Note

1. Press Command-N, or select New Capture in the menu bar icon.
2. Type or paste text into the capture field.
3. Press Return.

Window > Today (Command-1) and New Capture in the More menu of the feed paper do the same thing. Each one shows Today and puts the cursor in the capture field.

Shift-Return adds a new line. A note goes to the section that the list shows. In All, Notes, Reading, and Kept, a note goes to Inbox. Piper keeps unfinished text in the field until you save it.

## Save A Link To Read Later

1. Paste a web link alone in the capture field.
2. Press Return.

Piper saves the link as a kept link capture. The link shows in the Reading lens and the Kept lens.

If the link is the address of a feed or the home page of a site, Return opens Sources and looks for its feeds. See [Read feeds](feeds.md#add-a-feed). To save such a link to read later instead, press Option-Return.

## Act On A Row

Each row has four verbs. The verbs show as round buttons on the selected row and on the row under the pointer. Each verb also has a key and an item in the More menu (the ellipsis button) and the context menu of the row.

| Verb | Key | Result |
| --- | --- | --- |
| Keep | K | Marks a note as kept, or removes the mark. Saves an article as a kept link capture. Saves a clipboard text as a kept note in Inbox. |
| Done | E | Marks a note as done, marks an article as read, or removes a clipboard text. Undo shows for 5 seconds. |
| File | F | Opens the File list. See [File a row](#file-a-row). |
| Send | S | Sends the row to a folder skill, or Ask starts a session about it. See [Work with agents](claude.md). |

Keep on a digest keeps each article of the digest. Done on a digest marks each article as read.

Other actions are in the More menu and the context menu: Open, Edit, Edit in New Window, Copy, Copy Link, Open in Browser, Show the Feed, and Delete. Delete is not available for an article or a digest.

Space and the circle of a note also mark it as done. The Delete key deletes the selected notes. Command-Z undoes the last change.

## File A Row

File puts the selected rows in one place. The File list has one search field for these places:

| Place | Result |
| --- | --- |
| A section | Moves notes and links to the section. An article becomes a kept link capture in the section. |
| A folder | Saves the rows as a new Markdown file in the folder. |
| A file | Adds the rows at the end of a Markdown file of the active folder. |

1. Select one or more rows.
2. Press F, or select the File button.
3. Type a part of the name of the place.
4. Press Up Arrow or Down Arrow to choose the place.
5. Press Return.

After Piper saves a row to a folder or a file, it marks the row as done or read.

## Act On Several Rows

1. Command-click a row to add it to the selection. Shift-click selects a range. Shift-Up Arrow and Shift-Down Arrow also add rows.
2. Use the selection bar at the bottom of the list, or press a key.

| Action | Key | Result |
| --- | --- | --- |
| Keep | K | Keeps each row |
| Done | E | Marks each row as done, with Undo |
| File | F | Files the rows in one place |
| Send | S | Sends each row with its default skill |
| Merge | M | Joins the notes with blank lines between them |
| Copy | Command-C | Copies the text of the rows. Command-Shift-C copies them as a numbered list. |

To end the selection, select the close button on the bar, or press Escape. Command-A selects all rows.

## Keep A Clipboard Text

Piper shows the texts that you copy while it runs, in the Clipboard part at the end of Today. These texts are not saved.

1. Copy text in any app.
2. Select the text in the Clipboard part.
3. Press K, or select Keep.

Keep saves the text to Inbox as a kept note. A copied web link becomes a link capture. Done removes the text. Clear Clipboard History in the menu of the Clipboard part removes every text. Select a selected text again to copy it to the clipboard.

The menu bar icon has a Capture Clipboard command. It saves the current clipboard text to the selected section.

Clipboard texts obey these rules:

- Piper keeps the 50 latest texts for 7 days. The history survives a restart.
- The same text shows once. A new copy of that text moves it to the top.
- Text that is already a saved note does not show.
- Piper skips images, text larger than 500 KB, and items that the source app marks concealed, transient, or autogenerated.

## Capture A Selection

Before you start, allow Accessibility access. See [Install Piper](install.md#allow-selection-capture).

1. Select text in another app.
2. Press and release Shift twice, within 0.35 seconds.

To use Control-Option-Space instead, change Shortcut in Settings > Capture. If another app holds Control-Option-Space, Piper reports the conflict.

Piper reads the selection directly. It does not simulate Copy, and it does not change the clipboard or the focus. The note records the source app, and its row shows the app name.

If the app in front shows a web page, such as Safari, Chrome, or Arc, the selection becomes a highlight of that page. See [Capture from a web page](#capture-from-a-web-page).

A secure text field or an empty selection creates no note. A small toast confirms each capture for three seconds.

If an app does not expose its selection, use the clipboard:

1. Copy the text in the source app.
2. Select Capture Clipboard in the menu bar icon.

## Capture From A Web Page

Piper finds the web page in front through Accessibility. Each web page has one link capture, which shows in Today and in the Reading lens. The highlights, the notes, and the reading position of the page belong to that capture. See [Keep a reading list](browse.md#keep-a-reading-list).

Two links name the same page when they differ only in tracking parameters, such as `utm_source`, in the fragment, or in `www.`.

### Highlight Text

1. Select text on the web page.
2. Press Shift twice.

Piper saves the selection as a highlight under the link capture of the page. If Piper does not have the page, it adds the page first. The link capture goes to the selected section.

The toast shows the page title and the number of highlights from the page, for six seconds. The toast does not take the focus, so you can continue to read in the browser. Continue in Piper opens the page in the tab that you last chose for its site.

The page in the browser shows no mark. The mark shows in the Reader tab.

### Add A Note To A Highlight

1. While the highlight toast shows, press Shift twice again on the same page. Do not select other text.
2. Type the note.
3. Press Return.

On another page, Shift twice saves that page or its selection, as usual. The note field takes the focus. After Return, the focus goes back to the browser. Escape closes the field and saves no note. If you click another window, Piper saves the text that you typed.

Piper adds the note to the highlight, after the quote.

### Save A Page For Later

1. Open the page in the browser. Do not select text.
2. Press Shift twice.

Piper adds the page to Today, with its title and reading time. Read Now opens the page on a reader paper. If Piper already has the page, the toast shows Already in Reading.

### Read A Page Behind A Login

Piper loads a page in its own web view, and that web view does not have the sign-ins of your browser. For this reason, each capture from a web page also keeps the page text that the browser shows. If the page does not load in Piper, or if it gives much less text, the Reader tab shows the kept text. The kept text has no headings or lists.

## Organize Notes

Sections group notes. The Today index lists the lenses, the sections, Done, and Sources. To show the index, select the Today tab.

- To create a section, select New Section on the Today index or in the More menu of the feed paper.
- To create or choose a section from the capture field, type `# Research` alone and press Return. The list then shows that section.
- To show the notes of one section, select the section on the Today index.
- To run a folder skill, type `/` and the skill name. See [Work with agents](claude.md#run-a-skill-from-the-composer).
- To find rows, press Command-F. Search matches every row of Today. To end the search, press Escape.

Section names have 1 to 80 characters and ignore case.

On the Today index, right-click a section to open Edit Section or Delete Section. Edit Section changes its name. Delete Section moves its notes to Inbox and removes the section. Undo restores the previous name or the deleted section and its notes. Inbox has a fixed name and cannot be deleted.

## Edit A Note

Select a note, then press Return or click it again, to open it on a reader paper. You edit the note in place on the paper. Piper saves the change shortly after you stop typing. A note that holds only a link opens in the Reader tab or the Web tab, and it has no editor. See [Read captures](browse.md#read-captures).

- To edit the note in a sheet, Control-click it and select Edit. Select Save to keep the change.
- To open the note in a separate editor window, press Command-Return.

Done on the Today index groups the completed notes by the month in which you marked them as done. The newest month is first. A completed note shows an indigo check, and a line goes through its text. Search in Done matches only completed notes. Done on a completed note reopens it. Reopened notes return to their original sections.

If you close a changed editor or quit Piper, Piper asks you to Save, Discard, or Cancel. A failed save keeps the draft.

For all shortcuts, see [Keyboard shortcuts](shortcuts.md).
