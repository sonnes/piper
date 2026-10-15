import Agents
import AppKit
import SwiftUI

/// An agent session: the transcript, the files it wrote, the request that
/// waits, and the composer.
///
/// The session pane, the Sessions list, and the detail of a note show this
/// view. Without a session, the first message starts one in the folder.
struct SessionPane: View {
    @Bindable var model: AppModel
    let session: AgentSession?
    /// The folder that a new session works in.
    let folder: String
    /// The note that a new session belongs to.
    var noteID: UUID?
    /// The files that the next message names as context, as absolute paths.
    var context: [String] = []
    /// Called when the reader removes the context, and after a message took it.
    var contextUsed: () -> Void = {}
    /// Called with the session that the first message started.
    var started: (AgentSession) -> Void = { _ in }

    /// The agent, model, and mode of the first message, before the session exists.
    @State private var choice: SessionChoice?

    private var runner: SessionRunner { model.agents.runner }

    /// The name of the agent of a new session. Nil for an agent that the reader removed.
    private var agentName: String? {
        model.agents.agent(choice?.agentID ?? model.agents.sessionAgentID)?.name
    }

    var body: some View {
        VStack(spacing: 0) {
            if let session {
                SessionTranscript(model: model, session: session)
                SessionFooter(model: model, session: session)
            } else {
                EmptyPane(title: "New Session",
                          detail: "\(agentName ?? "The agent") works in \(URL(fileURLWithPath: folder).lastPathComponent). It can read and change the files there.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .frame(maxHeight: .infinity)
            }
            if let session { ApprovalDrawer(session: session, runner: runner) }
            SessionComposer(model: model, session: session, folder: folder, context: context,
                            removeContext: contextUsed, send: send,
                            stop: { if let session { runner.stop(session) } }, choice: $choice)
        }
        .background(PiperTheme.page)
    }

    private func send(_ text: String, choice: SessionChoice) {
        let target = session ?? model.agents.newSession(in: folder, noteID: noteID, agentID: choice.agentID, model: choice.model,
                                                         mode: choice.mode)
        runner.send(text, context: context, to: target)
        if !context.isEmpty { contextUsed() }
        if session == nil { started(target) }
    }
}

/// The blocks of a session, scrolled to the newest. The tool calls of a
/// finished turn fold into one line.
private struct SessionTranscript: View {
    let model: AppModel
    let session: AgentSession
    /// The folds that the reader opened.
    @State private var opened: Set<String> = []

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppDefaults.Sessions.blockSpacing) {
                    ForEach(TranscriptRow.rows(of: session.blocks)) { row in
                        switch row {
                        case .block(let block):
                            TranscriptBlockView(model: model, session: session, block: block).id(block.id)
                        case .fold(let id, let summary, let blocks):
                            TurnFold(summary: summary, isOpen: Binding(
                                get: { opened.contains(id) },
                                set: { if $0 { opened.insert(id) } else { opened.remove(id) } }
                            )) {
                                ForEach(blocks) { block in TranscriptBlockView(model: model, session: session, block: block) }
                            }
                            .id(id)
                        }
                    }
                    if session.state == .running || session.state == .waiting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(session.state == .waiting ? "Waiting for another session" : "Working")
                        }
                        .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.faint)
                    }
                    Color.clear.frame(height: 1).id(Self.end)
                }
                .padding(AppDefaults.Sessions.transcriptInset)
            }
            .defaultScrollAnchor(.bottom)
            .onAppear { model.agents.runner.markRead(session) }
            .onChange(of: session.blocks.count) { _, _ in
                proxy.scrollTo(Self.end, anchor: .bottom)
                model.agents.runner.markRead(session)
            }
            .onChange(of: session.id) { _, _ in proxy.scrollTo(Self.end, anchor: .bottom) }
        }
        .accessibilityLabel("Transcript")
    }

    private static let end = "transcript-end"
}

/// The files that the session wrote, and what the session cost.
private struct SessionFooter: View {
    let model: AppModel
    let session: AgentSession

    var body: some View {
        let files = session.files
        if !files.isEmpty || session.totalCost > 0 {
            HStack(spacing: 6) {
                if !files.isEmpty {
                    Menu {
                        ForEach(files, id: \.self) { file in
                            Button(file) { model.openRunFile(file, in: session.folder) }
                        }
                    } label: {
                        Label(files.count == 1 ? files[0] : "\(files.count) files changed", systemImage: "doc.on.doc")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Open a file that the session changed")
                }
                Spacer(minLength: 4)
                if session.totalCost > 0 {
                    Text(String(format: "$%.2f", session.totalCost)).monospacedDigit()
                        .help("The cost of the session so far, from the agent")
                }
            }
            .font(PiperTheme.ui(11))
            .foregroundStyle(PiperTheme.secondary)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .overlay(alignment: .top) { Rule() }
        }
    }
}

/// The header over a session: its title and its state.
struct SessionHeader: View {
    let session: AgentSession?

    var body: some View {
        HStack(spacing: 8) {
            Text(session?.title ?? "New Session")
                .font(PiperTheme.ui(13, weight: .semibold))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            if let session { SessionStateChip(session: session) }
        }
    }
}

/// One row of a transcript: a block, or the folded tool calls of a finished turn.
enum TranscriptRow: Identifiable {
    case block(TranscriptBlock)
    case fold(id: String, summary: String, blocks: [TranscriptBlock])

    var id: String {
        switch self {
        case .block(let block): return block.id
        case .fold(let id, _, _): return id
        }
    }

    /// The rows of a transcript. A turn that has a result folds its tool calls
    /// and its answered requests into one row, where its first tool call was.
    /// A turn that runs shows every block.
    static func rows(of blocks: [TranscriptBlock]) -> [TranscriptRow] {
        var rows: [TranscriptRow] = []
        var turn: [TranscriptBlock] = []
        func flush() {
            rows += fold(turn)
            turn.removeAll()
        }
        for block in blocks {
            if case .user = block { flush() }
            turn.append(block)
        }
        flush()
        return rows
    }

    private static func fold(_ turn: [TranscriptBlock]) -> [TranscriptRow] {
        guard let result = turn.lazy.compactMap({ block -> TurnResult? in
            if case .result(_, let result) = block { return result } else { return nil }
        }).first else { return turn.map(TranscriptRow.block) }
        let calls = turn.compactMap { block -> ToolCall? in
            if case .toolCall(let call) = block { return call } else { return nil }
        }
        guard let first = calls.first else { return turn.map(TranscriptRow.block) }
        let work = turn.filter(isWork)
        var summary = "Worked"
        if result.durationMs > 0 {
            summary += " for " + Duration.milliseconds(result.durationMs)
                .formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated, fractionalPart: .hide))
        }
        summary += " · " + ToolCall.summary(of: calls)
        var rows: [TranscriptRow] = []
        for block in turn where !isWork(block) || block.id == first.id {
            rows.append(block.id == first.id ? .fold(id: "fold-" + first.id, summary: summary, blocks: work) : .block(block))
        }
        return rows
    }

    private static func isWork(_ block: TranscriptBlock) -> Bool {
        switch block {
        case .toolCall, .permission, .question: return true
        default: return false
        }
    }
}

/// The folded tool calls of a finished turn. A click opens them.
private struct TurnFold<Content: View>: View {
    let summary: String
    @Binding var isOpen: Bool
    @ViewBuilder let content: Content

    private typealias Metrics = AppDefaults.Sessions

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.blockSpacing) {
            Button { isOpen.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: 12)
                    Text(summary).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .font(PiperTheme.ui(12))
                .foregroundStyle(PiperTheme.secondary)
                .padding(Metrics.chipPadding)
                .background(PiperTheme.hover, in: RoundedRectangle(cornerRadius: Metrics.chipRadius))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(summary)
            .accessibilityHint(isOpen ? "Hides the tool calls" : "Shows the tool calls")
            if isOpen {
                VStack(alignment: .leading, spacing: 6) { content }
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) { Rectangle().fill(PiperTheme.rule).frame(width: 1).padding(.leading, 6) }
            }
        }
    }
}
