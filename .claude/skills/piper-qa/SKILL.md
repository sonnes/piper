---
name: piper-qa
description: Test a Piper build in the real app with agent-desktop, while the user keeps working in other apps. Builds a copy of Piper named PiperQA with its own bundle identifier, home folder, and folder of files, starts it in QA mode so that it never takes focus, then drives it through the accessibility tree and checks the result on disk and in screenshots. Use when the user says "test in the app", "check it in the app", "QA this", "try it in the built app", or "/piper-qa", when a change touches the UI of Piper, or when docs/release/validate.md lists manual checks for a change.
---

# Piper QA

Test Piper changes in a separate copy of the app. PiperQA has the bundle identifier `com.piper.qa`, its own home folder, and its own folder of files. The real Piper, its preferences, and its database do not change.

PiperQA starts in QA mode (`-PiperQA YES`). In QA mode, Piper opens the main window at launch and never becomes the active app. The user keeps the focus during the whole test. QA mode is in debug builds of the `qa-hooks` branch and of each branch that contains it. See "QA Mode" in `docs/internals/architecture.md`.

Run `qa.sh` from this skill folder. The data goes to `/tmp/piper-qa`. To use a different folder, set `QA`.

## Before You Start

1. If you did not use agent-desktop in this session, load the `agent-desktop` and `agent-desktop-macos` skills.
2. Run `agent-desktop status`. Make sure that `accessibility` and `screen_recording` are `granted`.
3. Write the files for the test into `/tmp/piper-qa/folder`. If the folder is empty, `qa.sh start` adds two sample notes.

To start with a clean folder, remove `/tmp/piper-qa/folder` before you start PiperQA.

## Start PiperQA

Run `qa.sh start <repo-dir>`. Use the worktree of the change, for example `.project/changes/<change>/wkt/piper`.

The command builds the app, quits an earlier PiperQA, and removes the `com.piper.qa` preferences. Then it starts PiperQA in the background and waits for the main window.

If the command stops with "no main window", the branch does not contain `qa-hooks`. Tell the user. Do not test that build with keys or with `--headed`, because they take focus.

## Drive The App

For each action, do these steps:

1. Find the element with `agent-desktop find --app PiperQA --role <role> --name <name>`. Take its `ref_id`.
2. Act on the ref with `click`, `focus`, `select`, `toggle`, or `expand`.
3. Read the result from a source that the action does not report itself.

To edit the open file, run `qa.sh type <text>`. The command inserts the text at the end of the file through the editor page. For other edits, run `qa.sh js <body>` with the body of an async function, for example `qa.sh js 'return window.piperErrors'`. The command prints the return value as JSON.

Use one of these sources for the check:

- The file on disk, with `cat`. This is the best check for an edit.
- The value of the element, with `agent-desktop find --app PiperQA --role textfield`.
- A screenshot. Run `qa.sh shot <name>`, then read `/tmp/piper-qa/<name>.png`.

Do not trust the status in the JSON output of an action. A click on a file row returns `ACTION_FAILED` with "effect could not be verified", but the file opens.

Use `agent-desktop wait --text <text> --app PiperQA` to wait for a change. Use `sleep` only when no text or window changes.

## Checks That Need The User

macOS sends keys only to the active app. Thus these checks do not work in QA mode:

- Key presses and shortcuts, such as Command-K, Command-B, Command-F, and Command-Z.
- The command palette, because it closes when it loses key focus.
- Japanese input and other input methods.
- Paste and other clipboard checks. The clipboard is shared with the user, and Piper records each clipboard change.

Do not do these checks with `press`, `--headed`, or the clipboard. List them for the user in the summary of the change.

## Facts About Piper

- On `main`, the editor is a native text view. The file changes on disk only after Command-S or Save.
- The web editor (a `WKWebView`) saves automatically. Headless `agent-desktop type` does not change it: use `qa.sh type`.
- On the `web-editor` branch, a switch to a second file blanks the editor page. The fix is on the `main-window` branch.
- `NSLog` lines from PiperQA do not show in `log show`. To trace the app, write to a file in `/tmp`.
- `agent-desktop click` takes only a ref. With `--app`, it stops with `INVALID_ARGS`.
- To add notes before a test, start and stop PiperQA once. Then write a `SavedState` JSON blob to the `state` table of `$QA/home/Library/Application Support/Piper/notes.sqlite`, with version 2. Dates are seconds from 2001-01-01. A later `qa.sh start` keeps this database.
- PiperQA records the system clipboard of the user in the `clipboard` table of its `notes.sqlite`. Before you render a view from a copy of that database, delete the `clipboard` rows and add fake rows. The `copied_at` column holds seconds from 1970.
- To check the capture panel without key focus, render `CaptureView(model:)` in an `NSHostingView` from a temporary test, and write the PNG to `/tmp`. Run the test with `CFFIXED_USER_HOME=$QA/home`. Delete the test and the PNG after the check.
- `qa.sh type` inserts the whole string at once, so Tiptap input rules do not run. To test an input rule, call `handleTextInput` for each character in `qa.sh js`. Place the caret with `editor.commands.setTextSelection`.

## Stop And Record

1. Run `qa.sh stop`. It quits PiperQA and removes the screenshots.
2. In the `summary.md` of the change, write what you checked in the app and the date. Use this form: "Checked in the app on <date> with agent-desktop: <checks>."
3. Write the checks that you did not do in the same place.
4. If you learned a new fact about Piper or agent-desktop, add it to "Facts About Piper" in this skill.

## Limits

- Do not use `--headed`, `focus-window`, or `launch` on PiperQA. They make PiperQA the active app. A `press` without `--headed` fails in QA mode.
- Do not test against the real Piper (`com.piper`) or against a real folder of the user.
- Do not take screenshots of the whole screen. They show the private content of other apps. `qa.sh shot` captures only a PiperQA window.
- Do not click at screen coordinates with `osascript`. Coordinates change when a window moves. Use refs from agent-desktop.
- Do not keep screenshots or snapshots in a commit. They can contain private content.
