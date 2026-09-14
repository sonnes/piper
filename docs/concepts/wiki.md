---
title: "Wiki Files And Exports"
summary: "Metadata, path handling, and the limits of draft export"
read_when:
  - Changing the Wiki repository
  - Understanding export recovery and compatibility
---

# Wiki Files And Exports

## Creation

Create Wiki initializes an absent or empty folder with an OKF 0.2 `index.md`. It refuses nonempty folders and never adds sample documents.

## Reading

The scanner reads Markdown recursively. It skips hidden directories, symbolic links, and common dependency directories.

Browser scans include indexes and logs. Export scans exclude these generated files when validating concept metadata.

Malformed YAML produces a read problem while preserving the raw document text. The browser supports headings, lists, task markers, quotes, fenced code, tables, and footnotes.

The renderer does not implement full CommonMark. It does not execute raw HTML or fetch remote images. Archived sources under `.raw` remain outside browsing.

Relative links resolve from the current document. Bundle-absolute links resolve from the Wiki root. File access rejects paths outside that root and symlink components.

Wiki links also resolve by vault path, title, or filename. Ambiguous titles require a folder path. Heading links accept heading text or its generated anchor.

Backlinks derive from Markdown and Wiki links in the current scan. Code examples, image references, and self-links do not create backlinks.

The workspace has one navigation history. A new visit replaces forward history. Refresh removes missing files from history.

## Metadata

The reader exposes `type`, `title`, `description`, `status`, `sources`, `verified`, and `stale_after` metadata where present.

Trust labels derive from verification entries. Export writes neither `verified` nor `trust_tier`.

Before export, Piper requires `okf_version: "0.2"` in the root index. Scanned concepts require a nonempty `type` and no `trust_tier` field.

These checks cover Piper's current integration. They do not implement the full Wiki validator.

## Existing Notes

The native Markdown editor always accepts body edits. Save or Command-S writes them to the file. Navigation and closing prompt for unsaved changes. The original YAML prefix remains intact, including comments, field order, and line endings.

An adapter translates Wiki aliases between Piper syntax and the editor library. Files retain `[[target|label]]` syntax.

Saving compares the original file bytes with the current file before an atomic replacement. A mismatch or missing file leaves the draft open.

These edits do not regenerate indexes or append export log entries. Other applications do not share a file lock with the editor.

## New Drafts

The exporter writes `Source` documents under `sources/` and `Note` documents in other supported destinations. Each document has `status: draft`.

Generated metadata identifies `process:piper`. Capture IDs, timestamps, source applications, and source URLs preserve provenance.

Filename collisions receive numeric suffixes. A repeated selection matches the set of `piper_capture_ids` and reuses that draft.

Indexes derive from the complete scan. Export replaces their contents, so handwritten index additions do not survive regeneration.

## Write Boundaries

The draft write refuses to overwrite an existing file. Index and log writes replace individual files atomically.

The export is not one atomic transaction across all files. An error after draft creation leaves the draft available for retry.

An exclusive `.piper-export.lock` serializes Piper exports. Content comparisons detect changes before derived writes. Other editors do not share this lock.

A race remains possible between comparison and replacement. Release validation must cover external edits and interrupted exports.

## Commands

Piper runs the slash commands that the Wiki folder defines in `.claude/commands`. It reads the name, description, and argument hint from each file's frontmatter. It holds no command definitions of its own.

A command runs as a `claude --print` subprocess with the Wiki folder as the working directory. Piper saves an open edit first, and rescans the folder when the subprocess stops.

The subprocess writes outside the boundaries in this document. The export lock does not hold it back. The metadata checks do not apply to it. Hooks in the Wiki folder run with it.
