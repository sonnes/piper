import AppKit
import Agents
import Captures
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
        let agents = FolderAgents(store: store, preferences: preferences)
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

        let restored = FolderAgents(store: store, preferences: preferences)
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

    func testSendRunsTheDefaultSkillAndRemembersTheFolder() async throws {
        let agents = try makeAgents()
        XCTAssertTrue(store.add("https://example.com/page"))
        let note = try XCTUnwrap(store.notes.last)
        let notesAction = try XCTUnwrap(agents.completions(for: "capture").last)

        let session = try XCTUnwrap(agents.send(note, action: notesAction))
        XCTAssertEqual(session.folder, notes.standardizedFileURL.path)
        XCTAssertEqual(session.command, SlashCommand(name: "capture", arguments: "https://example.com/page"))
        XCTAssertEqual(agents.defaultFolder?.name, "notes")
        XCTAssertEqual(store.status, "Running /capture in notes")
        try await waitForRuns(agents)

        XCTAssertEqual(agents.latestSession(for: note)?.state, .idle)
        XCTAssertEqual(try prompts(), ["/capture https://example.com/page"])
        XCTAssertEqual(FolderAgents(store: store, preferences: preferences).lastFolderPath, notes.standardizedFileURL.path)
    }

    func testSendSelectionSendsEachNoteWithItsOwnSkill() async throws {
        let agents = try makeAgents()
        XCTAssertTrue(store.add("https://example.com/a"))
        XCTAssertTrue(store.add("Decision keep runs"))
        store.selection = Set(store.notes.map(\.id))

        XCTAssertEqual(agents.sendSelection(), 2)
        try await waitForRuns(agents)
        XCTAssertEqual(try prompts().sorted(), ["/capture https://example.com/a", "/new Decision keep runs"])
    }

    func testSendingAClipboardTextSavesItFirst() async throws {
        let agents = try makeAgents()
        let clipboard = ClipboardInbox(store: store, pasteboard: NSPasteboard(name: .init("com.piper.test." + UUID().uuidString)))
        clipboard.receive(["https://example.com/copied"])
        let entry = try XCTUnwrap(clipboard.entries.first)

        let session = try XCTUnwrap(agents.send(entry, from: clipboard))
        XCTAssertEqual(store.notes.map(\.text), ["https://example.com/copied"])
        XCTAssertEqual(store.notes.first?.section, "Inbox")
        XCTAssertEqual(session.noteID, store.notes.first?.id)
        XCTAssertTrue(clipboard.entries.isEmpty)
        try await waitForRuns(agents)
    }

    func testSendingThePasteboardSkipsANoteThatWasSent() async throws {
        let agents = try makeAgents()
        let pasteboard = NSPasteboard(name: .init("com.piper.test." + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("https://example.com/twice", forType: .string)

        XCTAssertNotNil(agents.sendPasteboard(pasteboard))
        try await waitForRuns(agents)
        XCTAssertNil(agents.sendPasteboard(pasteboard))
        XCTAssertEqual(store.status, "Already sent to wiki")
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(try prompts().count, 1)

        pasteboard.clearContents()
        XCTAssertNil(agents.sendPasteboard(pasteboard))
        XCTAssertEqual(store.status, "The clipboard has no text")
    }

    func testComposerCommandSavesItsArgumentsAsANote() async throws {
        let agents = try makeAgents()
        XCTAssertTrue(store.chooseSection("Research"))

        XCTAssertNotNil(agents.run(SlashCommand("/capture https://example.com/x")!))
        XCTAssertNotNil(agents.run(SlashCommand("/stale")!))
        let tidy = try XCTUnwrap(agents.completions(for: "tidy").first)
        XCTAssertNotNil(agents.run(SlashCommand(name: "tidy"), action: tidy))
        // A chosen action for another skill is ignored, and the folder used last wins.
        XCTAssertEqual(agents.run(SlashCommand(name: "capture"), action: tidy)?.folder, notes.standardizedFileURL.path)
        XCTAssertNil(agents.run(SlashCommand("/missing text")!))

        XCTAssertEqual(store.notes.map(\.text), ["https://example.com/x", "/stale", "/tidy", "/capture"])
        XCTAssertTrue(store.notes.allSatisfy { $0.section == "Research" })
        XCTAssertEqual(agents.latestSession(for: store.notes[2])?.folder, notes.standardizedFileURL.path)
        try await waitForRuns(agents)
        XCTAssertEqual(try prompts().sorted(), ["/capture", "/capture https://example.com/x", "/stale", "/tidy"])
    }

    // MARK: - Executable

    func testSessionsDefaultToSonnetInAutoModeAndKeepTheChoice() {
        let agents = FolderAgents(store: store, preferences: preferences)
        XCTAssertEqual(agents.model, "sonnet")
        XCTAssertEqual(agents.runner.model, "sonnet")
        XCTAssertEqual(agents.runner.permissionMode, .auto)

        agents.permissionMode = .ask
        XCTAssertEqual(FolderAgents(store: store, preferences: preferences).runner.permissionMode, .ask)
        XCTAssertEqual(preferences.string(forKey: AppDefaults.Key.claudePermissionMode), "manual")

        agents.model = "opus"
        XCTAssertEqual(agents.runner.model, "opus")
        XCTAssertEqual(FolderAgents(store: store, preferences: preferences).runner.model, "opus")

        agents.model = ""
        XCTAssertEqual(FolderAgents(store: store, preferences: preferences).model, "")
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
        var shown: [String] = []
        model.showFile = { shown.append($0) }

        try FileManager.default.createDirectory(at: wiki.appendingPathComponent("sources"), withIntermediateDirectories: true)
        try "# New".write(to: wiki.appendingPathComponent("sources/new.md"), atomically: true, encoding: .utf8)
        model.openRunFile("sources/new.md", in: wiki.path)

        for _ in 0..<400 where model.selectedDocument != "sources/new.md" {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.vault.root, wiki.standardizedFileURL)
        XCTAssertEqual(model.selectedDocument, "sources/new.md")
        XCTAssertEqual(shown, ["sources/new.md"])
    }
}
