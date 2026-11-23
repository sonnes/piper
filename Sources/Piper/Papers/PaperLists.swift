import Agents
import SwiftUI
import Vault

/// The files of one folder and of the folders under it, grouped by folder.
/// A click on a file opens it as a file paper.
struct FolderListView: View {
    @Bindable var model: AppModel
    /// The path of the folder from the root of the active folder. The empty path is the root.
    let folder: String
    let open: (String) -> Void

    var body: some View {
        let groups = Self.groups(model.files, in: folder)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(groups, id: \.folder) { group in
                    IndexHeader(title: group.folder.isEmpty ? model.vault.root.lastPathComponent
                                : group.folder.replacingOccurrences(of: "/", with: " › "))
                    ForEach(group.files) { file in
                        PaperListRow(title: file.title, detail: file.name, time: RowTime.text(file.modifiedAt),
                                     icon: .glyph(RowIcon.fileIcon(file.name), PiperTheme.fileNS),
                                     selected: model.selectedDocument == file.id) { open(file.id) }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .overlay {
            if groups.isEmpty { EmptyPane(title: "No Files", detail: "This folder holds no files.") }
        }
    }

    /// The files under `folder`, one group for each folder, with the files of
    /// a group in the order of their names.
    static func groups(_ files: [VaultFile], in folder: String) -> [(folder: String, files: [VaultFile])] {
        let prefix = folder.isEmpty ? "" : folder + "/"
        let inside = files.filter { folder.isEmpty || $0.folder == folder || $0.folder.hasPrefix(prefix) }
        let grouped = Dictionary(grouping: inside, by: \.folder)
        return grouped.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { key in
            (key, grouped[key, default: []].sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }
}

/// The sessions of one folder, the newest change first, under a New Session row.
struct SessionList: View {
    @Bindable var model: AppModel
    let folder: String
    let open: (PaperItem) -> Void

    var body: some View {
        let sessions = model.agents.runner.sessions(in: folder)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                PaperListRow(title: "New Session", detail: "Start a session in this folder", time: "",
                             icon: .tile("claude", PiperTheme.claudeNS), selected: false) { open(.newSession(folder)) }
                if !sessions.isEmpty { IndexHeader(title: "Sessions") }
                ForEach(sessions) { session in
                    PaperListRow(title: session.title, detail: SessionStateChip.title(session.state),
                                 time: RowTime.text(session.updatedAt),
                                 icon: .dot(Self.color(session)), selected: model.selectedSession == session.id) {
                        open(.session(session.id))
                    }
                    .contextMenu {
                        Button("Delete Session") {
                            if model.selectedSession == session.id { model.selectedSession = nil }
                            model.agents.runner.delete(session)
                        }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    private static func color(_ session: AgentSession) -> NSColor {
        switch session.state {
        case .needsYou: return PiperTheme.claudeNS
        case .running, .waiting: return PiperTheme.successNS
        case .idle, .failed: return session.unread ? PiperTheme.brandNS : PiperTheme.paperFaintNS
        }
    }
}

/// One row of a list on the feed paper: an icon, a title, a detail line, and a time.
struct PaperListRow: View {
    let title: String
    let detail: String
    let time: String
    let icon: RowIcon
    let selected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RowIconView(icon: icon).padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(PiperTheme.paperUI(.row)).foregroundStyle(PiperTheme.paperInk).lineLimit(2)
                if !detail.isEmpty {
                    Text(detail).font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(time).font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint).monospacedDigit()
                .padding(.top, 3)
        }
        .padding(.horizontal, AppDefaults.Papers.rowPadding).padding(.vertical, 10)
        .background(selected || hovered ? PiperTheme.paperTint : .clear,
                    in: RoundedRectangle(cornerRadius: AppDefaults.Papers.rowRadius, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, action)
    }
}
