import Agents
import AppKit
import SwiftUI

/// The middle pane while the sidebar selects a Claude folder: its sessions,
/// the most recently changed first.
struct SessionListView: View {
    @Bindable var model: AppModel
    let folder: String

    private var runner: SessionRunner { model.agents.runner }

    var body: some View {
        let sessions = runner.sessions(in: folder)
        VStack(spacing: 0) {
            HStack {
                Text(sessions.count == 1 ? "1 session" : "\(sessions.count) sessions")
                    .font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary)
                Spacer()
                IconButton(title: "New Session", icon: "square.and.pencil") { model.selectedSession = nil }
            }
            .padding(.horizontal, AppDefaults.ListSearch.horizontalInset)
            .padding(.vertical, AppDefaults.ListSearch.verticalInset)
            List(selection: $model.selectedSession) {
                ForEach(sessions) { session in
                    SessionRow(session: session)
                        .tag(session.id as UUID?)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .contextMenu {
                            Button("Delete Session") {
                                if model.selectedSession == session.id { model.selectedSession = nil }
                                runner.delete(session)
                            }
                        }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .overlay {
                if sessions.isEmpty {
                    EmptyPane(title: "No Sessions", detail: "Sessions that you start in this folder appear here.")
                }
            }
            .accessibilityLabel("Sessions")
        }
        .background(PiperTheme.page)
    }
}

/// One session in the list: the unread dot, the title, the last message, and the state.
private struct SessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Circle()
                .fill(session.unread ? PiperTheme.accent : .clear)
                .frame(width: AppDefaults.Timeline.unreadCircleDimension, height: AppDefaults.Timeline.unreadCircleDimension)
                .frame(width: AppDefaults.Timeline.gutterWidth)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.title).font(PiperTheme.ui(13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(RowTime.text(session.updatedAt))
                        .font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.faint).monospacedDigit()
                }
                Text(session.snippet)
                    .font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary)
                    .lineLimit(2)
                SessionStateChip(session: session)
            }
            .padding(.trailing, 10)
        }
        .padding(.vertical, AppDefaults.Timeline.verticalPadding)
        .accessibilityElement(children: .combine)
        .accessibilityValue(session.unread ? "Unread" : "Read")
    }
}
