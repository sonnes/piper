import Agents
import SwiftUI

/// The sessions of one folder, the newest change first, under a New Session row.
struct SessionList: View {
    @Bindable var model: AppModel
    let folder: String
    let open: (PaperItem) -> Void
    /// Sets the keys of the list on the feed paper.
    var setKeys: (FeedPaperModel.ListKeys?) -> Void = { _ in }

    @State private var selected: PaperItem?

    var body: some View {
        let sessions = model.agents.runner.sessions(in: folder)
        let items = [PaperItem.newSession(folder)] + sessions.map { .session($0.id) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PaperRow(item: .newSession(folder), selected: current == .newSession(folder), time: "",
                         action: { pick(.newSession(folder)) }) {
                    Text("+").font(PiperTheme.paperUI(.reading)).foregroundStyle(PiperTheme.brand)
                } content: {
                    PaperRowTitle(text: Text("New Session"))
                }
                if !sessions.isEmpty { PaperGroupHeader(title: "Sessions") }
                ForEach(sessions) { session in
                    PaperRow(item: .session(session.id), selected: current == .session(session.id),
                             time: RowTime.text(session.updatedAt), action: { pick(.session(session.id)) }) {
                        Circle().fill(Color(nsColor: Self.color(session)))
                            .frame(width: AppDefaults.Papers.dotSize, height: AppDefaults.Papers.dotSize)
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
            .padding(AppDefaults.Papers.listPadding)
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
        open(item)
    }

    private func keys(_ items: [PaperItem]) -> FeedPaperModel.ListKeys {
        let current = current
        return FeedPaperModel.ListKeys(
            move: { delta in
                let index = current.flatMap { items.firstIndex(of: $0) }
                let next = max(0, min(items.count - 1, (index ?? (delta > 0 ? -1 : items.count)) + delta))
                if items.indices.contains(next) { selected = items[next] }
            },
            open: {
                if let current, items.contains(current) { open(current) }
            })
    }

    private static func color(_ session: AgentSession) -> NSColor {
        switch session.state {
        case .needsYou: return PiperTheme.claudeNS
        case .running, .waiting: return PiperTheme.successNS
        case .idle, .failed: return session.unread ? PiperTheme.brandNS : PiperTheme.paperBarNS
        }
    }
}
