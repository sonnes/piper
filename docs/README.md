---
title: "Documentation"
summary: "Guides, concepts, internals, and release status for Piper"
read_when:
  - Finding a guide
  - Deciding where a new page belongs
---

# Documentation

Piper captures text into a local database and browses a folder of files.

## Use Piper

- [Install Piper](guides/install.md): download the signed DMG, build from source, allow Accessibility access, and publish a signed release.
- [Capture notes](guides/capture.md): the capture panel, clipboard history, selection capture, and sections.
- [Send notes to Claude](guides/claude.md): talk to Claude Code in a folder, and send notes to its skills.
- [Browse and edit files](guides/browse.md): folders, Home, search, unread files, previews, editing, and the Inbox reader.
- [Keyboard shortcuts](guides/shortcuts.md): every shortcut in both windows.

## Understand The Data

- [Local storage](concepts/storage.md): the capture database, preferences, read state, and backups.
- [Wiki files](concepts/files.md): scan rules, links, backlinks, and safe saves.

## Change The Code

- [Architecture](internals/architecture.md): modules, windows, data flow, and the source map.
- [Coding guidelines](internals/coding-guidelines.md): values, composition, threading, and state changes.

## Ship A Release

- [Capability status](release/status.md): what exists, its evidence, and the known gaps.
- [Validate a build](release/validate.md): automated tests and manual checks.
- [Release readiness](release/readiness.md): open acceptance work.

## Page Conventions

| Folder | Content |
| --- | --- |
| `guides/` | Tasks for a person who uses Piper |
| `concepts/` | How Piper stores and treats data |
| `internals/` | How the code is built and the rules for changing it |
| `release/` | Status, validation, and open release work |

Each page starts with `title`, `summary`, and `read_when` frontmatter. Pages are plain Markdown and need no documentation site.

A guide or a concept page describes current behavior only. Unfinished work goes in [Release readiness](release/readiness.md). Local planning notes go in `docs/plans/archive/`, which Git ignores.
