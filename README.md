# Piper

Piper is a native macOS application for capturing text. It saves selected text and clipboard entries as local notes in a floating panel beside the application you work in. A separate window browses and edits a folder of files, such as a Markdown wiki.

Capture and browsing need no account, cloud service, telemetry, or network connection. Notes stay in a local SQLite database. Wiki files stay on disk as they are. The web reader connects to the pages you open.

## Status

Piper is at version 0.1.0. No signed build is available for download, so you must build it from source.

Selection capture works, but its compatibility across applications is unverified. Markdown rendering does not cover all of CommonMark. Piper captures text only. The [capability status](docs/release/status.md) page records each feature and its evidence.

## Requirements

- macOS 14 or later
- A Swift 5.9 toolchain with the macOS SDK
- Make

## Quick Start

1. Clone the repository and build the app:

   ```sh
   git clone https://github.com/sonnes/piper.git
   cd piper
   make run
   ```

2. Type a note in the capture panel and press Return.
3. Copy text in another app. Click its card in the panel to save it to Inbox.
4. Press Command-2 to open the main window on `~/Desktop/Wiki`.

To choose another folder, use the folder menu in the Wiki toolbar. To capture a selection with Shift pressed twice, allow Accessibility access first. See [Install Piper](docs/guides/install.md).

## Windows

| Window | Purpose |
| --- | --- |
| Capture panel | Save, organize, edit, and copy notes |
| Main window | Search, read, preview, and edit files, and read captures in Inbox |
| Note editor | Edit one capture in a separate window with Save |
| Settings | Folders, the capture shortcut, and reading preferences |

The capture panel and the main window take turns on screen. Command-1 shows the panel, and Command-2 shows the main window. Neither closes, so a draft stays open.

Both windows use the system font and colors, with one blue accent. Both follow the system appearance.

## Documentation

- [Documentation overview](docs/README.md)
- [Capture notes](docs/guides/capture.md)
- [Browse and edit files](docs/guides/browse.md)
- [Keyboard shortcuts](docs/guides/shortcuts.md)
- [Architecture](docs/internals/architecture.md)

## Development

| Command | Result |
| --- | --- |
| `make build` | Build and sign the local application bundle |
| `make run` | Build and open the application |
| `make test` | Run the Swift test suite |
| `make release` | Test, build, sign, notarize, and validate a DMG for the architecture of the build Mac |

`make release` reads Developer ID credentials from a local `.envrc` file, which Git ignores. [Build a signed release](docs/guides/install.md#build-a-signed-release) lists the variables.

`Sources/Modules/` holds the model modules, and `Sources/Piper/` holds the application. `Sources/CSQLite/` exposes system SQLite. Each module has a test target in `Tests/`. See [Architecture](docs/internals/architecture.md) and [Coding guidelines](docs/internals/coding-guidelines.md).

`Resources/AppIcon.png` is the icon master. The build creates `Resources/Piper.icns` and bundles the fonts, the bird mark, and the licenses.

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

The initial idea for Piper came from [Copper](https://shadcn.com/copper) by shadcn.

Piper adapts its coding guidelines, window architecture, and interface values from [NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire), by Brent Simmons and the NetNewsWire contributors. NetNewsWire is Copyright (c) 2002-2025 Brent Simmons and uses the MIT license. Piper ships no NetNewsWire code. The license text is in [`Licenses/NetNewsWire.txt`](Licenses/NetNewsWire.txt).

NetNewsWire does not endorse Piper and has no connection to this project.
