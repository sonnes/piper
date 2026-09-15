---
title: "Install Piper"
summary: "Build Piper from source, grant Accessibility access, and build a signed release"
read_when:
  - Starting Piper locally
  - Enabling selection capture
  - Building a notarized DMG
---

# Install Piper

No signed build is available for download. You build Piper from source.

## Requirements

- macOS 14 or later
- A Swift 5.9 toolchain with the macOS SDK
- Make
- Claude Code, for [commands and skills](commands.md) only

## Build And Open

1. Open a terminal in the Piper repository.
2. Run `make test`.
3. Run `make run`.

`make run` writes `build/Piper.app` with an ad hoc signature and opens it. The first build downloads the pinned Yams and SwiftMarkdownEngine packages. After that, capture and browsing work offline.

Piper starts with the capture panel and a menu bar icon. A second launch opens the copy that is already running.

## Allow Selection Capture

Piper reads selected text through the macOS Accessibility API. Without this permission, the capture panel and the Wiki window still work.

1. Open Settings with Command-comma.
2. Select Capture.
3. Select Open System Settings.
4. Turn on Piper in the Accessibility list.

Piper checks the permission every four seconds. You do not need to restart it. The capture panel shows an Enable Selection Capture banner until the permission is on.

To use selection capture, see [Capture notes](capture.md#capture-a-selection).

## Build A Signed Release

The `make release` target runs the tests. Then it signs, notarizes, staples, and validates a DMG for the architecture of the build Mac.

1. Make sure that Keychain Access contains the `Developer ID Application` certificate and its private key.
2. Create an `.envrc` file in the repository root with the variables below.
3. Run `make release`.
4. Make sure that `notarytool` reports an `Accepted` status.
5. Save the SHA-256 checksum that the command shows.

```text
APPLE_TEAM_ID
APPLE_SIGNING_IDENTITY
APPLE_API_ISSUER
APPLE_API_KEY
APPLE_API_KEY_PATH
```

Git ignores `.envrc`, and the credentials stay out of the app bundle. `APPLE_API_KEY_PATH` identifies the App Store Connect team key. Piper does not use `APPLE_PROVISIONING_PROFILE`.

The DMG is `build/Piper_<version>_<architecture>.dmg`. The bundle ID is `com.piper`. Release builds contain no sample data and no demo mode.

## Make Targets

| Command | Result |
| --- | --- |
| `make build` | Builds `build/Piper.app` with an ad hoc signature |
| `make run` | Builds the app and opens it |
| `make test` | Runs `swift test` |
| `make release` | Tests, builds, signs, notarizes, and validates the DMG |
