---
title: "Architecture"
summary: "Modules, window ownership, and the flow between captures and the vault"
read_when:
  - Changing window behavior
  - Deciding which module new code belongs in
  - Tracing capture persistence, file saves, or the daily brief
---

# Architecture

Piper is a Swift package. Model code lives in modules under `Sources/Modules`. The `Piper` application target sits above them and holds the windows and views. AppKit owns the windows and the panes. SwiftUI draws most pane content. The rules for new code are in [Coding guidelines](coding-guidelines.md).

```mermaid
flowchart LR
    CS[CaptureService] --> S[CaptureStore]
    CB[ClipboardInbox] --> S
    P[Capture panel] --> S
    S --> D[(SQLite snapshot)]
    V[Vault scan and watcher] --> M[AppModel]
    M --> W[Main window]
    W --> ED[Editor] --> V
```

## Modules

| Module | Responsibility | Depends on |
| --- | --- | --- |
| `CSQLite` | System SQLite, through `pkg-config` | nothing |
| `PiperCore` | `PiperError`, the frontmatter parser, and `PaletteSearch` | Yams |
| `PiperTree` | `Node`, `TreeController`, and `PathTreeBuilder` | nothing |
| `CapturesDatabase` | One versioned blob in SQLite, with compare-and-swap | `CSQLite` |
| `Captures` | `Note`, `CaptureStore`, `ClipboardInbox`, `CaptureLinks`, and edit sessions | `PiperCore`, `CapturesDatabase` |
| `Vault` | One folder: scan, read, write, and watch | `PiperCore`, Yams |
| `Agents` | `SessionRunner`, `AgentSession`, `AgentConnection` with `ClaudeCodeConnection` and `StdioAgentConnection`, the `ACP` types, `AgentProbe`, `SessionEvent`, `FolderSkill`, `SlashCommand`, and `PermissionRule` | `PiperCore`, `CapturesDatabase` |
| `Briefs` | `BrowserCatalog`, `HistoryReader`, `NetNewsWireReader`, `HackerNews`, `BriefDocument`, `HistoryDigest`, `BlockedSites`, `BriefLinks`, `BriefPrompts`, `BriefSchedule`, and `BriefStore` | `PiperCore`, `CSQLite` |
| `Piper` | Windows, panes, views, and app state | All modules and Yams |

`PiperCore`, `PiperTree`, and `CapturesDatabase` have no dependency on another Piper module. `PiperCore` holds the frontmatter parser.

Each module has a test target with the same name and a `Tests` suffix. `PiperTests` tests the application target.

## Windows

`AppDelegate` in `PiperApp.swift` creates each window when it first shows. It owns these windows:

| Window | Owner |
| --- | --- |
| Capture panel | `CapturePanelController` |
| Main window | `MainWindowController` |
| Settings | `SettingsWindowController` |
| Note editor windows | `AppDelegate`, one for each note |
| Capture toast | `AppDelegate` |
| Reading toast | `ReadingToast`, which `AppDelegate` owns |

The capture panel and the main window are exclusive. `showPanel()` hides the main window, and `showLibrary()` hides the panel. Neither closes, so drafts and edit sessions stay. Closing every window leaves the app running in the menu bar.

The panel is a non-activating `NSPanel` on every Space. Its initial size is 600 by 960 points with 22-point corners. It scales down on a small screen.

### Main Window

`MainWindowController` owns the toolbar and an `NSSplitViewController` with four split items:

| Pane | Controller | Content |
| --- | --- | --- |
| Sidebar | `SidebarViewController` | `SidebarOutline`, an `NSOutlineView` |
| List | `CaptureListViewController` | `CaptureView` for Inbox, a section, or Archived |
| Detail | `DetailViewController` | `BriefPage`, `CaptureView` for Clipboard, `EditorPane`, `FilePreview`, `NoteDetail`, or a session |
| Session card | `DetailViewController` | `SessionOverlay`, in a hosting view over the bottom right corner of the detail pane |

Each controller subclasses `HostingPaneViewController`, which wraps an `NSHostingView`. A pane reports upward through a delegate protocol, and `MainWindowController` decides what the other panes show. The editor page is an exception. A link in it calls `AppModel.openDocument` directly, so a link does not change the sidebar selection.

`SidebarSelection` decides the layout. `SidebarSelection.showsList` is true only for Inbox, a section, and Archived. Every other selection collapses the list pane, and the detail pane takes its width. A Claude folder hides the session card, because the detail pane shows the sessions of the folder. `MainWindowState` saves the selection, the open file, the open folders, and the pane widths. `AppModel.selectedSession` holds the session that the session card and the detail pane of a Claude folder show.

`AppModel.sessionPresentation` is the pill, the card, or the detached panel, and preferences keep it. `DetailViewController` holds two hosting views: the content, and an overlay pinned to the bottom right corner. The overlay takes the intrinsic size of `SessionPill` or `SessionCard`, so a click outside it reaches the content. A constraint keeps the overlay at most 85% of the pane height. `DetailPaneLayout` shares the pane width between the card and the tabs. In a narrow pane, the card fits the width and sits above the tabs. `SessionCard` hosts `SessionPane`, and `SessionTarget` picks its folder, its session, and its context page. `SessionPanelController` shows the same card in a non-activating `NSPanel` on every Space. Its close button returns the presentation to the pill.

The window title names the open file, and the subtitle shows the folders of the file. For other selections, the title names the selection, as in Mail, and the subtitle shows a count. The title updates through `withObservationTracking`. The toolbar has tracking separators that align with the split view dividers. Toggle Sidebar sits over the sidebar. New Capture sits over the list. Back and Forward, Mark as Done, and the More menu sit over the detail pane. `TabIsland` floats over the bottom of the detail pane, with Preview and Source for a file. The Session Card button at the end opens and collapses the session card, as does Option-Command-C. The list of captures and the clipboard history each have a search field.

The sidebar has up to three groups. Library holds Brief, Inbox with one child for each capture section other than Inbox, Clipboard, and Archived. Claude holds one `SidebarSelection.sessions` row for each folder with sessions, and it shows only when a session exists. Each folder row holds a `SidebarSessionRow` for each session. A session row sets `AppModel.selectedSession` and selects its folder. A folder row clears `AppModel.selectedSession`, so the detail pane starts a new session. Folders holds every root and the tree of the active root, with its files. A click on a folder opens or closes it. `SidebarSelection.folder` keeps the last file in the detail pane. `SidebarSelection.section` shows the captures of one section, and `SidebarSelection.clipboard` shows the clipboard history in the detail pane.

The expansion set of `SidebarPane` holds the open folder paths. It also holds two kinds of keys that start with `\u{1}`, so they cannot match a path: `SidebarOutline.inboxCollapsedKey` for a closed Inbox, and `SidebarOutline.sessionsExpandedKey` for each open Claude folder.

Sidebar fonts and icons follow the macOS sidebar size preference: 11 and 16 points, 13 and 19 points, or 15 and 22 points.

## Capture

`CaptureService` detects double Shift with `NSEvent` monitors. Control-Option-Space is a registered system hotkey, so the source app does not receive the keystroke.

The service records the source app and the active section before it reads Accessibility text. A serial queue reads the focused element with a 0.4-second timeout. If the selected text attribute is empty, the service uses the selected range. Secure fields produce no note.

The service then looks for a web page. It reads `AXDocument` from the focused element and the window, and `AXURL` from the `AXWebArea`. The web area is the first ancestor of the focused element with that role, or else the first web area in the window. If a web page is in front, the service also reads the window title and the text of the whole web area. The text comes from the `AXTextMarkerRangeForUIElement` and `AXStringForTextMarkerRange` attributes, which WebKit and Chromium both have, with a 1.5-second timeout.

`CaptureService.save` turns the result into a `CaptureOutcome`:

| Selection | Web page | Outcome |
| --- | --- | --- |
| The text of the highlight on the toast, or none, while the toast shows | Any | `comment`: the toast opens the note field |
| Text | Yes | `highlight`: `CaptureStore.saveHighlight` |
| None | Yes | `article`: `CaptureStore.saveArticle` |
| Text | No | `note`: `CaptureStore.add` |
| None | No | `note` with an error message and no id |

`CaptureStore.article(for:)` finds a link capture by the link that `CaptureLinks.canonical` returns, so two links to one page share one capture. `NoteAnchor.normalized` collapses the white space of a browser selection, as the Reader tab does. The anchor of a browser highlight has block -1. `NoteAnchor.locate` finds the quote when the Reader tab opens. A quote can run over more than one block. In that case, `locate` searches the blocks joined with spaces. The mark stops at the end of the first block. If the article holds only a part of the quote, it tries shorter starts of the quote, down to four words.

`ReadingToast` is a borderless, non-activating `NSPanel`. It shows a new highlight, a saved page, or the note field. Only the note field makes the panel the key window. Piper never becomes the active application, so the browser gets the keyboard back when the panel closes. `CaptureService.shownHighlight` reads the highlight on the toast, so a second capture of it asks for a note.

`CaptureStore` builds a candidate state and saves it before it replaces the current state. `Database` compares the stored blob with the last loaded blob on every save. A database error or a stale snapshot leaves the current notes as they are. See [Local storage](../concepts/storage.md).

`ClipboardInbox` polls the pasteboard and keeps the 50 latest texts from the last 7 days, with the copy time and the app in front. It stores them in the `clipboard` table through the `Database` of `CaptureStore`. `ClipboardRow` in `CaptureRows.swift` saves to Inbox with Keep, and pastes through `ClipboardPaster` on a double-click.

`CaptureView` draws the capture list for both windows. In the panel, the list holds every section under a header, and a `SectionScroll` request scrolls it to one header. In the main window, `CaptureListContent.stream` shows the `InboxStream` of the sidebar selection: every section for Inbox, or one section. `InboxStream` filters the captures by section, chip, and search, and groups them as Continue Reading and days, or as Continue, Up Next, and Finished This Week. `AppModel.inboxFilters` keeps the chip of each section. `InboxRow` draws each capture of the stream, and `NoteContextMenu` gives the panel rows and the stream rows the same menu. In the main window, a click on a row sets the selection to that capture, which opens it. Command-click and Shift-click set `checking` and select several captures. The selection bar shows while `checking` is true. The circle completes a note, and the ring marks an article as read. `NoteDetail` shows a link capture in its tabs and any other note in an editor. `SessionTarget` reads the open note from `AppModel.actionTarget`. For a note, the card shows the selected session when it belongs to the note, or else the newest session of the note, and it leaves out the margin sessions. A message from the card starts a session with the `noteID` of the note. `AppModel.newSessionNote` keeps the card empty after New Session. The child notes of an article stay hidden until the reader opens them. Archived shows `InboxStream.archive`, which groups the done captures by the month of `modifiedAt`, because marking a capture as done sets that time. The main-window controller routes note selection to the detail pane and limits shortcuts to the Inbox pane.

## Agent Sessions

`FolderAgents` in the application target holds the agents, the defaults of a new session and of a margin answer, the sidebar folders that have skills, the default folder, and the default skill for links and for text. `AppModel` refreshes the folders when the folder list changes, on each scan, and when the capture panel becomes key.

`SessionRunner` in the `Agents` module owns every `AgentSession`. Each session is an `@Observable` object, so a view of one session redraws only when that session changes. A session records its agent, its purpose, its model, its mode, and the ACP session id in `resumeToken`.

The runner reads only Agent Client Protocol (ACP) v1 terms. Each session has one `AgentConnection`, and the connection sends `AgentEvent` values to the runner:

| Event | Effect |
| --- | --- |
| `ready` | Stores the session id, the modes, and the config options of the agent |
| `update` | Applies one `session/update`: a part of a message, a tool call, a change to a tool call, the commands, the mode, the options, or the usage |
| `permission` | Adds a request. The session changes to `needsYou`, and the approval drawer shows the options of the agent. |
| `turnEnded` | Adds a result block with the time, the cost, and the failure, and ends the turn |

Parts of a message in a row join into one text block. A tool call keeps its ACP kind, and the transcript folds the calls of a finished turn by kind. A path stays only for a call that writes a file inside the folder.

### Connections

`ClaudeCodeConnection` runs Claude Code with no adapter. It starts one `AgentProcess` with this command in the folder:

```
claude -p --input-format stream-json --output-format stream-json --verbose \
  --permission-prompt-tool stdio --permission-mode <mode> [--model <model>] \
  [--tools <tools> --allowedTools <tools>] [--resume <id>]
```

The mode is `auto` and the model is `sonnet` by default. An empty model omits `--model`. A margin session adds `--tools` and `--allowedTools` with `Read,Grep,Glob,WebSearch,WebFetch`, and `--strict-mcp-config`. `--tools` limits only the built-in tools, so `--strict-mcp-config` removes the MCP servers of the user settings. The process then has no other tool. Claude Code takes a new model or mode only at start, so the runner closes an idle process after a change.

Each message is one JSON line on standard input: `{"type":"user","message":{"role":"user","content":[{"type":"text","text":...}]}}`. A context file goes after the text as a `Context file: <path>` line. A slash command takes the path as its argument.

`SessionEvent.parse` reads each line of standard output, and the connection turns it into ACP:

| Line | Event |
| --- | --- |
| `system` with subtype `init` | `ready` with `session_id`. The slash commands become a commands update. |
| `assistant` text | An agent message. A second text in one turn starts a new paragraph. |
| `assistant` tool use | A tool call with the kind of the tool. `Write`, `Edit`, `MultiEdit`, and `NotebookEdit` record the file. |
| `user` with a `tool_result` | A change of the tool call to completed or failed |
| `control_request` with subtype `can_use_tool` | A permission request with Allow Once, Always in the folder, and Deny |
| `result` | `turnEnded` with the time, the cost, and the failure |

A message from a subagent carries a `parent_tool_use_id`, and the parser skips it. A request sends one `control_response` line with the `request_id`. Allow sends `{"behavior":"allow","updatedInput":<input>}`. Deny sends `{"behavior":"deny","message":...}`, and Claude Code reads the message as the tool result. An answer to `AskUserQuestion` adds `answers`, a map from each question to the chosen labels, to `updatedInput`. A message that the reader sends while a request waits becomes the deny message of each waiting request, so Claude Code reads it in the same turn. Always also writes the rule from `PermissionRule` into `.claude/settings.local.json`. The connection then allows later calls with that rule in the folder for the rest of the launch.

A turn fails when `is_error` is true, when the subtype is not `success`, or when `permission_denials` names a call that the reader did not deny.

`StdioAgentConnection` runs a command that speaks ACP, as JSON-RPC 2.0 with one message on each line. It sends `initialize` with no file system and no terminal capability, so the agent uses its own tools. Then it opens the session:

- `session/load`, for a known session id when the agent offers `loadSession`. The connection skips the history that the agent replays.
- `session/resume`, for a known session id when the agent offers only `resume`.
- `session/new` in all other cases, or when a load fails.

A prompt waits until the session opens, and goes out as `session/prompt`. The `stopReason` of the response ends the turn. Stop sends `session/cancel`, and each request that waits gets the outcome `cancelled`. A request for a method that Piper does not offer gets the error `-32601`.

The connection changes the mode with `session/set_mode`, and the model with `session/set_config_option`. An agent that sends the older `models` list in place of a model option gets `session/set_model`. OpenCode 1.2 does this.

A margin session of an ACP agent shows no request. The runner allows a call of the kind `read`, `search`, `fetch`, or `think`, and denies every other call.

`AgentProcess` reads both pipes with a `readabilityHandler`. A blocking read holds a thread for each idle process, and a few idle sessions then hold every thread of the pool. Piper ignores SIGPIPE, so a write to a process that exited fails without a crash. The process starts through `zsh -l`, so it gets the PATH of the login shell, and a command can be a name on that PATH.

`AgentProbe` checks the health of each agent for Settings. For Claude Code, it runs `claude --version` and `claude auth status`. For an ACP agent, it sends `initialize` and reads the answer. Each check stops after 10 seconds.

### Turns

At most two sessions are in a turn. Other turns wait. A timer stops a turn after 10 minutes of work. The timer stops while a request waits. After a turn, the process stays open for the next message. It ends on Stop for Claude Code, on a failure, on Delete Session, on a change of the model or the mode of Claude Code, or when Piper quits. Then the next message starts a new process that resumes the session.

The session composer handles Return, Tab, the arrows, and Escape in `textView(_:doCommandBy:)` of `CaptureEditor`. An `NSEvent` monitor kept the view from its first appearance, and Return then sent to an old session.

`SkillTarget` names what the main window shows: `page(path)`, `text(text, noteID)`, or `folder`. `MainWindowController` sets `AppModel.actionTarget` with the selection, and the session card takes a page as context. A Send action opens a session draft with the skill command and note text. The composer sends the edited draft when the reader presses Return.

The `sessions` table stores each session at each change of state. Quit asks before it stops sessions in a turn. `AppDelegate` also stops them on SIGTERM, because a child process keeps running after its parent exits.

## Vault

`Vault` lists every file and folder under the root and applies no rule about structure. `VaultFile` holds the path, size, modification date, text, and parsed frontmatter. `VaultWatcher` wraps `FSEventStream` on a private queue and calls back on the main queue.

`AppModel` stores the folder list and the active root in preferences. `removeWikiFolder` moves the active root to another folder before it removes a root.

`AppModel` starts the watcher with the first scan and replaces it when the active root changes. A scan runs in the background. A change during a scan requests one more scan. A scan keeps unsaved edit sessions and updates clean editors and previews. See [Wiki files](../concepts/files.md).

`FileReadState` stores the last-read modification time of each file. `AppModel` computes unread state and folder counts, including subfolders. The first file selection waits until the detail pane shows before it marks the file read.

## Reading And Editing

`FilePresentation` decides how the detail pane shows a file. Markdown opens in the editor, other text in a read-only text view, and everything else in Quick Look. `AppModel.showsFileSource` holds the choice of the Source tab. For Markdown, Source is the source mode of the editor. For HTML, it is `PlainTextPreview`.

### The Editor Page

The Markdown editor is the editor of Hubble.md, a Tiptap and React editor, in a `WKWebView`. `web/` holds its source:

- `web/vendor/hubble/` is a copy of `packages/editor` and `packages/ui` of Hubble.md. Its `README.md` names the source commit and the local changes.
- `web/src/` is the host: the bridge, the image and embed nodes, the loss guard, and the theme of Piper.
- `make web` builds one file, `Sources/Piper/Resources/editor.html`, with the JS and CSS inline. The repository holds this file. The build also writes `Licenses/Editor.txt`.

`EditorPage` owns one web view for the main window. A change of file sends a new `open` call to the same page, so the page loads once. `EditorPane` moves the web view into the detail pane. Piper calls the functions on `window.piper`, and the page sends messages to the `editor` handler, which answers each message:

| From Piper | Effect |
| --- | --- |
| `open` | Shows a file, with its full text, its mode, the byline, and the link targets. |
| `replace` | Puts the disk text into the open file with no undo step. |
| `header`, `theme`, `scrollTo`, `command`, `assetChanged` | Change the byline, the reading theme, the scroll position, run Find, and reload an embed. |
| `setNotes` | Draws the margin cards of the file. |
| `flush` | Returns the current text, for quit and Command-S. |

| From the page | Piper does |
| --- | --- |
| `change` | `AppModel.editorChanged` saves the text. |
| `link` | Opens a wiki link or a URL. |
| `image` | Writes a pasted image to `<note>.assets/` and answers with its path. |
| `lossy` | Sets `EditorSession.lossy`. |
| `note`, `ask`, `explain`, `define`, `followup`, `continue`, `capture`, `open`, `copy` | `AppModel.performFileAction` runs the action of the selection bar or the card. |

`AssetSchemeHandler` serves the files of the folder at `piper-asset://folder/<path>`, for images and embeds, through `Vault.containedURL`. An HTML file gets a `sandbox` content security policy, and the iframe has no `allow-same-origin`.

`ReaderLayer.tsx` ports the selection bar and the margin cards of `reader.html` to the editor page. A highlight is the `highlight` mark, which `HighlightMarkdown.ts` reads and writes as `==text==` or `<mark class="color">`. The other actions go to `AppModel.performFileAction`, which calls `ReaderMarks.perform` with a page note for the file (`AppModel.fileLink`). `AppModel.fileNotes` sends the cards to the page through `setNotes`.

`lossGuard.ts` parses a file, writes it back, and compares the text, the link targets, and the structure. If they differ, or the file has footnotes, link titles, or table alignment, the rich editor is read-only. `EditorBanner` then offers the Source tab.

### Saving

`EditorSession` holds one Markdown file: its baseline, the editor text, its status, and its revision. `DiskChange.classify` compares the baseline, the editor text, and the disk text. `AppModel.editors` keeps the session of the open file, and each session with text that is not on disk. The page sends the last edit of a file after it opens the next file, so a session stays until that edit saves. A scan calls `EditorSession.diskChanged` for each file that changed. A conflict stops saves, and `EditorBanner` offers Reload or Keep Mine. `AppModel.settleEditors` saves each session before a folder change and before quit. It stops on a conflict.

### Command Palette

`CommandPaletteController` shows `CommandPaletteView` in a borderless child panel of the main window. `PaletteResults` ranks files with `PaletteSearch.score` and finds lines with `PaletteSearch.excerpts`, off the main thread. The scores copy `fuzzy.ts` of Hubble.md.

`WikiWorkspace` owns the navigation history. `WikiLinks` resolves links and computes backlinks. `WikiMarkdown` parses blocks for the outline, heading anchors, and backlinks.

## Inbox Reader

`NoteDetail` shows a capture. `CaptureLinks` finds HTTP and HTTPS URLs with `NSDataDetector` and keeps the original text. If the capture is only a URL, the reader opens it at once. `AppModel.articleTab` picks the Reader tab, the Web tab, or the Notes tab. `NoteDetail` shows Reader, Web, and Notes in a `TabIsland` at the bottom of the pane.

`NoteWebReader` embeds `WKWebView` through `NSViewRepresentable`, which works on macOS 14. It keeps the requested URL apart from the current URL, so a view update does not restart navigation after a redirect. A new capture selection resets the reader.

`ArticleReader` shows the Reader tab. `ArticleLoader` loads the page in a `WKWebView` outside the window and runs a script in an isolated content world. The script prefers an article container over the main page container. It returns headings, paragraphs, list items, quotes, and code blocks. If it finds no structured blocks, it splits the container text at blank lines. The article stays in memory for the rest of the launch.

`CaptureStore.pageText` returns the page text that a browser capture kept in the `pages` table. `ReaderArticle(url:title:pageText:)` turns each line of 40 characters or more into a paragraph. `ArticleLoader` uses that article when the load fails, or when the kept text has more than 2.5 times the words of the loaded article.

A second `WKWebView` loads `Resources/reader.html`, which allows no network requests. Piper calls `window.piper.render` with the article and `window.piper.setNotes` with the child notes. The page draws the text with `textContent`, so page markup never runs. Each action of the reader comes back through the `piper` message handler. The page draws the article again only when a mark changes, so an answer does not clear a selection.

The page reports the first block on the screen and the progress 250 milliseconds after a scroll stops. `ArticleReader` saves them in `Note.reading` 800 milliseconds later, through `CaptureStore.updateReading`, with no undo step. At a progress of 0.97, it records the finish time. When the article loads, `ArticleReader` records the title, the reading time, and the open time. It then picks the first place: a `ReaderScroll` request for this capture, the saved block, or the newest highlight from another app. A `ReaderScroll` names its capture, so a request for one article does not scroll another.

`ReaderAssistant` in `AppModel` saves highlights and questions as child notes, through `CaptureStore.addChild`. A highlight with a note of the reader is a `note` on the page, which draws it as a plain card. `HighlightText.comment` reads that note from the text after the quote. `NoteAnchor.locate` finds the quote of each note in the current article. One `AgentSession` answers the questions of one capture. Its `noteID` is the first question note. The assistant sends one message at a time and watches the session with `withObservationTracking`. When the turn ends, it appends the result text to the question note. Each answer thus stays after its own message in the transcript.

The Capture button runs JavaScript in an isolated content world. One call returns the selected text or the page text, the title, and the URL. `CaptureStore` saves the result to Inbox.

`ReadingList` in the `Captures` module groups the link captures that are not done into Continue, Up Next, and Finished This Week. `Note.isArticle` is true for a capture without a parent that has a reading state or holds only a link. `InboxStream` reads `ReadingList`. At launch, `AppModel` marks as done each article that the reader finished more than seven days before.

`ArticleNotebook` shows the Notes tab. Its summary is a child note with the tag `summary`. `ArticleMarkdown` builds the file of Save as File, and the text that Update File adds. `Vault.write` writes the file, and `Note.reading` records its path and the save time.

`Info.plist` sets `NSAllowsArbitraryLoadsInWebContent`, so WebKit can load HTTP pages. Other network requests keep the default App Transport Security policy.

## Search

Inbox search filters the active capture section and temporary clipboard cards. Go to File (Command-K) searches every file of the active folder. See [Command Palette](#command-palette).

## Daily Brief

`BriefBuilder` in the application target runs each build, and `BriefPage` shows the result. The build has these steps:

1. `BrowserCatalog` finds each source. `HistoryReader` and `NetNewsWireReader` read a private copy of each database, so another app cannot lock the file and the original does not change. `HackerNews` gets the popular submissions of the last day from the public search API.
2. `HistoryDigest` ranks the sites of the last 14 days. It drops blocked sites and full URLs, and it keeps 30 sites at most.
3. The runner starts a session with the purpose `brief`. Claude Code starts with `--restricted --tools "" --strict-mcp-config --no-session-persistence`, so the agent has no tool. The runner stores no transcript and deletes the session after the build.
4. The agent receives the digest and returns hosts. `BriefPrompts.hosts` keeps only the hosts in the digest.
5. `BriefPageLoader` makes the root URL of each host and loads it in a `WKWebView` with the default data store, which the Web tab also uses. A navigation to a blocked or private host stops.
6. The agent receives the page text, the feed articles, and the Hacker News stories, and returns Markdown.
7. `BriefLinks` removes images, HTML, and each link that no page, feed, or story holds. `BriefStore` writes the file.

The agent cannot put data in a URL, because Piper loads only URLs that it makes from known hosts. The Markdown can still hold false text from a page.

`BriefStore.linksBefore` reads the links of the briefs of earlier days. The build removes these links from each source and from the links that `BriefLinks` accepts, so no later brief repeats them.

`BriefDocument` converts the Markdown to the blocks of the reader page. The first highlight of a brief adds a parent note, and `ReaderMarks` handles its marks and actions for a brief and for a link capture. A selected link becomes a link capture that opens in the Web tab.

`BriefSchedule` decides when a morning build runs. A timer in `BriefBuilder` checks it every 15 minutes.

## QA Mode

A debug build that starts with `-PiperQA YES` is in QA mode. A test uses QA mode to drive Piper while the user works in another app.

- At launch, Piper opens the main window instead of the capture panel.
- `QA.activate` replaces `NSApp.activate`, so Piper never becomes the active app.
- `QAScripts` runs JavaScript in the editor page. A test posts the distributed notification `com.piper.qa.eval` with the body of an async function. Piper writes the result to the file that `-PiperQAResult` names.

macOS sends keys only to the active app. Thus a test in QA mode inserts text with a script, not with keys. A release build has no QA mode.

## Source Map

| Source | Responsibility |
| --- | --- |
| [PiperApp.swift](../../Sources/Piper/PiperApp.swift) | `AppDelegate`, menus, the menu bar item, editor windows, the toast, and quit |
| [AppModel.swift](../../Sources/Piper/AppModel.swift) | Scans, selection, and edit sessions |
| [AppDefaults.swift](../../Sources/Piper/AppDefaults.swift) | Preference keys, sizes, and metrics |
| [AppNotifications.swift](../../Sources/Piper/AppNotifications.swift) | Notification names |
| [PiperTheme.swift](../../Sources/Piper/PiperTheme.swift) | App colors, shapes, fonts, and shared controls |
| [FileReadState.swift](../../Sources/Piper/FileReadState.swift) | Read timestamps for each file |
| [CaptureService.swift](../../Sources/Piper/CaptureService.swift) | Global shortcuts, Accessibility selection, and web page capture |
| [ReadingToast.swift](../../Sources/Piper/ReadingToast.swift) | The toast of a web page capture and its note field |
| [ReaderAssistant.swift](../../Sources/Piper/ReaderAssistant.swift) | `ReaderArticle`, highlights, notes, and Claude questions of the Reader tab |
| [FolderAgents.swift](../../Sources/Piper/FolderAgents.swift) | Folders with skills, default skills, and every send action |
| [AgentViews.swift](../../Sources/Piper/AgentViews.swift) | The session badge, the Send button, and the skill list |
| [Sessions/](../../Sources/Piper/Sessions) | The session pane, the transcript views, the cards, the message field, the session card, and the detached session panel |
| [SendShortcut.swift](../../Sources/Piper/SendShortcut.swift) | The Control-Option-W hotkey |
| [Modules/Agents/](../../Sources/Modules/Agents) | Skill discovery, command parsing, sessions, the JSON stream, allow rules, and the session runner |
| [CapturePanel/](../../Sources/Piper/CapturePanel) | `CapturePanelController` and `ClipboardPaster` |
| [CaptureView.swift](../../Sources/Piper/CaptureView.swift) | The capture list, tabs, selection bar, and composer |
| [CaptureRows.swift](../../Sources/Piper/CaptureRows.swift) | Capture rows, headers, and the section and note sheets |
| [CaptureEditor.swift](../../Sources/Piper/CaptureEditor.swift) | The composer text view |
| [MainWindow/MainWindowController.swift](../../Sources/Piper/MainWindow/MainWindowController.swift) | Split view, toolbar, and routing between panes |
| [MainWindow/MainWindowState.swift](../../Sources/Piper/MainWindow/MainWindowState.swift) | `SidebarSelection`, restored state, and pane delegate protocols |
| [MainWindow/PaneViewControllers.swift](../../Sources/Piper/MainWindow/PaneViewControllers.swift) | One hosting view controller for each pane |
| [MainWindow/RouteSheets.swift](../../Sources/Piper/MainWindow/RouteSheets.swift) | The error alert |
| [Brief/](../../Sources/Piper/Brief) | The Brief page, its settings, the sign-in sheet, the builder, and the page loader |
| [Modules/Briefs/](../../Sources/Modules/Briefs) | Sources, history and feed reads, the digest, blocked sites, link cleaning, prompts, the schedule, and the files |
| [MainWindow/Sidebar/](../../Sources/Piper/MainWindow/Sidebar) | Library rows, the session rows, the folder tree, unread counts, and file warnings |
| [InboxRow.swift](../../Sources/Piper/InboxRow.swift) | The rows of the Inbox stream and the progress ring |
| [MainWindow/Detail/](../../Sources/Piper/MainWindow/Detail) | Header, file previews, the Reader tab, and the Notes tab |
| [Modules/Captures/ReadingList.swift](../../Sources/Modules/Captures/ReadingList.swift) | The Reading groups and the Markdown of Save as File |
| [Modules/Captures/InboxStream.swift](../../Sources/Modules/Captures/InboxStream.swift) | The groups and the chip counts of the Inbox stream |
| [MainWindow/Detail/EditorPage.swift](../../Sources/Piper/MainWindow/Detail/EditorPage.swift) | The editor page, its bridge, the asset scheme, and the conflict bar |
| [EditorSession.swift](../../Sources/Piper/EditorSession.swift) | The save of a Markdown file and the conflict rules |
| [MainWindow/CommandPalette.swift](../../Sources/Piper/MainWindow/CommandPalette.swift) | The command palette |
| [ReadingAppearance.swift](../../Sources/Piper/ReadingAppearance.swift) | Reading themes, fonts, and appearance |
| [web/](../../web) | The source of the editor page |
| [WikiWorkspace.swift](../../Sources/Piper/WikiWorkspace.swift) | Navigation history, link resolution, and backlinks |
| [WikiMarkdown.swift](../../Sources/Piper/WikiMarkdown.swift) | Block parsing, heading anchors, and inline text |
| [Wiki.swift](../../Sources/Piper/Wiki.swift) | File metadata |
| [SettingsWindow.swift](../../Sources/Piper/SettingsWindow.swift) | The Settings window and its panes |
| [QAHooks.swift](../../Sources/Piper/QAHooks.swift) | QA mode: no activation, and scripts in the editor page |

