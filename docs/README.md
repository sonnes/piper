---
title: "Documentation"
summary: "Guides, architecture, concepts, and delivery plans for Piper"
read_when:
  - Finding a guide
  - Choosing between current behavior and planned work
---

# Documentation

Piper keeps capture notes in a local database. The Wiki browser reads and edits Markdown files. An explicit export connects these stores.

## Start Here

- [Capture notes](howto/capture.md): build the app, enable capture, and organize notes.
- [Use your Wiki](howto/wiki.md): choose a folder, read documents, and save drafts.

## Understand The Implementation

- [Architecture](layers/architecture.md): window ownership and data flow.
- [Local storage](concepts/storage.md): persistence, preferences, and undo.
- [Wiki files](concepts/wiki.md): metadata, links, exports, and recovery limits.
- [Capabilities](capabilities/README.md): implementation status and evidence.

## Plan And Validate Changes

- [Plans](plans/README.md): delivery status and the original proposal.
- [Release readiness](plans/release-readiness.md): remaining work and acceptance criteria.
- [Manual validation](howto/validate.md): permission, window, and export checks.

## Page Conventions

The structure follows pi-go: `layers/`, `howto/`, `concepts/`, and `capabilities/`. Piper adds `plans/` for delivery work.

Pages use `title`, `summary`, and `read_when` frontmatter. Plain Markdown works without a documentation site or MDX components.

Current behavior belongs in guides and concepts. Plans label unfinished work explicitly. The archived proposal preserves the original assumptions.
