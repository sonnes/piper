---
title: "Send Notes To Claude"
summary: "Talk to Claude Code in a folder, and send notes to the skills of a folder"
read_when:
  - Talking to Claude about the file on the screen
  - Allowing or denying a tool call of Claude
  - Finding an earlier Claude session
  - Sending a link or a note to a folder
  - Running a folder skill from the composer
  - Setting up Claude Code for a folder
  - Reading why a session failed
---

# Send Notes To Claude

Piper runs Claude Code in a sidebar folder. You can talk to Claude in a session, or send a note to a skill of the folder.

A session is a conversation with Claude Code in one folder. Piper shows each message, each tool call, and each result in a transcript. A skill run is also a session, so you can answer Claude after the skill ends.

The folder decides what a skill does. For example, the `/capture` skill of a wiki can archive a web page and write a source file.

Piper holds no logic for any skill. It reads each `.claude/skills/<name>/SKILL.md` file in the folder. The `name`, `description`, and `argument-hint` keys of that file become an action in Piper.

## Prepare A Folder

1. Install Claude Code, and sign in once in Terminal.
2. Add the folder to the sidebar. See [Browse and edit files](browse.md#add-a-folder).
3. Make sure that the folder has at least one skill in `.claude/skills`.
4. Open Settings > Claude.
5. Make sure that the Claude Code row shows the path of the `claude` command.

If the row shows "Not found", select Choose and select the `claude` command. Piper looks in `~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin`, and `/usr/local/bin`.

Sessions use Sonnet by default. To use another model, select it in Settings > Claude > Model. Claude Code Default uses the model in your Claude Code settings.

A folder with skills shows in Settings > Claude with a switch. If you turn the switch off, Piper shows no Send action for that folder.

## Choose The Default Skills

Each folder has one default skill for links and one for text. A note is a link when its whole text is one HTTP or HTTPS URL.

- A link runs `/capture` if the folder has it.
- Text runs `/new` if the folder has it.

To change a default, select a skill in Links Run or Text Runs in Settings > Claude. Select Nothing to hide the Send action for that kind of note.

The folder that you used last is the default folder. The Send button names it, for example "Send to wiki".

## Talk To Claude In A Session

1. In the main window, press Option-Command-C, or select the Claude Pane button at the right end of the toolbar.
2. Select a file. A chip over the message field names the file.
3. Type a message.
4. Press Return.

The pane works in the folder of the selected file. If no file is selected, the pane works in the folder that you used last.

The first message starts a session. The message names the file as context. To send a message without the file, select the x on the chip. After a message takes the file, the chip goes away until you select another file.

In the message field:

- Shift-Return adds a new line.
- A `/` at the start lists the skills of the folder. Tab or Return puts the skill in the message.
- An `@` lists the files of the folder. Tab or Return puts the path in the message.
- A skill takes the path of the chip file as its argument, for example `/verify <path>`.

While Claude works, Stop replaces the Send button. Stop ends the turn. Your next message continues the same session.

To start another session, select New Session (the pencil icon). The title menu of the pane lists the sessions of the folder.

### Find A Session

When a folder has sessions, the sidebar shows a Claude group with a row for that folder. The number on the row counts the sessions that wait for you.

1. Select the folder in the Claude group.
2. Select a session in the list.

The list shows the newest change first. A blue dot marks a session with a turn that you have not read. The detail pane shows the transcript and a message field.

To delete a session, Control-click it and select Delete Session.

### Continue An Old Session

The `claude` process of a session stays open between turns, until you stop the turn or quit Piper. Each open session uses memory for its process. After a stop, a failure, or a restart of Piper, your next message starts a new process with `--resume`. Claude keeps the earlier conversation.

## Allow The Tools That Claude Uses

If Claude wants a tool that the permission mode does not allow, the transcript shows a card. The session waits for your answer, and its badge shows Needs you.

- Allow Once runs this tool call.
- Always in <folder> runs this tool call and adds an allow rule to `.claude/settings.local.json` in the folder. Later calls of the same kind run with no card.
- Deny stops this tool call. Claude reads that you denied it and continues without it.

The pointer over Always in <folder> shows the rule, for example `Bash(python3:*)` or `WebFetch(domain:example.com)`. Claude Code reads the rules in this file for that folder only.

Claude can also ask a question with choices. Select a choice for each question, then select Answer.

If you type a message while a card waits, Piper denies the card and gives your message to Claude as the reason. Claude continues the same turn with your message.

Settings > Claude > Permissions has these values:

| Value | When a tool call shows a card |
| --- | --- |
| Auto | Claude Code allows the tool calls that it finds safe. Risky calls show a card. This is the default. |
| Edit Files Only | File edits run with no card. Other tools show a card. |
| Ask Every Time | Each tool call that the folder settings do not allow shows a card. |
| Allow Every Tool | No tool call shows a card, including shell commands. |

Auto needs Sonnet or Opus.

To avoid a card for a tool, add an allow rule to `.claude/settings.json` in the folder. For example, a wiki skill that fetches pages and runs Python scripts needs rules like these:

```json
{
  "permissions": {
    "allow": ["WebFetch", "Bash(python3 .claude/scripts/*)"]
  }
}
```

If a turn ends while a card waits, the card changes to Denied.

CAUTION: Allow Every Tool lets Claude run any shell command in the folder. Use it only with skills that you trust.

## Send A Note

- In the capture panel, move the pointer over a clipboard row, then select Send to <folder>. Piper saves the text to Inbox, then runs the default skill.
- A link note that has no session shows Send to <folder> on its row. Select it.
- To send any note, Control-click it and select Send to <folder> with /<skill>.
- To send several notes, select them, then select Send in the selection bar, or press Command-Shift-Return. Each note runs its own default skill.
- To run a different skill, open the menu on the Send button, or select Send To in the context menu. The menu lists each folder and its skills.

## Send From Another App

- Copy a link or text, then press Control-Option-W. Piper saves the clipboard text to Inbox and sends it.
- The menu bar icon has the same action as Send Clipboard to <folder>.
- After a selection capture, the toast shows a Send button for 6 seconds.

Control-Option-W works only while a folder has skills. If the clipboard text is a note that was already sent, Piper does not send it again.

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
| Running | Claude works. The second line shows the last tool call. | Show the note |
| Needs you | A card waits for your answer. | Show the note |
| Done | The last turn ended. The second line shows the first Markdown file that the session wrote. | Open that file in the main window |
| Failed | The last turn stopped. The second line shows the reason. | Show the note |

In the main window, the detail pane of a note shows its session under the note. You can answer a card there, or send another message.

The transcript shows:

- Your messages, with the context files under them.
- The messages of Claude.
- One row for each tool call. A checkmark marks a finished call, and an x marks a failed call. Select the row to see the start of the result.
- The lines that an Edit call removes and adds.
- A line at the end of each turn with the time and the cost.

Open on a tool row opens the Markdown file that the call wrote. Under the transcript, a menu lists every file that the session changed, and the total cost shows at the right.

A turn stops after 10 minutes. The time that a card waits for you does not count. If you quit Piper during a turn, Piper asks first, then stops the turn. A stopped turn can leave some changed files in the folder. After you open Piper again, the session shows "Piper quit before the turn finished." Send a message to continue it.

Piper does not commit changes. A hook in the folder can commit them.
