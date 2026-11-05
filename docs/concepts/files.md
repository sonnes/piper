---
title: "Wiki Files"
summary: "How Piper scans a folder, resolves links, and saves edits without losing changes"
read_when:
  - Understanding which files Piper shows
  - Debugging a link or a backlink
  - Changing the vault scan or the save path
---

# Wiki Files

Piper treats the Wiki folder as a plain folder of files. It applies no rule about file names, folder names, or metadata. A file needs no frontmatter, and a file without frontmatter is not a problem.

## Scan

Piper lists every regular file in the folder and its subfolders. It also lists every folder, including empty folders.

The scan skips these items:

- Hidden files and hidden folders, for example `.git`, `.claude`, and `.raw`
- Items named `node_modules`, `venv`, or `__pycache__`
- Symbolic links inside the folder

If Piper cannot read one file, it adds a problem to the list and continues. The sidebar shows the count as file warnings.

`VaultWatcher` watches the folder with `FSEventStream`. It groups changes for about 0.5 seconds, then Piper scans again. A change during a scan starts one more scan after that scan finishes. Piper also scans every four seconds while the main window shows.

A scan updates the tree, previews, and unread counts. If the open file changed, the scan loads the new text into the editor, or marks a conflict. See [Saving An Edit](#saving-an-edit). A deleted file stays open while the editor has text that is not on disk.

## Text And Previews

A file is text if it is UTF-8, has no NUL bytes, and is 4 MiB or less. Only a Markdown text file opens in the editor. Other text files show as read-only text. Every other file uses Quick Look.

## Frontmatter

For a Markdown file, Piper reads a YAML block at the top of the file. Piper uses these frontmatter keys:

- `title` sets the title in the window title bar and in Go to File. Without it, Piper uses the first heading, then the file name.

Frontmatter never changes how Piper sorts or groups files. The Source view shows the original frontmatter text, including invalid YAML.

## Links

| Link | Resolves from |
| --- | --- |
| `[text](other.md)` | The folder of the current file |
| `[text](/folder/other.md)` | The Wiki root |
| `[[Note]]` | A vault path, a title, or a file name |
| `[[folder/Note\|Label]]` | A vault path. The label is the link text. |
| `[[Note#Heading]]` | The file, then the heading text or its anchor |

A link without an extension gets `.md`. If a title matches more than one file, the link fails, and you must add the folder path. Repeated headings get the anchors `heading-1`, `heading-2`, and so on.

Piper refuses a path that leaves the Wiki root or goes through a symbolic link.

## Navigation History

The main window has one history. Opening a new file clears the forward history. A scan removes deleted files from the history.

## Saving An Edit

The editor holds the whole text of the file, with the frontmatter. It sends the text to Piper 120 ms after the last edit, and again when it closes the file.

Piper keeps three texts for an open file: the text that it last read or wrote (the baseline), the text of the editor, and the text on disk. A save reads the disk first, then compares the three texts:

| Condition | Result |
| --- | --- |
| The disk holds the baseline | Piper writes the editor text atomically. |
| The disk holds the editor text | Nothing to write. |
| The disk changed, and the editor has no edits | Piper loads the disk text into the editor. |
| The disk changed, and the editor has edits | A conflict. Piper writes nothing until you select Reload or Keep Mine. |

A deleted file with edits is also a conflict. Keep Mine writes the file again.

After a save, the baseline is the written text. So the scan after the save of Piper finds no change. Hubble.md uses the same rules.

The frontmatter keeps its comments, key order, and line endings, unless you change a property. Then the editor writes the frontmatter again.

Other apps do not share a lock with Piper. A change between the compare and the write is possible. Piper does not detect it.
