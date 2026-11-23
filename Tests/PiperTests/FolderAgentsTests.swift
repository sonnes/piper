import AppKit
import Agents
import Captures
import Vault
import XCTest
@testable import Piper

@MainActor
final class FolderAgentsTests: XCTestCase {
    private var root: URL!
    private var preferences: UserDefaults!
    private var suite: String!
    private var store: CaptureStore!
    private var wiki: URL!
    private var notes: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("folder-agents-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "FolderAgentsTests." + UUID().uuidString
        preferences = UserDefaults(suiteName: suite)!
        store = CaptureStore(url: root.appendingPathComponent("notes.sqlite"))
        wiki = try folder("wiki", skills: ["capture": "<url> [note]", "new": "<type> <title>",
                                           "verify": "<path> [--stale-after DATE]", "stale": "[--within 14d]"])
        notes = try folder("notes", skills: ["capture": "<url>", "tidy": nil])
        try FileManager.default.createDirectory(at: root.appendingPathComponent("plain"), withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        preferences.removePersistentDomain(forName: suite)
        store = nil
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

    private func makeAgents() throws -> FolderAgents {
        let agents = FolderAgents(store: store, messages: Messages(), preferences: preferences)
        agents.runner.executable = try fakeClaude()
        agents.runner.usesLoginShell = false
        agents.refresh(paths: [wiki.path, root.appendingPathComponent("plain").path, notes.path])
        return agents
    }

    private func waitForRuns(_ agents: FolderAgents) async throws {
        for _ in 0..<500 {
            if agents.runner.activeCount == 0 { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The runs did not finish")
    }

    private func prompts() throws -> [String] {
        let url = root.appendingPathComponent("prompts.txt")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    // MARK: - Folders and defaults

    func testFindsFoldersWithSkillsAndHonorsTheSwitch() throws {
        let agents = try makeAgents()
        XCTAssertEqual(agents.folders.map(\.name), ["wiki", "notes"])
        XCTAssertEqual(agents.defaultFolder?.name, "wiki")

        agents.setEnabled(false, for: agents.folders[0])
        XCTAssertEqual(agents.folders.map(\.name), ["notes"])
        XCTAssertEqual(agents.defaultFolder?.name, "notes")
        XCTAssertEqual(agents.available.count, 2)

        let restored = FolderAgents(store: store, messages: Messages(), preferences: preferences)
        restored.refresh(paths: [wiki.path, notes.path])
        XCTAssertEqual(restored.folders.map(\.name), ["notes"])
    }

    func testDefaultActionDependsOnLinkOrTextAndTheStoredChoice() throws {
        let agents = try makeAgents()
        XCTAssertEqual(agents.defaultAction(for: " https://example.com/a ")?.skill.name, "capture")
        XCTAssertEqual(agents.defaultAction(for: "A thought about https://example.com")?.skill.name, "new")

        let wikiFolder = agents.folders[0]
        agents.setDefaultSkill("stale", forLink: false, in: wikiFolder)
        XCTAssertEqual(agents.defaultAction(for: "A thought")?.skill.name, "stale")
        agents.setDefaultSkill(FolderAgents.noSkill, forLink: true, in: wikiFolder)
        XCTAssertNil(agents.defaultAction(for: "https://example.com"))

        // The notes folder has no `new` skill, so text has no default there.
        agents.setEnabled(false, for: wikiFolder)
        XCTAssertEqual(agents.defaultAction(for: "https://example.com")?.folder.name, "notes")
        XCTAssertNil(agents.defaultAction(for: "A thought"))
    }

    func testCompletionsAndCommandsPreferTheDefaultFolder() throws {
        let agents = try makeAgents()
        XCTAssertEqual(agents.completions(for: "").map(\.id).count, 6)
        XCTAssertEqual(agents.completions(for: "CA").map(\.folder.name), ["wiki", "notes"])
        XCTAssertEqual(agents.completions(for: "t").map(\.skill.name), ["tidy"])
        XCTAssertEqual(agents.action(for: SlashCommand(name: "capture"))?.folder.name, "wiki")
        XCTAssertEqual(agents.action(for: SlashCommand(name: "tidy"))?.folder.name, "notes")
        XCTAssertNil(agents.action(for: SlashCommand(name: "missing")))
    }

    // MARK: - Sending

    func testSendPreparesAnEditableDraftAndRemembersTheFolder() async throws {
        let agents = try makeAgents()
        let note = try store.add("https://example.com/page", section: store.activeSection)
        let notesAction = try XCTUnwrap(agents.completions(for: "capture").last)

        let session = try agents.send(note, action: notesAction)
        XCTAssertEqual(session.folder, notes.standardizedFileURL.path)
        XCTAssertEqual(session.command, SlashCommand(name: "capture", arguments: "https://example.com/page"))
        XCTAssertEqual(agents.defaultFolder?.name, "notes")
        XCTAssertEqual(session.folderName, "notes")
        XCTAssertEqual(session.noteID, note.id)
        XCTAssertEqual(session.draft, "/capture https://example.com/page")
        XCTAssertTrue(session.blocks.isEmpty)
        XCTAssertEqual(agents.runner.activeCount, 0)
        XCTAssertEqual(try prompts(), [])

        session.draft += " Summarize the examples"
        agents.runner.send(session.draft, to: session)
        XCTAssertEqual(session.draft, "")
        try await waitForRuns(agents)

        XCTAssertEqual(agents.runner.latestSession(for: note.id)?.state, .idle)
        XCTAssertEqual(try prompts(), ["/capture https://example.com/page Summarize the examples"])
        XCTAssertEqual(session.command?.arguments, "https://example.com/page Summarize the examples")
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.notes[0].text, "https://example.com/page")
        XCTAssertEqual(FolderAgents(store: store, messages: Messages(), preferences: preferences).lastFolderPath, notes.standardizedFileURL.path)
    }

    func testSendPreparesEachNoteWithItsOwnSkill() async throws {
        let agents = try makeAgents()
        XCTAssertNoThrow(try store.add("https://example.com/a", section: store.activeSection))
        XCTAssertNoThrow(try store.add("Decision keep runs", section: store.activeSection))

        XCTAssertEqual(try store.notes.map { try agents.send($0) }.count, 2)
        try await waitForRuns(agents)
        XCTAssertEqual(try prompts(), [])
        XCTAssertEqual(store.notes.compactMap { agents.runner.latestSession(for: $0.id)?.draft }.sorted(),
                       ["/capture https://example.com/a", "/new Decision keep runs"])
    }

    func testSendingAClipboardTextSavesItFirst() async throws {
        let agents = try makeAgents()
        let clipboard = ClipboardInbox(store: store, pasteboard: NSPasteboard(name: .init("com.piper.test." + UUID().uuidString))) {
            XCTFail("\($0)")
        }
        clipboard.receive(["https://example.com/copied"])
        let entry = try XCTUnwrap(clipboard.entries.first)

        let session = try XCTUnwrap(try agents.send(entry, from: clipboard))
        XCTAssertEqual(store.notes.map(\.text), ["https://example.com/copied"])
        XCTAssertEqual(store.notes.first?.section, "Inbox")
        XCTAssertEqual(session.noteID, store.notes.first?.id)
        XCTAssertTrue(clipboard.entries.isEmpty)
        XCTAssertEqual(session.draft, "/capture https://example.com/copied")
        XCTAssertTrue(session.blocks.isEmpty)
        XCTAssertEqual(try prompts(), [])
    }

    func testSendingThePasteboardSkipsANoteThatWasSent() async throws {
        let agents = try makeAgents()
        let pasteboard = NSPasteboard(name: .init("com.piper.test." + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("https://example.com/twice", forType: .string)

        let session = try agents.sendPasteboard(pasteboard)
        session.draft += " Added instructions"
        XCTAssertEqual(try agents.sendPasteboard(pasteboard).id, session.id)
        XCTAssertTrue(session.draft.hasSuffix("Added instructions"))
        XCTAssertEqual(try prompts(), [])
        agents.runner.send(session.draft, to: session)
        try await waitForRuns(agents)
        XCTAssertThrowsError(try agents.sendPasteboard(pasteboard)) { error in
            XCTAssertEqual(error.localizedDescription, "Already sent to wiki")
        }
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(try prompts().count, 1)

        pasteboard.clearContents()
        XCTAssertThrowsError(try agents.sendPasteboard(pasteboard)) { error in
            XCTAssertEqual(error.localizedDescription, "The clipboard has no text")
        }
    }

    func testComposerCommandSavesItsArgumentsAsANote() async throws {
        let agents = try makeAgents()
        XCTAssertNoThrow(try store.chooseSection("Research"))

        XCTAssertNotNil(try agents.run(SlashCommand("/capture https://example.com/x")!))
        XCTAssertNotNil(try agents.run(SlashCommand("/stale")!))
        let tidy = try XCTUnwrap(agents.completions(for: "tidy").first)
        XCTAssertNotNil(try agents.run(SlashCommand(name: "tidy"), action: tidy))
        // A chosen action for another skill is ignored, and the folder used last wins.
        XCTAssertEqual(try agents.run(SlashCommand(name: "capture"), action: tidy)?.folder, notes.standardizedFileURL.path)
        XCTAssertNil(try agents.run(SlashCommand("/missing text")!))

        XCTAssertEqual(store.notes.map(\.text), ["https://example.com/x", "/stale", "/tidy", "/capture"])
        XCTAssertTrue(store.notes.allSatisfy { $0.section == "Research" })
        XCTAssertEqual(agents.runner.latestSession(for: store.notes[2].id)?.folder, notes.standardizedFileURL.path)
        try await waitForRuns(agents)
        XCTAssertEqual(try prompts().sorted(), ["/capture", "/capture https://example.com/x", "/stale", "/tidy"])
    }

    // MARK: - Executable

    func testSessionsDefaultToSonnetInAutoModeAndKeepTheChoice() {
        let agents = FolderAgents(store: store, messages: Messages(), preferences: preferences)
        XCTAssertEqual(agents.model, "sonnet")
        XCTAssertEqual(agents.runner.model, "sonnet")
        XCTAssertEqual(agents.runner.permissionMode, .auto)

        agents.permissionMode = .ask
        XCTAssertEqual(FolderAgents(store: store, messages: Messages(), preferences: preferences).runner.permissionMode, .ask)
        XCTAssertEqual(preferences.string(forKey: AppDefaults.Key.claudePermissionMode), "manual")

        agents.model = "opus"
        XCTAssertEqual(agents.runner.model, "opus")
        XCTAssertEqual(FolderAgents(store: store, messages: Messages(), preferences: preferences).runner.model, "opus")

        agents.model = ""
        XCTAssertEqual(FolderAgents(store: store, messages: Messages(), preferences: preferences).model, "")
    }

    func testAgentsPersistAndSetTheDefaultsOfNewSessions() throws {
        let agents = FolderAgents(store: store, messages: Messages(), preferences: preferences)
        agents.addAgent(name: "Fake", command: "/usr/bin/true", arguments: ["acp"])
        let added = try XCTUnwrap(agents.acpAgents.first)
        XCTAssertEqual(agents.runner.agents, [added])

        let reloaded = FolderAgents(store: store, messages: Messages(), preferences: preferences)
        XCTAssertEqual(reloaded.acpAgents, [added])
        XCTAssertEqual(reloaded.runner.agents, [added])

        reloaded.sessionAgentID = added.id
        let session = reloaded.newSession(in: wiki.path, mode: "plan")
        XCTAssertEqual(session.agentID, added.id)
        XCTAssertEqual(session.mode, "plan")
        XCTAssertEqual(session.purpose, .session)

        let margin = reloaded.newMarginSession(in: wiki.path, noteID: UUID())
        XCTAssertEqual(margin.agentID, AgentDefinition.claudeCodeID)
        XCTAssertEqual(margin.purpose, .margin)
        XCTAssertEqual(margin.model, "haiku")

        reloaded.marginAgentID = added.id
        reloaded.removeAgent(added)
        XCTAssertTrue(reloaded.acpAgents.isEmpty)
        XCTAssertEqual(reloaded.sessionAgentID, AgentDefinition.claudeCodeID)
        XCTAssertEqual(reloaded.marginAgentID, AgentDefinition.claudeCodeID)
    }

    func testRemovedAgentReadsAsMissing() throws {
        let agents = FolderAgents(store: store, messages: Messages(), preferences: preferences)
        agents.addAgent(name: "Fake", command: "/usr/bin/true", arguments: [])
        let added = try XCTUnwrap(agents.acpAgents.first)
        XCTAssertEqual(agents.agent(added.id), added)
        agents.removeAgent(added)
        XCTAssertNil(agents.agent(added.id))
        XCTAssertEqual(agents.agent(AgentDefinition.claudeCodeID), .claudeCode)
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
        let agents = try makeAgents()
        agents.addAgent(name: "Coder", command: script.path, arguments: [])
        let coder = try XCTUnwrap(agents.acpAgents.first)
        agents.marginAgentID = coder.id
        XCTAssertEqual(agents.marginAgents.map(\.id), [AgentDefinition.claudeCodeID, coder.id])

        let session = agents.newSession(in: wiki.path, agentID: coder.id)
        agents.runner.send("Hello", to: session)
        try await waitForRuns(agents)
        XCTAssertEqual(agents.marginAgents.map(\.id), [AgentDefinition.claudeCodeID])
        XCTAssertEqual(agents.marginAgent, .claudeCode)

        let margin = agents.newMarginSession(in: wiki.path, noteID: UUID())
        XCTAssertEqual(margin.agentID, AgentDefinition.claudeCodeID)
        XCTAssertEqual(agents.marginAgentID, AgentDefinition.claudeCodeID)
        XCTAssertEqual(margin.model, FolderAgents.defaultMarginModel)
    }

    func testFindsClaudeInTheUsualPlaces() {
        let found = FolderAgents.executable(chosen: nil, home: "/Users/me") { $0 == "/opt/homebrew/bin/claude" }
        XCTAssertEqual(found?.path, "/opt/homebrew/bin/claude")
        XCTAssertEqual(FolderAgents.executable(chosen: nil, home: "/Users/me") { $0 == "/Users/me/.local/bin/claude" }?.path,
                       "/Users/me/.local/bin/claude")
        XCTAssertNil(FolderAgents.executable(chosen: nil, home: "/Users/me") { _ in false })
        XCTAssertEqual(FolderAgents.executable(chosen: "/tmp/claude") { _ in false }?.path, "/tmp/claude")
    }

    // MARK: - Opening results

    func testOpeningARunFileWaitsForTheScanThatFindsIt() async throws {
        try "# Home".write(to: wiki.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)
        preferences.set(notes.path, forKey: AppDefaults.Key.vaultPath)
        let model = AppModel(store: store, preferences: preferences)
        let desk = PaperDesk(model: model, defaults: preferences)
        defer { desk.hide() }

        try FileManager.default.createDirectory(at: wiki.appendingPathComponent("sources"), withIntermediateDirectories: true)
        try "# New".write(to: wiki.appendingPathComponent("sources/new.md"), atomically: true, encoding: .utf8)
        model.files.openRunFile("sources/new.md", in: wiki.path)

        for _ in 0..<400 where model.files.selectedDocument != "sources/new.md" {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.library.vault.root, Vault(path: wiki.path).root)
        XCTAssertEqual(model.files.selectedDocument, "sources/new.md")
        XCTAssertTrue(desk.paper.marks.isOpenFile("sources/new.md"))
    }
}
