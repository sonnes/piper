import Foundation

/// One `claude` child process with open pipes.
///
/// Standard output arrives line by line on the main actor. Standard input
/// stays open, so the caller can send more lines while the process runs.
@MainActor
public final class ClaudeProcess {

    // MARK: - Properties

    public let arguments: [String]
    private let process = Process()
    private let input = Pipe()
    private var isInputOpen = true

    /// A write to a pipe after the child exits raises SIGPIPE. Piper ignores
    /// the signal, and the write fails with an error instead.
    private static let ignoresBrokenPipes: Void = { signal(SIGPIPE, SIG_IGN) }()

    // MARK: - Initialization

    /// Makes a process that runs in `folder`. With `usesLoginShell`, the process
    /// starts through `zsh -l`, so the child gets the reader's PATH.
    public init(executable: URL, arguments: [String], folder: URL, usesLoginShell: Bool) {
        self.arguments = arguments
        if usesLoginShell {
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", "exec \"$0\" \"$@\"", executable.path] + arguments
        } else {
            process.executableURL = executable
            process.arguments = arguments
        }
        process.currentDirectoryURL = folder
    }

    // MARK: - Running

    /// Starts the process. `line` gets each line of standard output. `exit`
    /// gets the exit status and the start of standard error, after the last line.
    ///
    /// Both pipes use a readability handler. A blocking read holds a thread
    /// while an idle process waits for input, and a few idle sessions would
    /// hold every thread of the pool.
    public func start(line: @escaping @MainActor (String) -> Void,
                      exit: @escaping @MainActor (Int32, String) -> Void) throws {
        _ = Self.ignoresBrokenPipes
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        let status = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = { process in
            status.continuation.yield(process.terminationStatus)
            status.continuation.finish()
        }
        let lines = PipeReader.lines(of: output.fileHandleForReading)
        let errorText = PipeReader.lines(of: errors.fileHandleForReading)
        try process.run()
        Task { @MainActor in
            for await text in lines { line(text) }
            var code: Int32 = 0
            for await value in status.stream { code = value }
            var stderr = ""
            for await text in errorText where stderr.utf8.count < 4000 { stderr += text + "\n" }
            exit(code, String(stderr.prefix(4000)))
        }
    }

    /// Sends one line on standard input. A write after the input closed, or
    /// after the process exited, does nothing.
    public func write(_ line: String) {
        guard isInputOpen else { return }
        try? input.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8))
    }

    /// Closes standard input. Claude Code then ends after the current turn.
    public func closeInput() {
        guard isInputOpen else { return }
        isInputOpen = false
        try? input.fileHandleForWriting.close()
    }

    public func terminate() {
        if process.isRunning { process.terminate() }
    }
}

/// Reads a pipe without a blocking read, and splits it into lines.
private final class PipeReader: @unchecked Sendable {
    private var buffer = Data()
    private let continuation: AsyncStream<String>.Continuation

    private init(_ continuation: AsyncStream<String>.Continuation) {
        self.continuation = continuation
    }

    /// The lines of a pipe. The stream ends at the end of the file.
    static func lines(of handle: FileHandle) -> AsyncStream<String> {
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        let reader = PipeReader(continuation)
        // The handler runs on one serial queue per handle, so the buffer needs no lock.
        handle.readabilityHandler = { handle in reader.read(handle) }
        return stream
    }

    private func read(_ handle: FileHandle) {
        let data = handle.availableData
        guard !data.isEmpty else {
            handle.readabilityHandler = nil
            if !buffer.isEmpty { continuation.yield(String(decoding: buffer, as: UTF8.self)) }
            buffer.removeAll()
            continuation.finish()
            return
        }
        buffer.append(data)
        while let end = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            continuation.yield(String(decoding: buffer[buffer.startIndex..<end], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...end)
        }
    }
}
