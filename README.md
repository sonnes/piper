---
title: "Piper"
summary: "Native macOS capture notes and a separate local Wiki browser"
read_when:
  - Building Piper for the first time
  - Finding documentation and implementation plans
---

# Piper

Piper is a native macOS application for capturing text. It saves selected text and clipboard entries as local notes in a floating panel beside the application you work in. A separate window browses and edits a folder of Markdown files. You can export a capture into that folder as a draft.

Capture and Wiki browsing need no account, cloud service, telemetry, or network connection. Notes stay in a local SQLite database. Wiki documents stay as Markdown files on disk.

Wiki Commands is the one exception. It starts Claude Code, and Claude Code contacts the Anthropic API.

## Status

Piper is at version 0.1.0. No signed build is available for download, so you must build it from source.

Selection capture works. Its compatibility across applications is unverified. Markdown rendering covers common syntax and omits parts of CommonMark. Piper captures text only, and image and file attachments do not exist. The [capability matrix](docs/capabilities/README.md) records the status of each feature.

## Requirements

- macOS 14 or later
- A Swift 5.9 toolchain with the macOS SDK
- Make
- Claude Code, for Wiki Commands only

## Quick Start

Clone the repository, then build and open the application:

```sh
git clone https://github.com/sonnes/piper.git
cd piper
make run
```

The first build downloads the pinned Yams and SwiftMarkdownEngine dependencies. `make run` writes `build/Piper.app` and opens it. The bundle uses an ad hoc signature for local development.

Piper opens the capture panel with Inbox as the first section. Clipboard text appears as an unsaved preview. Click a preview to save it.

To capture a selection with double-Shift or Control-Option-Space, enable Accessibility for Piper in System Settings. Selection capture keeps the clipboard and the focus of the source application.

The Wiki folder defaults to `~/Desktop/Wiki`. Create Wiki makes an empty folder. Settings has a folder picker and the capture permission controls.

## Windows

| Window | Purpose |
| --- | --- |
| Capture panel | Enter, organize, edit, and copy notes. Review a Wiki export. |
| Wiki browser | Browse folders, search, read and edit Markdown, and inspect source details. |
| Note editor | Edit a capture in a separate window with explicit Save Changes. |

The capture panel is separate from the Wiki browser. After you save a draft, Piper offers Read in Wiki and does not open the browser for you.

Piper uses Graphite surfaces, Cobalt accents, and bundled IBM Plex Mono text. Colors follow the system appearance. The Wiki reader keeps its own font and paper preferences.

## Wiki Commands

A Wiki folder can define its own Claude Code slash commands in `.claude/commands`. Piper reads that folder and runs the commands in place. It carries no copy of them.

1. Open the Wiki window.
2. Select the terminal button in the left ribbon.
3. Select a command, then enter its arguments.
4. Select Run.

Piper starts `claude --print` with the command as the prompt and the Wiki folder as the working directory. Output appears in the sheet as it arrives. Piper rescans the Wiki when the command stops.

The run accepts file edits without a prompt. It permits Read, Write, Edit, Glob, Grep, WebFetch, and `python3` through Bash. Every other tool stops the run.

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
| `make release` | Test, build, sign, notarize, and validate a DMG for the architecture of the build Mac. |

`make release` reads Developer ID credentials from a local `.envrc` file, which Git ignores. The [release instructions](docs/howto/capture.md#build-a-signed-release) list the required variables. Release builds contain no sample data or demo mode.

`Sources/Piper/` contains the application. `Sources/CSQLite/` exposes system SQLite. `Tests/PiperTests/` contains the automated tests.

`PiperTheme.swift` defines the shared colors and typography. `Resources/AppIcon.png` is the icon master. The build creates `Resources/Piper.icns` and bundles the fonts, bird mark, and licenses.

## License

Piper is licensed under the [Apache License 2.0](LICENSE).

The application bundles the components below. Their license texts are in [`Licenses/`](Licenses/) and ship inside the application bundle.

| Component | License |
| --- | --- |
| [Yams](https://github.com/jpsim/Yams) | MIT |
| [libyaml](https://github.com/yaml/libyaml), vendored in Yams | MIT |
| [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine) | Apache 2.0 |
| [HighlighterSwift](https://github.com/smittytone/HighlighterSwift) | MIT and BSD 3-Clause |
| [SwiftMath](https://github.com/mgriebling/SwiftMath) | MIT |
| [IBM Plex Mono](https://github.com/IBM/plex) | SIL Open Font License 1.1 |

## Attribution

Piper adapts its coding guidelines, window architecture, and interface values from [NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire), by Brent Simmons and the NetNewsWire contributors. NetNewsWire is Copyright (c) 2002-2025 Brent Simmons and uses the MIT license. Piper ships no NetNewsWire code. The license text is in [`Licenses/NetNewsWire.txt`](Licenses/NetNewsWire.txt).

NetNewsWire does not endorse Piper and has no connection to this project.
