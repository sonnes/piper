---
title: "Export Captures"
summary: "Write selected captures to one Markdown file with Send to Wiki"
read_when:
  - Saving captures as a Markdown file
  - Checking what an export writes
---

# Export Captures

Send to Wiki writes selected captures to one Markdown file. You choose the name and the folder. Piper writes that file and changes no other file.

## Send Captures To A File

1. Open the capture panel with Command-1.
2. Click a note, then Command-click more notes.
3. Select Wiki in the selection bar.
4. Make sure that the Title is correct.
5. If you want, enter an HTTP or HTTPS Source URL.
6. Select Save.
7. In the save panel, choose a folder and a file name.
8. Select Read in Wiki to open the file, or select Done.

The sheet fills the title from the first line of the first note, up to 80 characters. It fills Source URL from the first note that has one. The proposed file name comes from the title, and the proposed folder is the Wiki root.

If you save the file inside the Wiki folder, Piper opens it after the folder scan. The browser selects its folder and clears the previous search. Select Read in Wiki to show the window. If you save it outside, Piper writes it and does not show it.

The captures stay in Piper after the export. While an export runs, Piper does not quit.

## File Format

```markdown
---
created: 2026-09-15T06:30:00Z
sources:
- https://example.com/article
title: Reading notes
---

# Reading notes

Text of the first note

---

Text of the second note

## Sources

* <https://example.com/article>
```

- `sources` holds the source URLs of the notes and the Source URL field, sorted, with no duplicates.
- If no note has a URL, the file has no `sources` key and no Sources section.
- A horizontal rule separates the notes.
- The file name has lowercase letters, numbers, and hyphens, up to 80 characters. An empty result becomes `capture.md`.

## Limits

- Piper writes the file atomically. If the save panel replaces an existing file, the old file is gone.
- The export builds no index, appends to no log, and makes no Git commit.
- Piper checks no metadata in the Wiki folder before or after the export.
