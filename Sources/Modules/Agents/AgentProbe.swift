import Foundation

/// The health of an agent, for Settings.
public struct AgentStatus: Equatable, Sendable {
    public enum Health: Equatable, Sendable {
        case checking
        case ready
        /// The agent runs, but needs an action, for example a sign-in.
        case warning
        case error
    }

    public var health: Health
    /// One line, for example "Signed in · claude.ai" or "Not found".
    public var headline: String
    public var version: String?

    public static let checking = AgentStatus(health: .checking, headline: "Checking…")

    public init(health: Health, headline: String, version: String? = nil) {
        self.health = health
        self.headline = headline
        self.version = version
    }
}

/// Checks that an agent starts. Each check stops after a time limit.
public enum AgentProbe {

    public static let timeLimit: TimeInterval = 10

    // MARK: - Claude Code

    /// Runs `claude --version` and `claude auth status`.
    public static func claudeCode(executable: URL?, usesLoginShell: Bool = true) async -> AgentStatus {
        guard let executable else {
            return AgentStatus(health: .error, headline: "Not found. Install Claude Code, or choose the claude command.")
        }
        guard let version = await run(executable.path, ["--version"], usesLoginShell: usesLoginShell),
              version.status == 0 else {
            return AgentStatus(health: .error, headline: "The claude command did not start.")
        }
        let number = version.output.split(whereSeparator: \.isWhitespace).first.map(String.init)
        guard let auth = await run(executable.path, ["auth", "status"], usesLoginShell: usesLoginShell),
              let json = jsonObject(auth.output) else {
            return AgentStatus(health: .ready, headline: "Installed", version: number)
        }
        guard json["loggedIn"] == .bool(true) else {
            return AgentStatus(health: .warning, headline: "Not signed in. Run claude auth login in Terminal.", version: number)
        }
        let method = json["authMethod"]?.string.map { " · " + $0 } ?? ""
        return AgentStatus(health: .ready, headline: "Signed in" + method, version: number)
    }

    // MARK: - ACP

    /// Starts the agent, sends `initialize`, and reads the answer.
    public static func acp(_ agent: AgentDefinition, usesLoginShell: Bool = true) async -> AgentStatus {
        let request = JSONRPCMessage.request(id: .number(Double(initializeID)), method: "initialize",
                                             params: StdioAgentConnection.initializeParams)
        guard let result = await run(agent.command, agent.arguments, input: request.line + "\n",
                                     usesLoginShell: usesLoginShell, until: { answersInitialize($0) }) else {
            return AgentStatus(health: .error, headline: "No answer to initialize in \(Int(timeLimit)) seconds.")
        }
        // The process ended, so the last line is complete even without a line break.
        switch initializeAnswer(in: result.output + "\n") {
        case .response(_, let value)?:
            let info = ACP.AgentInfo(json: value)
            let methods = value["authMethods"]?.array ?? []
            let hint = methods.first?["description"]?.string
            let name = info.name.map { "ACP · " + $0 } ?? "ACP"
            return AgentStatus(health: .ready, headline: hint.map { name + " · " + $0 } ?? name, version: info.version)
        case .error(_, _, let message)?:
            return AgentStatus(health: .error, headline: message)
        default:
            let detail = result.errors.split(separator: "\n").last.map(String.init)
            return AgentStatus(health: .error, headline: detail ?? "The command did not answer in ACP.")
        }
    }

    /// The JSON-RPC id of the `initialize` request of a check.
    static let initializeID = 1

    /// True when the output has a complete line with the answer to `initialize`.
    static func answersInitialize(_ output: String) -> Bool {
        initializeAnswer(in: output) != nil
    }

    /// The response or the error with the id of `initialize`, in the complete
    /// lines of the output. A line without its line break is not complete yet.
    static func initializeAnswer(in output: String) -> JSONRPCMessage? {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        for line in lines {
            let message = JSONRPCMessage.parse(String(line))
            switch message {
            case .response(let id, _)?, .error(let id, _, _)?:
                if id.int == initializeID { return message }
            default:
                continue
            }
        }
        return nil
    }

    // MARK: - Processes

    private struct Output: Sendable {
        let status: Int32
        let output: String
        let errors: String
    }

    /// Runs a command and collects its output. With `until`, the command ends
    /// when the output passes the test. Returns nil when it does not start or
    /// does not finish in time.
    private static func run(_ command: String, _ arguments: [String], input: String? = nil, usesLoginShell: Bool,
                            until done: (@Sendable (String) -> Bool)? = nil) async -> Output? {
        await withCheckedContinuation { continuation in
            let process = Process()
            AgentProcess.setCommand(of: process, to: command, arguments: arguments, usesLoginShell: usesLoginShell)
            process.currentDirectoryURL = FileManager.default.temporaryDirectory
            let stdin = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr
            let collector = Collector(continuation: continuation, process: process, done: done)
            stdout.fileHandleForReading.readabilityHandler = { collector.read($0, errors: false) }
            stderr.fileHandleForReading.readabilityHandler = { collector.read($0, errors: true) }
            process.terminationHandler = { collector.finish(status: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                return collector.fail()
            }
            if let input { try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8)) }
            if done == nil { try? stdin.fileHandleForWriting.close() }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeLimit) { collector.timeOut() }
        }
    }

    private static func jsonObject(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return JSONValue(object)
    }

    /// Collects output from two pipes, and resumes the caller once.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Output?, Never>?
        private let process: Process
        private let done: (@Sendable (String) -> Bool)?
        private var output = Data()
        private var errors = Data()

        init(continuation: CheckedContinuation<Output?, Never>, process: Process, done: (@Sendable (String) -> Bool)?) {
            self.continuation = continuation
            self.process = process
            self.done = done
        }

        func read(_ handle: FileHandle, errors isErrors: Bool) {
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            lock.lock()
            if isErrors { errors.append(data) } else { output.append(data) }
            let text = String(decoding: output, as: UTF8.self)
            lock.unlock()
            if !isErrors, let done, done(text) {
                resume(status: 0)
                process.terminate()
            }
        }

        func finish(status: Int32) {
            // The last bytes can arrive after the exit. A short wait lets them in.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { self.resume(status: status) }
        }

        func timeOut() {
            lock.lock()
            let waiting = continuation != nil
            lock.unlock()
            guard waiting else { return }
            process.terminate()
            fail()
        }

        func fail() {
            lock.lock()
            let continuation = continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: nil)
        }

        private func resume(status: Int32) {
            lock.lock()
            let continuation = continuation
            self.continuation = nil
            let result = Output(status: status, output: String(decoding: output, as: UTF8.self),
                                errors: String(decoding: errors, as: UTF8.self))
            lock.unlock()
            continuation?.resume(returning: result)
        }
    }
}
