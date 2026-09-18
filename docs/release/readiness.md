---
title: "Release Readiness"
summary: "Open acceptance work before Piper is ready for regular use and distribution"
read_when:
  - Planning the next development pass
  - Deciding whether a build is ready for regular use
---

# Release Readiness

Release 0.1.0 is notarized, but it is older than the current source. The next release needs the acceptance work below. Each task links to the checks in [Validate a build](validate.md). Change a checkbox only when you record the evidence.

## Capture Compatibility

- [ ] Fill in the selection capture app matrix after Accessibility approval.
- [ ] Record double Shift behavior during normal typing and with held modifiers.
- [ ] Test Control-Option-Space.
- [ ] Test empty selections, secure fields, and the clipboard fallback.
- [ ] Correct the defects that you find, and add regression tests where possible.

Acceptance: a supported app saves the exact selected text. The clipboard and the focus do not change. An unsupported selection gives a clear fallback message.

## Windows And Persistence

- [ ] Run the capture checks, including a restart.
- [ ] Test Save and Cancel in a separate note editor.
- [x] Keep the current notes when a database write fails. `ReleaseTests` covers locked, invalid, and stale databases.
- [x] Protect capture drafts from conflicting edits and from quit. `ReleaseTests` and `QuitSafetyTests` cover this.

Acceptance: each window restores its own state, saved notes survive a restart, and a failed write keeps the current data.

## Main Window

- [ ] Run the main window, editing, and reading preference checks.
- [ ] Decide whether the main window needs find in the open file.
- [ ] Decide whether the capture tabs follow the section at the top of the list while it scrolls. Today a tab changes only on a click.
- [ ] Decide whether Piper needs a Create Wiki action. `Vault.create()` has no caller.
- [ ] Make a link from the editor update the sidebar and the file list.
- [x] Connect the Capture Clipboard action on Home. `ReleaseTests.testHomeClipboardCaptureSavesWithoutAnAppDelegate` covers the model action and an empty clipboard.

Acceptance: every visible control does what its label says, and no edit is lost on navigation, close, or quit.

## Claude Sessions

- [ ] Run the Claude checks in [Validate a build](validate.md#claude-checks).
- [ ] Test the toast Send button when Piper is not the active app.
- [ ] Decide on a notice when a turn ends or needs an answer while the main window is hidden.
- [ ] Decide whether Stop sends an interrupt and keeps the process. Today Stop ends the process.
- [ ] Decide whether the Claude pane restores the session that it showed before a restart.

Acceptance: a link from the clipboard reaches the folder with one action, a card waits for an answer, and a failed turn names its cause.

## Distribution

- [x] Choose the Developer ID identity and a direct-download channel.
- [x] Add Developer ID signing and notarization for the DMG.
- [x] Notarize and staple release 0.1.0 for Apple silicon.
- [ ] Choose the supported macOS versions and the app compatibility list.
- [ ] Run the distribution checks for the next release, including a clean Mac.

Acceptance: the downloaded DMG installs and captures text with the documented permission steps.

## Repository Preparation

- [x] Add README screenshots with fictional developer notes and public project links.
- [x] Add CI for tests, the app build, and signature checks on macOS 14 and macOS 26.
- [x] Run local tests and build the current source. See [Recorded results](validate.md#recorded-results).
- [ ] Record the first successful GitHub Actions run.
- [ ] Publish a GitHub release with the signed DMG of the current source. The README links to the latest release.

## Out Of Scope

These items need a separate scope decision: attachments, URL lookup beyond Accessibility, an arbitrary shortcut recorder, launch at login, and full CommonMark. Sync, built-in model hosting, and a documentation website are outside this release. Optional Claude Code sessions already exist.
