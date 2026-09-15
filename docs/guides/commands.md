---
title: "Run Commands And Skills"
summary: "Run Claude Code slash commands and skills in your Wiki folder"
read_when:
  - Running a Claude Code command or skill from Piper
  - Adding commands or skills to a Wiki folder
  - Checking what a command run can change
---

# Run Commands And Skills

Piper runs the Claude Code commands and skills that your Wiki folder can reach. It keeps no command definitions of its own. This is the only Piper feature that uses the network.

Claude Code must be installed. Piper looks for `claude` in `~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin`, and `/usr/local/bin`.

## Where Piper Finds Them

| Kind | Path | Name | Summary |
| --- | --- | --- | --- |
| Command | `.claude/commands/<name>.md` | The file name | The `description` key |
| Skill | `.claude/skills/<name>/SKILL.md` | The `name` key, or the folder name | The first sentence of `description` |

Piper reads both paths in the Wiki folder and in your home folder. A row from your home folder has the tag `personal`. If both folders have the same name, the Wiki folder wins. Either `.claude` folder can be a symbolic link.

A command can also set `argument-hint` in its frontmatter. Piper uses it as the label of the argument field.

## Run From The Toolbar

1. Open the Wiki window with Command-2.
2. Select the Commands And Skills button (the terminal symbol) in the toolbar.
3. Select a command or a skill.
4. If the field below the menu is available, enter the arguments.
5. Select Run.

The output shows in the sheet as it arrives. To stop a run, select Stop. You cannot close the sheet while a command runs.

## Run From Home

1. Press Command-0.
2. Type `/` and the name, for example `/summarize today`.
3. Press Return.

Home runs the selected row at once. The text after the name becomes the arguments. The output opens in the same sheet.

## What A Run Does

Piper starts this process with the Wiki folder as the working directory:

```sh
claude --print "<prompt>" --permission-mode acceptEdits --allowedTools Read Write Edit Glob Grep WebFetch "Bash(python3:*)"
```

A command sends `/<name> <arguments>` as the prompt. A skill sends `Use the <name> skill. <arguments>`.

Before a run, Piper asks you to save or discard an unsaved edit. If you select Cancel, the run does not start. After the run stops, Piper scans the folder again. While a command runs, Piper does not quit and shows the Wiki window instead.

## Limits

- A run edits files without asking. The allowed tools can read, write, and fetch web pages.
- Claude Code decides what happens when the run needs a tool that is not on the list.
- Hooks and settings in the Wiki folder run as usual. A hook can create Git commits.
- A run sends the prompt and file content to the Anthropic API.

## Errors

| Message | Cause |
| --- | --- |
| Piper cannot find the claude command | `claude` is not in any of the four paths |
| This Wiki folder has no .claude/commands directory | The Wiki folder has no command folder. The skill message names `.claude/skills`. |
| claude exited with status N | Claude Code stopped with an error. Read the output in the sheet. |
| The command stopped | You selected Stop |
