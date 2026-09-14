---
title: "Release Readiness"
summary: "Remaining acceptance work for the local Piper application"
read_when:
  - Planning the next development pass
  - Deciding whether the local build is ready for regular use
---

# Release Readiness

Status: Release 0.1.0 packaged and notarized. Cross-app capture and clean-Mac acceptance remain open. Baseline: September 12, 2026.

## Scope

The next milestone is dependable local capture and Wiki export. The capture panel and Wiki browser remain separate windows.

The application uses real capture and clipboard services, starts with Inbox, and creates empty Wikis. All 48 automated tests pass.

## Capture Compatibility

Accessibility approval succeeded on the test Mac. The user skipped global-shortcut verification. Automated keystrokes do not exercise the macOS hotkey path.

- [ ] Run the [application matrix](../howto/validate.md) after permission approval.
- [ ] Record double-Shift behavior during normal typing and held modifiers.
- [ ] Verify the Control-Option-Space alternative.
- [ ] Verify empty selections, secure fields, and the clipboard fallback.
- [ ] Fix observed capture defects and add regression tests where reproducible.

Acceptance: supported applications save the exact selected text without a clipboard replacement or focus change. Unsupported selections produce a useful fallback message.

## Windows And Persistence

Prerequisite: a packaged local build from `make build`.

- [ ] Run the window and restart checks in the manual guide.
- [ ] Verify separate editor Save Changes and Cancel behavior.
- [x] Exercise a failed database write without losing the current notes. Lock, invalid-record, and stale-writer tests pass.
- [x] Protect capture drafts from conflicting edits and unsaved termination.

Acceptance: window state remains independent, saved notes survive restart, and failed writes preserve current data.

## Wiki Export Recovery

Prerequisite: a disposable copy of the user's Wiki.

- [ ] Run the manual export checks.
- [ ] Interrupt export between draft creation and derived file updates.
- [ ] Verify retry behavior and stale lock recovery.
- [ ] Exercise external edits during export.
- [ ] Compare exported drafts with the Wiki's own validator.
- [ ] Fix confirmed compatibility defects before regular use.

Acceptance: retries preserve the draft and avoid duplicates. Existing concepts and archives remain unchanged. Any unresolved concurrency limit remains explicit in the documentation.

## Distribution Decision

Prerequisite: successful local acceptance and a decision to distribute the app.

- [ ] Choose a supported macOS and application compatibility list.
- [x] Define the Developer ID identity and direct-download channel.
- [x] Add Developer ID signing and notarization for the DMG.
- [x] Notarize and staple release 0.1.0 for Apple silicon. Gatekeeper accepts the DMG and the installed app.
- [ ] Verify installation and permission behavior on a clean Mac.

Acceptance: the distributed artifact installs and captures text under the documented permission flow.

## Deferred Scope

Attachments, browser URL lookup beyond Accessibility, arbitrary shortcut recording, launch at login, and complete CommonMark support require separate scope decisions.

Sync, AI processing, and a documentation website remain outside this milestone.
