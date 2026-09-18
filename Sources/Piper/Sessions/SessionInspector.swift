import Agents
import AppKit
import SwiftUI

/// The Claude pane on the right of the main window.
///
/// The pane works in the folder of the page on the screen. The page is the
/// context of the next message until the reader removes it or sends one.
struct SessionInspector: View {
    @Bindable var model: AppModel
    /// The page that the reader removed from the context, or that a message took.
    @State private var usedContext: String?

    private var runner: SessionRunner { model.agents.runner }

    private var page: String? {
        if case .page(let path) = model.actionTarget { return path }
        return nil
    }

    /// The folder of the page, or the default folder for Claude.
    private var folder: String {
        page == nil ? model.agents.defaultFolder?.path ?? model.vault.root.path : model.vault.root.path
    }

    private var session: AgentSession? {
        guard let id = model.selectedSession, let session = runner.session(id), session.folder == folder else { return nil }
        return session
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                sessionMenu
                Spacer(minLength: 4)
                if let session { SessionStateChip(session: session) }
                IconButton(title: "New Session", icon: "square.and.pencil") { model.selectedSession = nil }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            Rule()
            SessionPane(model: model, session: session, folder: folder,
                        context: page.map { $0 == usedContext ? [] : [$0] } ?? [],
                        contextUsed: { usedContext = page },
                        started: { model.selectedSession = $0.id })
        }
        .background(PiperTheme.page)
        .onChange(of: page) { _, _ in usedContext = nil }
    }

    private var sessionMenu: some View {
        Menu {
            Button("New Session") { model.selectedSession = nil }
            let sessions = runner.sessions(in: folder)
            if !sessions.isEmpty { Divider() }
            ForEach(sessions.prefix(20)) { item in
                Button {
                    model.selectedSession = item.id
                } label: {
                    Text(item.title)
                    Text(SessionStateChip.title(item.state) + " · " + RowTime.text(item.updatedAt))
                }
            }
        } label: {
            Text(session?.title ?? "New Session in \(URL(fileURLWithPath: folder).lastPathComponent)")
                .font(PiperTheme.ui(13, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
        .help("Choose a session of this folder")
    }
}
