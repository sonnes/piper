import Foundation
import Observation

/// One conversation with Claude Code in a folder.
///
/// A session keeps its transcript across turns and across launches of Piper.
/// Each session is its own observable object, so a pane that shows one session
/// redraws only when that session changes.
@MainActor @Observable
public final class AgentSession: Identifiable {

    public enum State: String, Codable, Sendable {
        /// The next turn waits for a free slot.
        case waiting
        case running
        /// A permission card or a question card waits for the reader.
        case needsYou
        /// The last turn ended. The reader can send another message.
        case idle
        /// The last turn failed. The reader can send another message.
        case failed
    }

    /// The stored form of a session.
    public struct Snapshot: Codable, Equatable, Sendable {
        public var id: UUID
        public var folder: String
        public var noteID: UUID?
        public var command: SlashCommand?
        public var claudeSessionID: String?
        public var state: State
        public var createdAt: Date
        public var updatedAt: Date
        public var unread: Bool
        public var blocks: [TranscriptBlock]
    }

    // MARK: - Properties

    public let id: UUID
    /// The folder the session works in, as an absolute path.
    public let folder: String
    /// The note that started the session.
    public let noteID: UUID?
    /// The skill of the first turn, for a session that a Send action started.
    public let command: SlashCommand?
    /// The id that `--resume` takes.
    public internal(set) var claudeSessionID: String?
    public internal(set) var state: State
    public let createdAt: Date
    public internal(set) var updatedAt: Date
    /// True when a turn ended after the reader last looked at the session.
    public internal(set) var unread = false
    public internal(set) var blocks: [TranscriptBlock] = []

    private static let titleLimit = 60
    private static let snippetLimit = 160

    public var folderName: String { URL(fileURLWithPath: folder).lastPathComponent }
    public var isActive: Bool { state == .waiting || state == .running || state == .needsYou }

    /// The first message of the reader, in one line.
    public var title: String {
        let text = userTexts.first ?? command?.prompt ?? "New session"
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > Self.titleLimit ? String(line.prefix(Self.titleLimit - 1)) + "…" : line
    }

    /// The last message of Claude, or the last step while a turn runs.
    public var snippet: String {
        for block in blocks.reversed() {
            switch block {
            case .assistant(_, let text): return String(text.prefix(Self.snippetLimit))
            case .toolCall(let call) where isActive: return call.line
            case .result(_, let result) where result.failure != nil: return result.failure ?? ""
            default: continue
            }
        }
        return ""
    }

    /// The last message that the reader sent.
    public var lastPrompt: String? { userTexts.last }

    /// The files that the session wrote, relative to the folder, oldest first.
    public var files: [String] {
        var files: [String] = []
        for case .toolCall(let call) in blocks {
            if let path = call.path, !call.isError, !files.contains(path) { files.append(path) }
        }
        return files
    }

    /// The file to open for a finished session: the first Markdown file that it
    /// wrote, other than an index or a log.
    public var primaryFile: String? {
        files.first { $0.lowercased().hasSuffix(".md") && !$0.hasSuffix("index.md") && $0 != "log.md" }
            ?? files.first { $0.lowercased().hasSuffix(".md") }
    }

    public var totalCost: Double { results.reduce(0) { $0 + $1.costUSD } }
    public var totalDuration: TimeInterval { Double(results.reduce(0) { $0 + $1.durationMs }) / 1000 }

    /// The permission request or question that waits for the reader.
    public var pendingRequest: PermissionRequest? {
        for block in blocks {
            switch block {
            case .permission(let request, decision: .pending), .question(let request, answers: nil): return request
            default: continue
            }
        }
        return nil
    }

    /// The last tool call, as one line.
    public var lastStep: String? {
        for case .toolCall(let call) in blocks.reversed() { return call.line }
        return nil
    }

    /// Why the last turn failed, when it failed.
    public var failure: String? {
        state == .failed ? results.last?.failure : nil
    }

    public var snapshot: Snapshot {
        Snapshot(id: id, folder: folder, noteID: noteID, command: command, claudeSessionID: claudeSessionID,
                 state: state, createdAt: createdAt, updatedAt: updatedAt, unread: unread, blocks: blocks)
    }

    private var userTexts: [String] {
        blocks.compactMap { if case .user(_, let text, _) = $0 { return text } else { return nil } }
    }

    private var results: [TurnResult] {
        blocks.compactMap { if case .result(_, let result) = $0 { return result } else { return nil } }
    }

    // MARK: - Initialization

    public init(id: UUID = UUID(), folder: String, noteID: UUID? = nil, command: SlashCommand? = nil,
                state: State = .idle, createdAt: Date = Date()) {
        self.id = id
        self.folder = folder
        self.noteID = noteID
        self.command = command
        self.state = state
        self.createdAt = createdAt
        updatedAt = createdAt
    }

    public convenience init(_ snapshot: Snapshot) {
        self.init(id: snapshot.id, folder: snapshot.folder, noteID: snapshot.noteID, command: snapshot.command,
                  state: snapshot.state, createdAt: snapshot.createdAt)
        claudeSessionID = snapshot.claudeSessionID
        updatedAt = snapshot.updatedAt
        unread = snapshot.unread
        blocks = snapshot.blocks
    }

    // MARK: - Changing

    func append(_ block: TranscriptBlock) {
        blocks.append(block)
        updatedAt = Date()
    }

    /// Changes the block with an id. Returns false when no block has the id.
    @discardableResult
    func update(_ id: String, _ change: (inout TranscriptBlock) -> Void) -> Bool {
        guard let index = blocks.lastIndex(where: { $0.id == id }) else { return false }
        change(&blocks[index])
        updatedAt = Date()
        return true
    }
}
