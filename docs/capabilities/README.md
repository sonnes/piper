---
title: "Capability Coverage"
summary: "Current implementation, validation evidence, and known gaps"
read_when:
  - Checking whether a feature exists
  - Choosing release validation work
---

# Capability Coverage

Status reflects the local implementation on September 12, 2026. Implemented does not imply distribution readiness.

| Capability | Status | Evidence Or Limit |
| --- | --- | --- |
| Separate capture and Wiki windows | Implemented | Native window inspection completed |
| Manual notes, sections, and search | Implemented | Local state operations |
| Merge, copy, completion, move, delete, undo | Implemented | Persistence, merge, and copy tests |
| Composer draft persistence | Implemented | UserDefaults storage |
| Explicit note editing | Implemented | Save Changes, quit protection, and conflicting editor tests |
| Global selection capture | Implemented; manual check skipped | Accessibility enabled; gesture tests pass; cross-app compatibility remains unverified |
| Capture Clipboard | Implemented | Exact text and unchanged pasteboard tests |
| Clipboard ghost cards | Implemented | Temporary buffer, click-to-save, deduplication, failure recovery, and Undo tests |
| Custom capture shortcut | Partial | Double-Shift or Control-Option-C presets |
| Local SQLite persistence | Implemented | Restart, locked database, invalid records, unsupported versions, and stale writer tests |
| Wiki folders, search, and reading | Implemented | Nested tree, search, and file-scan tests |
| Single-document navigation | Implemented | Back/Forward history and missing-file tests |
| Wiki links, outline, and backlinks | Implemented | Path, title, anchor, and backlink tests |
| Focus mode and reading controls | Implemented | Native light-appearance checks passed for focus, heading navigation, and scrolling |
| Document sidebar | Implemented | Manual save, document actions, preview, reading preferences, and collapsible note information |
| Live Wiki editing with manual save | Implemented | Save/Discard/Cancel, conflict, refresh, and unchanged-file tests |
| Markdown rendering | Partial | Lists, task markers, quotes, code, tables, and footnotes; incomplete CommonMark support |
| Empty Wiki creation | Implemented | Creates only an index; existing files remain unchanged |
| Wiki export | Implemented | Draft, collision, retry, and path tests |
| OKF validation | Partial | Selected metadata checks; no full validator integration |
| Concurrent external edits | Partial | Comparisons detect changes; no shared transaction |
| Automatic document source URL | Partial | HTTP/HTTPS AXDocument value when the source application provides it |
| Image and file attachments | Deferred | Text captures only |
| Existing Wiki concept editing | Implemented | Same-page editing, preserved scroll position and undo, YAML preservation, alias conversion, and external-change checks |
| Distribution signing and notarization | Verified locally | Apple accepted the 0.1.0 arm64 DMG; stapling and Gatekeeper checks passed. Clean-Mac installation remains open |

All 48 automated tests pass. [Manual validation](../howto/validate.md) records release checks and application compatibility.

See [release readiness](../plans/release-readiness.md) for delivery criteria.
