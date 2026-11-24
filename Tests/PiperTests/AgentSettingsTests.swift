import AppKit
import Agents
import Captures
import CapturesDatabase
import Vault
import XCTest
@testable import Piper

@MainActor
final class AgentSettingsTests: XCTestCase {
    private var root: URL!
    private var preferences: UserDefaults!
    private var suite: String!
    private var database: Database!
    private var store: CaptureStore!
    private var wiki: URL!
    private var notes: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("folder-agents-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "AgentSettingsTests." + UUID().uuidString
        preferences = UserDefaults(suiteName: suite)!
        database = try Database(url: root.appendingPathComponent("notes.sqlite"))
        store = CaptureStore(database: .success(database))
        wiki = try folder("wiki", skills: ["capture": "<url> [note]", "new": "<type> <title>",
                                           "verify": "<path> [--stale-after DATE]", "stale": "[--within 14d]"])
        notes = try folder("notes", skills: ["capture": "<url>", "tidy": nil])
        try FileManager.default.createDirectory(at: root.appendingPathComponent("plain"), withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        preferences.removePersistentDomain(forName: suite)
        store = nil
        database = nil
        try FileManager.default.removeItem(at: root)
    }

    private func folder(_ name: String, skills: [String: String?]) throws -> URL {
        let url = root.appendingPathComponent(name)
        for (skill, hint) in skills {
            let directory = url.appendingPathComponent(".claude/skills/\(skill)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let hintLine = hint.map { "argument-hint: \($0)\n" } ?? ""
            try "---\nname: \(skill)\ndescription: The \(skill) skill.\n\(hintLine)---\nRun $ARGUMENTS"
                .write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        return url
    }

    /// A stand-in for `claude` that records the text of each message and ends the turn.
    private func fakeClaude() throws -> URL {
        let url = root.appendingPathComponent("claude")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          printf '%s\\n' "$line" | sed -n 's/.*"text":"\\([^"]*\\)".*/\\1/p' >> "\(root.path)/prompts.txt"
          echo '{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
        done
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// The settings, the skill folders, and the Send actions of one app.
    private struct Parts {
        let agents: AgentSettings
        let skills: SkillFolders
        let send: Send
    }

    private func makeParts() throws -> Parts {
        let agents = AgentSettings(storage: database, messages: Messages(), preferences: preferences)
        agents.executable = try fakeClaude()
        agents.runner.usesLoginShell = false
        let skills = makeSkills()
        return Parts(agents: agents, skills: skills, send: Send(store: store, agents: agents, skills: skills))
    }

    private func makeSkills() -> SkillFolders {
        let skills = SkillFolders(preferences: preferences)
        skills.paths = [wiki.path, root.appendingPathComponent("plain").path, notes.path]
        return skills
    }

    private func newAgents(_ messages: Messages? = nil) -> AgentSettings {
        AgentSettings(storage: database, messages: messages ?? Messages(), preferences: preferences)
    }

    private func waitForRuns(_ agents: AgentSettings) async throws {
        try await waitFor("The runs finish.") { agents.runner.activeCount == 0 }
    }

    private func prompts() throws -> [String] {
        let url = root.appendingPathComponent("prompts.txt")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    // MARK: - Folders and defaults

    func testFindsFoldersWithSkillsAndHonorsTheSwitch() throws {
        let skills = makeSkills()
        XCTAssertEqual(skills.folders.map(\.name), ["wiki", "notes"])
        XCTAssertEqual(skills.defaultFolder?.name, "wiki")

        skills.setEnabled(false, for: skills.folders[0])
        XCTAssertEqual(skills.folders.map(\.name), ["notes"])
        XCTAssertEqual(skills.defaultFolder?.name, "notes")
        XCTAssertEqual(skills.available.count, 2)

        let restored = SkillFolders(preferences: preferences)
        restored.paths = [wiki.path, notes.path]
        XCTAssertEqual(restored.folders.map(\.name), ["notes"])
    }

    /// Settings stored by a path through a symbolic link still apply to the folder.
    func testStoredSettingsOfAFolderThroughALinkStillApply() throws {
        let link = root.appendingPathComponent("linked-notes")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: notes)
        preferences.set([link.path], forKey: AppDefaults.Key.agentDisabledFolders)
        preferences.set(["link|" + link.path: SkillFolders.noSkill], forKey: AppDefaults.Key.agentDefaultSkills)

        let skills = SkillFolders(preferences: preferences)
        skills.paths = [link.path]
        let folder = try XCTUnwrap(skills.available.first)
        XCTAssertFalse(skills.isEnabled(folder))
        skills.setEnabled(true, for: folder)
        XCTAssertNil(skills.defaultSkill(forLink: true, in: folder))
    }

    func testRefreshReadsTheSkillsAgain() throws {
        let plain = root.appendingPathComponent("plain")
        let skills = SkillFolders(preferences: preferences)
        skills.paths = [plain.path]
        let directory = plain.appendingPathComponent(".claude/skills/later")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "---\nname: later\n---\nRun".write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        skills.reload()
        XCTAssertEqual(skills.available.first?.skills.map(\.name), ["later"])
    }

    func testChoosingTheClaudeCommandChecksItsHealth() {
        let agents = newAgents()
        agents.claudePath = root.appendingPathComponent("missing-claude").path
        XCTAssertEqual(agents.health[AgentDefinition.claudeCodeID], .checking)
    }

    func testReadsTheSkillsAgainWhenASkillFileChanges() async throws {
        let plain = root.appendingPathComponent("plain")
        let skills = SkillFolders(preferences: preferences)
        skills.paths = [plain.path]
        XCTAssertTrue(skills.available.isEmpty)

        let directory = plain.appendingPathComponent(".claude/skills/later")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "---\nname: later\n---\nRun".write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try await waitFor("The new skill appears.") { !skills.available.isEmpty }
        XCTAssertEqual(skills.available.first?.skills.map(\.name), ["later"])
    }

    func testDefaultActionDependsOnLinkOrTextAndTheStoredChoice() throws {
        let skills = makeSkills()
        XCTAssertEqual(skills.defaultAction(for: " https://example.com/a ")?.skill.name, "capture")
        XCTAssertEqual(skills.defaultAction(for: "A thought about https://example.com")?.skill.name, "new")

        let wikiFolder = skills.folders[0]
        skills.setDefaultSkill("stale", forLink: false, in: wikiFolder)
        XCTAssertEqual(skills.defaultAction(for: "A thought")?.skill.name, "stale")
        skills.setDefaultSkill(SkillFolders.noSkill, forLink: true, in: wikiFolder)
        XCTAssertNil(skills.defaultAction(for: "https://example.com"))

        // The notes folder has no `new` skill, so text has no default there.
        skills.setEnabled(false, for: wikiFolder)
        XCTAssertEqual(skills.defaultAction(for: "https://example.com")?.folder.name, "notes")
        XCTAssertNil(skills.defaultAction(for: "A thought"))
    }

    func testCompletionsAndCommandsPreferTheDefaultFolder() throws {
        let skills = makeSkills()
        XCTAssertEqual(skills.completions(for: "").map(\.id).count, 6)
        XCTAssertEqual(skills.completions(for: "CA").map(\.folder.name), ["wiki", "notes"])
        XCTAssertEqual(skills.completions(for: "t").map(\.skill.name), ["tidy"])
        XCTAssertEqual(skills.action(for: SlashCommand(name: "capture"))?.folder.name, "wiki")
        XCTAssertEqual(skills.action(for: SlashCommand(name: "tidy"))?.folder.name, "notes")
        XCTAssertNil(skills.action(for: SlashCommand(name: "missing")))

        let notesCapture = try XCTUnwrap(skills.completions(for: "capture").last)
        XCTAssertEqual(skills.action(for: SlashCommand(name: "capture"), chosen: notesCapture)?.folder.name, "notes")
        XCTAssertEqual(skills.action(for: SlashCommand(name: "tidy"), chosen: notesCapture)?.skill.name, "tidy")
    }

    // MARK: - Sending

    func testSendPreparesAnEditableDraftAndRemembersTheFolder() async throws {
        let parts = try makeParts()
        var shown: [UUID] = []
        parts.agents.showSession = { shown.append($0.id) }
        let note = try store.add("https://example.com/page", section: store.activeSection)
        let notesAction = try XCTUnwrap(parts.skills.completions(for: "capture").last)

        let session = try parts.send.note(note, action: notesAction)
        XCTAssertEqual(shown, [session.id])
        XCTAssertEqual(session.folder, notes.standardizedFileURL.path)
        XCTAssertEqual(session.command, SlashCommand(name: "capture", arguments: "https://example.com/page"))
        XCTAssertEqual(session.agentID, AgentDefinition.claudeCodeID)
        XCTAssertEqual(parts.skills.defaultFolder?.name, "notes")
        XCTAssertEqual(session.folderName, "notes")
        XCTAssertEqual(session.noteID, note.id)
        XCTAssertEqual(session.draft, "/capture https://example.com/page")
        XCTAssertTrue(session.blocks.isEmpty)
        XCTAssertEqual(parts.agents.runner.activeCount, 0)
        XCTAssertEqual(try prompts(), [])

        session.draft += " Summarize the examples"
        parts.agents.runner.send(session.draft, to: session)
        XCTAssertEqual(session.draft, "")
        try await waitForRuns(parts.agents)

        XCTAssertEqual(parts.agents.runner.latestSession(for: note.id)?.state, .idle)
        XCTAssertEqual(try prompts(), ["/capture https://example.com/page Summarize the examples"])
        XCTAssertEqual(session.command?.arguments, "https://example.com/page Summarize the examples")
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.notes[0].text, "https://example.com/page")
        XCTAssertEqual(SkillFolders(preferences: preferences).lastFolderPath, notes.standardizedFileURL.path)
    }

    func testSendPreparesEachNoteWithItsOwnSkill() async throws {
        let parts = try makeParts()
        XCTAssertNoThrow(try store.add("https://example.com/a", section: store.activeSection))
        XCTAssertNoThrow(try store.add("Decision keep runs", section: store.activeSection))

        XCTAssertEqual(try store.notes.map { try parts.send.note($0) }.count, 2)
        try await waitForRuns(parts.agents)
        XCTAssertEqual(try prompts(), [])
        XCTAssertEqual(store.notes.compactMap { parts.agents.runner.latestSession(for: $0.id)?.draft }.sorted(),
                       ["/capture https://example.com/a", "/new Decision keep runs"])
    }

    func testADraftWithoutACommandUsesTheAgentOfANewSession() throws {
        let agents = newAgents()
        agents.addAgent(name: "Fake", command: "/usr/bin/true", arguments: [])
        let added = try XCTUnwrap(agents.acpAgents.first)
        agents.sessionAgentID = added.id
        let session = agents.openDraft(text: "About this\n\n", folder: wiki.path)
        XCTAssertEqual(session.agentID, added.id)
        XCTAssertEqual(session.draft, "About this\n\n")
        XCTAssertNil(session.command)
    }

    func testSendingAClipboardTextSavesItFirst() async throws {
        let parts = try makeParts()
        let clipboard = ClipboardInbox(store: store, database: database, pasteboard: NSPasteboard(name: .init("com.piper.test." + UUID().uuidString))) {
            XCTFail("\($0)")
        }
        clipboard.receive(["https://example.com/copied"])
        let entry = try XCTUnwrap(clipboard.entries.first)

        let session = try XCTUnwrap(try parts.send.clip(entry, from: clipboard))
        XCTAssertEqual(store.notes.map(\.text), ["https://example.com/copied"])
        XCTAssertEqual(store.notes.first?.section, "Inbox")
        XCTAssertEqual(session.noteID, store.notes.first?.id)
        XCTAssertTrue(clipboard.entries.isEmpty)
        XCTAssertEqual(session.draft, "/capture https://example.com/copied")
        XCTAssertTrue(session.blocks.isEmpty)
        XCTAssertEqual(try prompts(), [])
    }

    func testSendingThePasteboardSkipsANoteThatWasSent() async throws {
        let parts = try makeParts()
        let pasteboard = NSPasteboard(name: .init("com.piper.test." + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("https://example.com/twice", forType: .string)

        let session = try parts.send.pasteboard(pasteboard)
        session.draft += " Added instructions"
        XCTAssertEqual(try parts.send.pasteboard(pasteboard).id, session.id)
        XCTAssertTrue(session.draft.hasSuffix("Added instructions"))
        XCTAssertEqual(try prompts(), [])
        parts.agents.runner.send(session.draft, to: session)
        try await waitForRuns(parts.agents)
        XCTAssertThrowsError(try parts.send.pasteboard(pasteboard)) { error in
            XCTAssertEqual(error.localizedDescription, "Already sent to wiki")
        }
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(try prompts().count, 1)

        pasteboard.clearContents()
        XCTAssertThrowsError(try parts.send.pasteboard(pasteboard)) { error in
            XCTAssertEqual(error.localizedDescription, "The clipboard has no text")
        }
    }

    func testComposerCommandSavesItsArgumentsAsANote() async throws {
        let parts = try makeParts()
        XCTAssertNoThrow(try store.chooseSection("Research"))

        XCTAssertNotNil(try parts.send.run(SlashCommand("/capture https://example.com/x")!))
        XCTAssertNotNil(try parts.send.run(SlashCommand("/stale")!))
        let tidy = try XCTUnwrap(parts.skills.completions(for: "tidy").first)
        XCTAssertNotNil(try parts.send.run(SlashCommand(name: "tidy"), action: tidy))
        // A chosen action for another skill is ignored, and the folder used last wins.
        XCTAssertEqual(try parts.send.run(SlashCommand(name: "capture"), action: tidy)?.folder, notes.standardizedFileURL.path)
        XCTAssertNil(try parts.send.run(SlashCommand("/missing text")!))

        XCTAssertEqual(store.notes.map(\.text), ["https://example.com/x", "/stale", "/tidy", "/capture"])
        XCTAssertTrue(store.notes.allSatisfy { $0.section == "Research" })
        XCTAssertEqual(parts.agents.runner.latestSession(for: store.notes[2].id)?.folder, notes.standardizedFileURL.path)
        try await waitForRuns(parts.agents)
        XCTAssertEqual(try prompts().sorted(), ["/capture", "/capture https://example.com/x", "/stale", "/tidy"])
    }

    // MARK: - Executable

    func testSessionsDefaultToSonnetInAutoModeAndKeepTheChoice() {
        let claudeCode = AgentConfig(agentID: AgentDefinition.claudeCodeID)
        let agents = newAgents()
        XCTAssertEqual(agents.model, "sonnet")
        XCTAssertEqual(agents.runner.config(claudeCode), AgentConfig(agentID: claudeCode.agentID, model: "sonnet", mode: "auto"))

        agents.permissionMode = .ask
        XCTAssertEqual(newAgents().runner.config(claudeCode).mode, "manual")
        XCTAssertEqual(preferences.string(forKey: AppDefaults.Key.claudePermissionMode), "manual")

        agents.model = "opus"
        XCTAssertEqual(agents.runner.config(claudeCode).model, "opus")
        XCTAssertEqual(newAgents().runner.config(claudeCode).model, "opus")

        agents.model = ""
        XCTAssertEqual(newAgents().model, "")
    }

    func testAgentsPersistAndSetTheDefaultsOfNewSessions() throws {
        let agents = newAgents()
        agents.addAgent(name: "Fake", command: "/usr/bin/true", arguments: ["acp"])
        let added = try XCTUnwrap(agents.acpAgents.first)
        XCTAssertEqual(added.kind, .acp)
        XCTAssertEqual(agents.runner.agents.map(\.id), [AgentDefinition.claudeCodeID, added.id])

        let reloaded = newAgents()
        XCTAssertEqual(reloaded.acpAgents, [added])
        XCTAssertEqual(reloaded.runner.config(AgentConfig(agentID: added.id)), AgentConfig(agentID: added.id))

        reloaded.sessionAgentID = added.id
        let session = reloaded.newSession(in: wiki.path, mode: "plan")
        XCTAssertEqual(session.agentID, added.id)
        XCTAssertEqual(session.mode, "plan")
        XCTAssertEqual(session.purpose, .session)

        let margin = reloaded.newMarginSession(in: wiki.path, noteID: UUID())
        XCTAssertEqual(margin.agentID, AgentDefinition.claudeCodeID)
        XCTAssertEqual(margin.purpose, .margin)
        XCTAssertEqual(margin.model, "haiku")

        reloaded.setMarginAgent(added.id)
        XCTAssertEqual(reloaded.marginModel, "")
        reloaded.removeAgent(added)
        XCTAssertTrue(reloaded.acpAgents.isEmpty)
        XCTAssertEqual(reloaded.sessionAgentID, AgentDefinition.claudeCodeID)
        XCTAssertEqual(reloaded.marginAgentID, AgentDefinition.claudeCodeID)
        XCTAssertEqual(reloaded.marginModel, ClaudeCodeConnection.defaultMarginModel)
    }

    func testAnUnreadableAgentListIsReportedAndNotOverwritten() throws {
        let stored = Data("not a list".utf8)
        preferences.set(stored, forKey: AppDefaults.Key.acpAgents)
        let messages = Messages()
        let agents = newAgents(messages)
        XCTAssertEqual(messages.last?.isError, true)
        XCTAssertTrue(agents.acpAgents.isEmpty)

        agents.addAgent(name: "Fake", command: "/usr/bin/true", arguments: [])
        XCTAssertEqual(agents.acpAgents.map(\.name), ["Fake"])
        XCTAssertEqual(preferences.data(forKey: AppDefaults.Key.acpAgents), stored)
    }

    func testRemovedAgentReadsAsMissing() throws {
        let agents = newAgents()
        agents.addAgent(name: "Fake", command: "/usr/bin/true", arguments: [])
        let added = try XCTUnwrap(agents.acpAgents.first)
        XCTAssertEqual(agents.agent(added.id), added)
        agents.removeAgent(added)
        XCTAssertNil(agents.agent(added.id))
        XCTAssertEqual(agents.agent(AgentDefinition.claudeCodeID)?.kind, .claudeCode)
    }

    func testAnAgentListFromAnOlderPiperReadsAsACPAgents() {
        let stored = #"[{"id":"a1","name":"OpenCode","command":"opencode","arguments":["acp"]}]"#
        preferences.set(Data(stored.utf8), forKey: AppDefaults.Key.acpAgents)
        let agents = newAgents()
        XCTAssertEqual(agents.acpAgents, [AgentDefinition(id: "a1", name: "OpenCode", command: "opencode", arguments: ["acp"])])
        XCTAssertEqual(agents.kind(of: "a1"), .acp)
    }

    func testAgentWithoutAReadOnlyModeCannotAnswerInTheMargin() async throws {
        let script = root.appendingPathComponent("acp-agent")
        try """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -n 's/.*"id":\\([0-9]*\\).*/\\1/p')
          case "$line" in
            *'"method":"initialize"'*) echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1}}' ;;
            *'"method":"session/new"'*) echo '{"jsonrpc":"2.0","id":'$id',"result":{"sessionId":"a","modes":{"currentModeId":"code","availableModes":[{"id":"code","name":"Code"}]}}}' ;;
            *'"method":"session/prompt"'*) echo '{"jsonrpc":"2.0","id":'$id',"result":{"stopReason":"end_turn"}}' ;;
          esac
        done
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let agents = try makeParts().agents
        agents.addAgent(name: "Coder", command: script.path, arguments: [])
        let coder = try XCTUnwrap(agents.acpAgents.first)
        agents.setMarginAgent(coder.id)
        XCTAssertEqual(agents.marginAgents.map(\.id), [AgentDefinition.claudeCodeID, coder.id])

        let session = agents.newSession(in: wiki.path, agentID: coder.id)
        agents.runner.send("Hello", to: session)
        try await waitForRuns(agents)
        XCTAssertEqual(agents.marginAgents.map(\.id), [AgentDefinition.claudeCodeID])
        XCTAssertEqual(agents.marginChoice, AgentConfig(agentID: AgentDefinition.claudeCodeID,
                                                        model: ClaudeCodeConnection.defaultMarginModel))

        let margin = agents.newMarginSession(in: wiki.path, noteID: UUID())
        XCTAssertEqual(margin.agentID, AgentDefinition.claudeCodeID)
        XCTAssertEqual(agents.marginAgentID, AgentDefinition.claudeCodeID)
        XCTAssertEqual(margin.model, ClaudeCodeConnection.defaultMarginModel)
    }

    func testFindsClaudeInTheUsualPlaces() {
        let found = AgentSettings.executable(chosen: nil, home: "/Users/me") { $0 == "/opt/homebrew/bin/claude" }
        XCTAssertEqual(found?.path, "/opt/homebrew/bin/claude")
        XCTAssertEqual(AgentSettings.executable(chosen: nil, home: "/Users/me") { $0 == "/Users/me/.local/bin/claude" }?.path,
                       "/Users/me/.local/bin/claude")
        XCTAssertNil(AgentSettings.executable(chosen: nil, home: "/Users/me") { _ in false })
        XCTAssertEqual(AgentSettings.executable(chosen: "/tmp/claude") { _ in false }?.path, "/tmp/claude")
    }

    // MARK: - Opening results

    func testOpeningARunFileWaitsForTheScanThatFindsIt() async throws {
        try "# Home".write(to: wiki.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)
        preferences.set(notes.path, forKey: AppDefaults.Key.vaultPath)
        let model = AppModel(databaseURL: root.appendingPathComponent("notes.sqlite"), preferences: preferences)
        let desk = PaperDesk(model: model, defaults: preferences)
        defer { desk.hide() }

        try FileManager.default.createDirectory(at: wiki.appendingPathComponent("sources"), withIntermediateDirectories: true)
        try "# New".write(to: wiki.appendingPathComponent("sources/new.md"), atomically: true, encoding: .utf8)
        model.files.openRunFile("sources/new.md", in: wiki.path)

        try await waitFor("The scan finds the file.") { model.files.selectedDocument == "sources/new.md" }
        XCTAssertEqual(model.library.vault.root, Vault(path: wiki.path).root)
        XCTAssertEqual(model.files.selectedDocument, "sources/new.md")
        XCTAssertTrue(desk.paper.marks.isOpenFile("sources/new.md"))
    }
}
