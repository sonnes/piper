import Agents
import AppKit
import SwiftUI

/// A Claude session: the transcript, the files it wrote, and the composer.
///
/// The Claude pane, the Claude list, and the detail of a note show this view.
/// Without a session, the first message starts one in the folder.
struct SessionPane: View {
    @Bindable var model: AppModel
    let session: AgentSession?
    /// The folder that a new session works in.
    let folder: String
    /// The files that the next message names as context, as absolute paths.
    var context: [String] = []
    /// Called when the reader removes the context, and after a message took it.
    var contextUsed: () -> Void = {}
    /// Called with the session that the first message started.
    var started: (AgentSession) -> Void = { _ in }

    private var runner: SessionRunner { model.agents.runner }

    var body: some View {
        VStack(spacing: 0) {
            if let session {
                SessionTranscript(model: model, session: session)
                SessionFooter(model: model, session: session)
            } else {
                EmptyPane(title: "New Session",
                          detail: "Claude Code works in \(URL(fileURLWithPath: folder).lastPathComponent). It can read and change the files there.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .frame(maxHeight: .infinity)
            }
            SessionComposer(model: model, session: session, folder: folder, context: context,
                            removeContext: contextUsed, send: send,
                            stop: { if let session { runner.stop(session) } })
        }
        .background(PiperTheme.page)
    }

    private func send(_ text: String) {
        let target = session ?? runner.newSession(in: folder)
        runner.send(text, context: context, to: target)
        if !context.isEmpty { contextUsed() }
        if session == nil { started(target) }
    }
}

/// The blocks of a session, scrolled to the newest.
private struct SessionTranscript: View {
    let model: AppModel
    let session: AgentSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(session.blocks) { block in
                        TranscriptBlockView(model: model, session: session, block: block).id(block.id)
                    }
                    if session.state == .running || session.state == .waiting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(session.state == .waiting ? "Waiting for another session" : session.lastStep ?? "Working")
                                .lineLimit(1).truncationMode(.middle)
                        }
                        .font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary)
                    }
                    Color.clear.frame(height: 1).id(Self.end)
                }
                .padding(14)
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
                        .help("The cost of the session so far, from Claude Code")
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
