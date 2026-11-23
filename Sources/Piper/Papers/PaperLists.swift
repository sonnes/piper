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
    /// Sets the keys of the list on the feed paper.
    var setKeys: (FeedPaperModel.ListKeys?) -> Void = { _ in }

    @State private var selected: String?
    @State private var scrollTarget: String?

    var body: some View {
        let groups = Self.groups(model.files, in: folder)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups, id: \.folder) { group in
                        PaperGroupHeader(title: group.folder.isEmpty ? model.vault.root.lastPathComponent
                                         : group.folder.replacingOccurrences(of: "/", with: " › "))
                        ForEach(group.files) { file in
                            FileRow(file: file, selected: (selected ?? model.selectedDocument) == file.id) {
                                selected = file.id
                                open(file.id)
                            }
                            .id(file.id)
                        }
                    }
                }
                .padding(AppDefaults.Papers.listPadding)
            }
            .onChange(of: scrollTarget) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
        .overlay {
            if groups.isEmpty { PaperEmpty(title: "No Files", detail: "This folder holds no files.") }
        }
        .onAppear { setKeys(keys(groups)) }
        .onChange(of: groups.flatMap(\.files).map(\.id)) { _, _ in setKeys(keys(groups)) }
        .onChange(of: selected) { _, _ in setKeys(keys(groups)) }
    }

    private func keys(_ groups: [(folder: String, files: [VaultFile])]) -> FeedPaperModel.ListKeys {
        let ids = groups.flatMap(\.files).map(\.id)
        let current = selected ?? model.selectedDocument
        return FeedPaperModel.ListKeys(
            move: { delta in
                guard let next = Self.step(from: current, by: delta, in: ids) else { return }
                selected = next
                scrollTarget = next
            },
            open: {
                if let current, ids.contains(current) { open(current) }
            })
    }

    /// The row after or before `current`, or the first or the last row when no row is selected.
    static func step(from current: String?, by delta: Int, in ids: [String]) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else { return delta > 0 ? ids.first : ids.last }
        return ids[max(0, min(ids.count - 1, index + delta))]
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

/// One file in a folder list: the sheet, the title in serif, and the name of the file.
private struct FileRow: View {
    let file: VaultFile
    let selected: Bool
    let action: () -> Void

    @Environment(DeskMarks.self) private var marks: DeskMarks?

    var body: some View {
        PaperRow(item: nil, openOnDesk: marks?.isOpenFile(file.id) == true, selected: selected,
                 time: RowTime.text(file.modifiedAt), action: action) {
            SheetMark()
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                PaperRowTitle(text: Text(file.title), read: true)
                PaperRowMeta { Text(file.name) }
            }
        }
    }
}

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
