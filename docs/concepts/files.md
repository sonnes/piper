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

`VaultWatcher` watches the folder with `FSEventStream`. It groups changes for about 0.5 seconds, then Piper scans again. A change during a scan or an export starts one more scan after that work finishes. Piper also scans every four seconds while the Wiki window shows.

A scan updates the tree, the file list, previews, and unread counts. It keeps unsaved edits, including a draft whose file was deleted.

## Text And Previews

A file is text if it is UTF-8, has no NUL bytes, and is 4 MiB or less. Only a Markdown text file opens in the editor. Other text files show as read-only text. Every other file uses Quick Look.

## Frontmatter

For a Markdown file, Piper reads a YAML block at the top of the file. Piper uses these frontmatter keys:

- `title` sets the title in the file list. Without it, Piper uses the first heading, then the file name.
- `description` sets the summary in the file list, and search matches it.

Frontmatter never changes how Piper sorts or groups files. Raw view shows the original frontmatter text, including invalid YAML.

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

The Wiki window has one history. Opening a new file clears the forward history. A scan removes deleted files from the history.

## Saving An Edit

The editor holds the body of the file. The frontmatter stays outside the editor.

A save goes through these steps:

1. Piper reads the file from disk again.
2. It compares those bytes with the bytes it opened.
3. If they differ, or the file is gone, the save stops and the draft stays open.
4. Otherwise, Piper joins the original frontmatter bytes with the new body.
5. It replaces the file atomically.

The original frontmatter keeps its comments, key order, and line endings. The splitter works on the original text, so a CRLF file stays CRLF.

The editor library uses its own syntax for Wiki aliases. Piper translates between that syntax and `[[target|label]]`, so the file keeps `[[target|label]]`.

Other apps do not share a lock with Piper. A change between the compare and the replace is possible. Piper does not detect it.
