import Agents
import SwiftUI

/// The sessions of one folder, the newest change first, under a New Session row.
struct SessionList: View {
    @Bindable var model: AppModel
    let folder: String
    /// Sets the keys of the list on the feed paper.
    var setKeys: ([PaperKey]) -> Void = { _ in }

    @State private var selected: PaperItem?
    @Environment(\.paperDesk) private var desk

    var body: some View {
        let sessions = model.agents.runner.sessions(in: folder)
        let items = [PaperItem.newSession(folder)] + sessions.map { .session($0.id) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PaperRow(item: .newSession(folder), selected: current == .newSession(folder), time: "",
                         action: { pick(.newSession(folder)) }) {
                    Image(systemName: "square.and.pencil").font(.system(size: 15, weight: .medium)).foregroundStyle(PiperTheme.brand)
                } content: {
                    PaperRowTitle(text: Text("New Session"))
                }
                if !sessions.isEmpty { PaperGroupHeader(title: "Sessions") }
                ForEach(sessions) { session in
                    PaperRow(item: .session(session.id), selected: current == .session(session.id),
                             time: RowTime.text(session.updatedAt), action: { pick(.session(session.id)) }) {
                        Circle().fill(Color(nsColor: Self.color(session)))
                            .frame(width: PaperRowMetrics.dotSize, height: PaperRowMetrics.dotSize)
                    } content: {
                        VStack(alignment: .leading, spacing: 0) {
                            PaperRowTitle(text: Text(session.title), bold: session.unread)
                            PaperRowMeta { Text(SessionStateChip.title(session.state)) }
                        }
                    }
                    .contextMenu {
                        Button("Delete Session") {
                            if model.selectedSession == session.id { model.selectedSession = nil }
                            model.agents.runner.delete(session)
                        }
                    }
                }
            }
            .padding(PaperRowMetrics.listPadding)
        }
        .onAppear { setKeys(keys(items)) }
        .onChange(of: items) { _, items in setKeys(keys(items)) }
        .onChange(of: selected) { _, _ in setKeys(keys(items)) }
    }

    private var current: PaperItem? {
        selected ?? model.selectedSession.map(PaperItem.session)
    }

    private func pick(_ item: PaperItem) {
        selected = item
        desk?.open(item)
    }

    private func keys(_ items: [PaperItem]) -> [PaperKey] {
        let current = current
        return [
            PaperKey(key: .up, title: "move") { if let item = items.step(from: current, by: -1) { selected = item } },
            PaperKey(key: .down, title: "move") { if let item = items.step(from: current, by: 1) { selected = item } },
            PaperKey(key: .enter, title: "open as a paper", isOn: { current.map(items.contains) == true }) {
                if let current { desk?.open(current) }
            }
        ]
    }

    private static func color(_ session: AgentSession) -> NSColor {
        switch session.state {
        case .needsYou: return PiperTheme.claudeNS
        case .running, .waiting: return PiperTheme.successNS
        case .idle, .failed: return session.unread ? PiperTheme.brandNS : PiperTheme.paperBarNS
        }
    }
}
