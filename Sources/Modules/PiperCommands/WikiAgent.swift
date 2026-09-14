import Foundation
import Observation

/// Runs a Wiki command or a Wiki skill through the Claude Code CLI.
///
/// The commands and the skills already exist as prompts. Piper starts
/// `claude --print` in the Wiki folder and shows the output. It does not
/// reimplement what a command does.
@MainActor @Observable
public final class WikiAgent {
    /// Tools the bundled commands need: Markdown edits, the OKF scripts, and
    /// the page fetch that `/capture` performs. Every other tool still asks,
    /// and a headless run cannot answer, so it stops instead of acting alone.
    public static let tools = ["Read", "Write", "Edit", "Glob", "Grep", "WebFetch", "Bash(python3:*)"]

    public private(set) var running: WikiAgentJob?
    public private(set) var transcript = ""
    private var process: Process?

    public var isRunning: Bool { running != nil }

    // MARK: - Life Cycle

    public init() {}

    // MARK: - Functions

    /// A Finder-launched application inherits a minimal PATH, so look in the
    /// places the Claude Code installers use.
    public static func executable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/claude"),
            home.appendingPathComponent(".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Runs `job` and streams the output into `transcript`.
    ///
    /// - Returns: A message for the reader when the run fails, or `nil` when it succeeds.
    public func run(_ job: WikiAgentJob, arguments: String, root: URL) async -> String? {
        guard !isRunning else { return nil }
        guard let executable = Self.executable() else {
            return "Piper cannot find the claude command. Install Claude Code, then reopen Piper."
        }
        // A personal command lives in the home folder, so only the Wiki scope
        // needs a directory inside this folder.
        if job.scope == .wiki {
            let directory = root.appendingPathComponent(job.directoryPath)
            guard FileManager.default.fileExists(atPath: directory.path) else {
                return "This Wiki folder has no \(job.directoryPath) directory."
            }
        }
        let prompt = job.prompt(arguments: arguments)

        let task = Process()
        task.executableURL = executable
        task.currentDirectoryURL = root
        task.arguments = ["--print", prompt, "--permission-mode", "acceptEdits", "--allowedTools"] + Self.tools
        var environment = ProcessInfo.processInfo.environment
        let binary = executable.deletingLastPathComponent().path
        environment["PATH"] = environment["PATH"].map { $0 + ":" + binary } ?? binary
        task.environment = environment

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.transcript += text }
        }

        running = job
        transcript = "$ claude --print \"\(prompt)\"\n\n"
        process = task
        defer { running = nil; process = nil }

        do { try task.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return error.localizedDescription
        }
        await Task.detached { task.waitUntilExit() }.value
        pipe.fileHandleForReading.readabilityHandler = nil
        if let rest = try? pipe.fileHandleForReading.readToEnd(), let text = String(data: rest, encoding: .utf8) {
            transcript += text
        }
        if task.terminationReason == .uncaughtSignal { return "The command stopped." }
        guard task.terminationStatus == 0 else { return "claude exited with status \(task.terminationStatus)." }
        return nil
    }

    public func cancel() {
        process?.terminate()
    }
}
