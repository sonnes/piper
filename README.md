---
title: "Piper"
summary: "Native macOS capture notes and a separate local Wiki browser"
read_when:
  - Building Piper for the first time
  - Finding documentation and implementation plans
---

# Piper

Piper captures selected text and clipboard entries into local notes. A separate Wiki window reads and edits Markdown files. Send to Wiki creates unverified drafts.

## Quick Start

Requirements: macOS 14 or later, a Swift 5.9-compatible toolchain with the macOS SDK, and Make. The first build downloads pinned Yams and SwiftMarkdownEngine dependencies.

From the repository directory, run:

```sh
make test
make run
```

`make run` builds and opens `build/Piper.app`. The bundle uses an ad hoc signature for local development.

Piper opens the capture panel with Inbox as the initial section. Clipboard text appears as unsaved previews. Click a preview to save it.

Enable Accessibility to capture a selection with double-Shift or Control-Option-C. Selection capture preserves the clipboard and the source application's focus.

The Wiki folder defaults to `~/Desktop/Wiki`. Create Wiki initializes an empty folder. Settings provides a folder picker and capture permission controls.

## Windows

| Window | Purpose |
| --- | --- |
| Capture panel | Enter, organize, edit, and copy notes. Review a Wiki export. |
| Wiki browser | Browse folders, search, read and edit Markdown, and inspect source details. |
| Note editor | Edit a capture in a separate window with explicit Save Changes. |

The capture panel stays separate from the Wiki browser. Saving a draft offers Read in Wiki without opening the browser automatically.

Piper uses Graphite surfaces, Cobalt accents, and bundled IBM Plex Mono text. Colors follow the system appearance. The Wiki reader retains its font and paper preferences.

## Documentation

- [Documentation overview](docs/README.md)
- [Build and capture notes](docs/howto/capture.md)
- [Browse and export to your Wiki](docs/howto/wiki.md)
- [Architecture](docs/layers/architecture.md)
- [Capability coverage](docs/capabilities/README.md)
- [Implementation plans](docs/plans/README.md)

## Development

| Command | Result |
| --- | --- |
| `make build` | Build and sign the local application bundle. |
| `make run` | Build and open the application. |
| `make test` | Run the Swift test suite. |
| `make release` | Test, build, sign, notarize, and validate a DMG for the build Mac's architecture. |

The [release instructions](docs/howto/capture.md#build-a-signed-release) describe the required Developer ID credentials. Release builds contain no sample data or demo mode.

`Sources/Piper/` contains the application. `Sources/CSQLite/` exposes system SQLite. `Tests/PiperTests/` contains the automated tests.

`PiperTheme.swift` defines the shared colors and typography. `Resources/AppIcon.png` is the icon master. The build creates `Resources/Piper.icns` and bundles the fonts, bird mark, and licenses.

Global capture still needs manual testing across applications after Accessibility approval. The [capability matrix](docs/capabilities/README.md) records other limits.
