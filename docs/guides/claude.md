---
title: "Work With Agents"
summary: "Talk to Claude Code or an ACP agent in a folder, answer its requests, and send notes to the skills of a folder"
read_when:
  - Talking to an agent about the file on the screen
  - Choosing the agent, the model, or the mode of a session
  - Adding Gemini CLI, OpenCode, or another ACP agent
  - Allowing or denying a tool call of an agent
  - Finding an earlier session
  - Sending a link or a note to a folder
  - Running a folder skill from the composer
  - Setting up Claude Code for a folder
  - Reading why a session failed
---

# Work With Agents

Piper runs an agent in a sidebar folder. The agent is Claude Code, or a command that speaks the Agent Client Protocol (ACP), such as Gemini CLI or OpenCode. You can talk to an agent in a session, or send a note to a skill of the folder.

A session is a conversation with one agent in one folder. Piper shows each message, each tool call, and each result in a transcript. A skill run is also a session, so you can answer the agent after the skill ends.

A skill always runs in Claude Code. The folder decides what a skill does. For example, the `/capture` skill of a wiki can archive a web page and write a source file.

Piper holds no logic for any skill. It reads each `.claude/skills/<name>/SKILL.md` file in the folder. The `name`, `description`, and `argument-hint` keys of that file become an action in Piper.

## Prepare A Folder

1. Install Claude Code, and sign in once in Terminal.
2. Add the folder to the sidebar. See [Browse and edit files](browse.md#add-a-folder).
3. Make sure that the folder has at least one skill in `.claude/skills`.
4. Open Settings > AI.
5. Make sure that the Claude Code row shows a green dot and the path of the `claude` command.

If the row shows "Not found", select Choose and select the `claude` command. Piper looks in `~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin`, and `/usr/local/bin`.

Claude Code uses Sonnet by default. To change the default, select a model in Settings > AI > Claude Code > Model. Claude Code Default uses the model in your Claude Code settings. A session can use another model. See [Choose the agent, the model, and the mode](#choose-the-agent-the-model-and-the-mode).

A folder with skills shows in Settings > AI with a switch. If you turn the switch off, Piper shows no Send action for that folder.

## Choose The Default Skills

Each folder has one default skill for links and one for text. A note is a link when its whole text is one HTTP or HTTPS URL.

- A link runs `/capture` if the folder has it.
- Text runs `/new` if the folder has it.

To change a default, select a skill in Links Run or Text Runs in Settings > AI. Select Nothing to hide the Send action for that kind of note.

The folder that you used last is the default folder. The Send button names it, for example "Send to wiki".

## Talk To An Agent In A Session

1. In the main window, select a file or a capture.
2. Press Option-Command-C, or select the pill in the bottom right corner of the detail pane. The session card opens. A chip over the message field names the file.
3. Type a message.
4. Press Return.

The card works in the folder of the selected file. If no file is selected, the card works in the folder that you used last.

While a capture is open, the card shows the conversations of that capture. It opens the newest one. The title menu lists the others. A message to a capture that has no session starts one for that capture, so the card shows it again when you come back. When you open another capture, the card and the pill change with it.

The session card floats over the bottom right corner of the detail pane, so the page stays on the screen beside it. In a narrow pane, the card fits the pane width and sits above the tabs. To change its height, drag its top edge. To close it, press Escape, select the down arrow, or press Option-Command-C again. The card collapses to the pill.

The pill shows the state of the session:

| Pill | State |
| --- | --- |
| Ask about this page | No session, or a draft |
| A spinner and the last step | The agent works |
| An orange pill with Needs you | A request waits for your answer |
| Done and a file name | The last turn wrote that file |
| Failed and the reason | The last turn stopped |

### Pop Out The Session Card

Select Pop Out in the header of the card. The card moves to a panel of its own. The panel floats over every app, on every Space, so you can read in another app and ask at the same time. The panel does not make Piper the active app.

To return the card to the main window, select Dock in the panel. To close the panel, select its close button. The card collapses to the pill. While the panel is open, Option-Command-C brings it to the front. Piper keeps the size and the place of the panel, and it opens the panel again after a restart.

The first message starts a session. The message names the file as context. To send a message without the file, select the x on the chip. After a message takes the file, the chip goes away until you select another file.

In the message field:

- Shift-Return adds a new line.
- A `/` at the start lists the commands available in the session. Tab or Return puts the command in the message.
- Before the session starts, the list shows folder skills. After the agent starts, the list also includes its supported built-in commands.
- An `@` lists the files of the folder. Tab or Return puts the path in the message.
- A skill takes the path of the chip file as its argument, for example `/verify <path>`.

While the agent works, Stop replaces the Send button. Stop ends the turn. Your next message continues the same session.

To start another session, select New Session (the pencil icon). The title menu of the card lists the sessions of the folder.

### Find A Session

When a folder has sessions, the sidebar shows a Sessions group with a row for that folder. An orange number on the row counts the sessions that wait for you.

1. Select the folder in the Sessions group.
2. Select a session in the list.

The list shows the newest change first. A blue dot marks a session with a turn that you have not read. The detail pane shows the transcript and a message field.

To delete a session, Control-click it and select Delete Session.

### Run A Command In A Follow-Up

1. Type `/compact` in the message field of an existing session.
2. If the completion list is open, press Tab to complete the command.
3. Add optional instructions, such as `keep the implementation decisions`.
4. Press Return to send the command.

Claude Code compacts the conversation in the same session. The transcript shows confirmation, or the reason that compaction did not run.

The list uses the commands reported by the installed Claude Code version. Commands that need an interactive terminal do not appear.
The `/compact`, `/clear`, `/context`, and `/usage` commands receive no attached file paths. Other commands and skills keep file context.

### Continue An Old Session

The agent process of a session stays open between turns, until you stop the turn or quit Piper. Each open session uses memory for its process. After a failure or a restart of Piper, your next message starts a new process that resumes the session. Claude Code also starts a new process after Stop, and after a change of the model or the mode. The agent keeps the earlier conversation.

## Choose The Agent, The Model, And The Mode

The footer of the composer has these menus:

- The agent menu lists Claude Code and each ACP agent in Settings > AI. A session keeps its agent after the first message.
- The model menu lists the models of the agent.
- The mode menu lists the modes of the agent, for example Plan.

A change of the model or the mode applies to the next turn. Before the first message, an ACP agent shows its name only. Its model and mode menus show after the agent starts.

Claude Code takes a new model or mode when its next process starts. Piper ends the idle process, and the next message resumes the session with `--resume`. An ACP agent takes the change at once.

A new session uses the agent in Settings > AI > Defaults > New Sessions. A skill run always uses Claude Code, with the model and the permissions in Settings > AI > Claude Code.

Settings > AI > Defaults > Margin Answers sets the agent that answers questions in the reader margin. An ACP agent can answer there only if it has a read-only mode, for example Plan, Ask, or Read Only. Piper puts the margin session in that mode before the first question. If the agent has no read-only mode, the answer fails and the next answer uses Claude Code. Settings then stops offering that agent for margin answers until you quit Piper.

## Allow The Tools That An Agent Uses

If an agent wants a tool that its mode does not allow, a drawer opens over the message field. The session waits for your answer, and its badge shows Needs you. The transcript shows one line for the request.

The drawer title names the request, for example "Waiting for your approval: run a command" or "Waiting for your approval: change a file". The transcript line shows the same text. The drawer shows the command or the path. For an edit, it also shows the lines that the edit changes, if the agent sends them. Claude Code always sends them. If more than one request waits, the drawer shows the count.

The buttons come from the agent. Claude Code shows these buttons:

- Allow Once runs this tool call.
- Always in <folder> runs this tool call and adds an allow rule to `.claude/settings.local.json` in the folder. Later calls of the same kind run with no request.
- Deny stops this tool call. Claude Code reads that you denied it and continues without it.

An ACP agent names its own buttons, for example Allow, Always Allow, and Reject.

The pointer over Always in <folder> shows the rule, for example `Bash(python3:*)` or `WebFetch(domain:example.com)`. Claude Code reads the rules in this file for that folder only. An ACP agent keeps its own record of an Always answer.

Claude Code can also ask a question with choices. The question shows in the drawer. Select a choice for each question, then select Answer.

If you type a message while a request waits, Piper denies the request. Claude Code reads your message as the reason and continues the same turn. An ACP agent gets your message as the next turn.

For Claude Code, the mode menu and Settings > AI > Claude Code > Permissions have these values:

| Value | When a tool call opens the drawer |
| --- | --- |
| Auto | Claude Code allows the tool calls that it finds safe. Risky calls open the drawer. This is the default. |
| Edit Files Only | File edits run with no request. Other tools open the drawer. |
| Ask Every Time | Each tool call that the folder settings do not allow opens the drawer. |
| Plan | Claude Code reads files and writes a plan. It edits no file. |
| Allow Every Tool | No tool call opens the drawer, including shell commands. |

Auto needs Sonnet or Opus.

To avoid a request for a tool, add an allow rule to `.claude/settings.json` in the folder. For example, a wiki skill that fetches pages and runs Python scripts needs rules like these:

```json
{
  "permissions": {
    "allow": ["WebFetch", "Bash(python3 .claude/scripts/*)"]
  }
}
```

If a turn ends while a request waits, the request changes to Denied.

CAUTION: Allow Every Tool lets Claude Code run any shell command in the folder. Use it only with skills that you trust.

## Add An ACP Agent

1. Install the agent, and sign in once in Terminal.
2. Open Settings > AI.
3. Select Add ACP Agent, then select the agent. If the agent is not in the menu, select Other.
4. Make sure that the command and the arguments are correct.
5. Select Add.

The menu has these agents:

| Agent | Command |
| --- | --- |
| Gemini CLI | `gemini --experimental-acp` |
| OpenCode | `opencode acp` |
| Codex | `codex-acp`, the Codex adapter for ACP. Install it first. |

Piper starts the command in the folder of each session, through your login shell. The command can be a name on your PATH, or a full path.

The dot on each agent row shows its health:

| Dot | Meaning |
| --- | --- |
| Green | The agent answered. For Claude Code, you are signed in. |
| Amber | The agent runs, but you must sign in. |
| Red | The command did not start, or it did not answer in 10 seconds. |
| Grey | Piper checks the agent. |

Piper checks each agent when you open Settings > AI. To check again, select Check Again.

An ACP agent uses its own tools. Piper gives it no file system and no terminal. The skills in `.claude/skills` run in Claude Code only.

To remove an agent, select Remove on its row. A session of a removed agent fails at its next message. Its agent menu shows Missing Agent, and its message field says that the agent was removed.

## Send A Note

- In the capture panel, move the pointer over a clipboard row, then select Send to <folder>. Piper saves the text to Inbox and opens a draft.
- In the capture panel, a link note that has no session shows Send to <folder> on its row. Select it.
- To send any note, Control-click it and select Send to <folder> with /<skill>.
- To send several notes, select them, then select Send in the selection bar, or press Command-Shift-Return. Each note gets a draft with its default skill.
- To choose a different skill, open the menu on the Send button, or select Send To in the context menu. The menu lists each folder and its skills.

The session composer opens with the skill command and the note text. Edit the text or add instructions, then press Return or select Send.
Claude Code starts only after you send the draft. The original note stays unchanged. Unsent drafts last until you quit Piper.
For several notes, Piper opens the last draft. Select each other draft from the session menu to edit and send it.

## Send From Another App

- Copy a link or text, then press Control-Option-W. Piper saves the clipboard text to Inbox and opens its draft.
- The menu bar icon has the same action as Send Clipboard to <folder>.
- After a selection capture in an app that does not show a web page, the toast shows a Send button for 6 seconds.

Control-Option-W works only while a folder has skills. An unsent note opens its existing draft. If a note has a session that did not fail, Piper does not send it again.

If another app holds Control-Option-W, Piper shows an error once. Use the menu bar icon instead.

## Run A Skill From The Composer

1. Type `/` in the composer.
2. Select a skill in the list, or type more letters of its name.
3. Press Tab or Return to put the skill in the composer.
4. Type the argument, for example a URL.
5. Press Return.

Piper saves the argument as a note in the selected section and starts a session with the skill. A skill with no argument hint runs when you press Return in the list. The note text of that session is the command, for example `/stale`.

In the list, Up and Down move the highlight, and Escape clears the command. The hint line under the composer names the skill and the folder that Return runs.

If no folder has a skill with the typed name, Return saves the text as a normal note.

## Read The Result

The row of a sent note shows a badge and a second line:

| Badge | Meaning | Select the badge to |
| --- | --- | --- |
| Waiting | Two sessions are in a turn. This turn starts when one ends. | Show the note |
| Running | The agent works. The second line shows the last tool call. | Show the note |
| Needs you | A request waits for your answer. | Show the note |
| Done | The last turn ended. The second line shows the first Markdown file that the session wrote. | Open that file in the main window |
| Failed | The last turn stopped. The second line shows the reason. | Show the note |

In the main window, select the note. The pill of the session card shows the state of its session. Open the card to answer a request, or to send another message.

The transcript shows:

- Your messages, with the context files under them.
- The messages of the agent.
- In a finished turn, one line for its tool calls, for example "Worked for 1m 12s · 4 reads, 2 edits". Select the line to show one row for each tool call.
- In a turn that runs, one row for each tool call. A checkmark marks a finished call, and an x marks a failed call. Select the row to see the start of the result.
- The lines that an edit removes and adds.
- A line at the end of each turn with the time and the cost. An agent that reports no cost shows the time only.

Open on a tool row opens the Markdown file that the call wrote. Under the transcript, a menu lists every file that the session changed, and the total cost shows at the right.

A turn stops after 10 minutes. The time that a request waits for you does not count. If you quit Piper during a turn, Piper asks first, then stops the turn. A stopped turn can leave some changed files in the folder. After you open Piper again, the session shows "Piper quit before the turn finished." Send a message to continue it.

Piper does not commit changes. A hook in the folder can commit them.
