import Agents
import AppKit
import Feeds
import PiperTree
import SwiftUI
import Vault

/// The source list, its actions, and file warnings.
struct SidebarView: View {
    @Bindable var model: AppModel
    @Binding var expanded: Set<String>
    let selection: SidebarSelection
    let select: (SidebarSelection) -> Void
    /// Selects one session of a Claude folder, by its id and its folder.
    let selectSession: (UUID, String) -> Void
    @State private var namingSection = false
    @State private var editingSection: String?
    @State private var sectionName = ""
    @State private var deletingSection: String?

    var body: some View {
        VStack(spacing: 0) {
            SidebarOutline(model: model, sections: sectionCounts,
                           sessionFolders: sessionFolders, feeds: feedRows, selectedSession: model.selectedSession,
                           expanded: $expanded, selection: selection, openFile: model.selectedDocument, select: select,
                           selectSession: selectSession,
                           newSection: { namingSection = true },
                           editSection: { section in
                               sectionName = section
                               editingSection = section
                           },
                           deleteSection: { deletingSection = $0 },
                           addFeed: { model.addingFeed = true })
            if !model.wikiProblems.isEmpty {
                DisclosureGroup("\(model.wikiProblems.count) file warnings") {
                    Text(model.wikiProblems.joined(separator: "\n"))
                        .textSelection(.enabled).font(PiperTheme.ui(.caption)).padding(.top, 5)
                }
                .font(PiperTheme.ui(.caption)).foregroundStyle(PiperTheme.warning)
                .padding(.horizontal, AppDefaults.Sidebar.rowInset).padding(.vertical, 6)
            }
        }
        .sheet(isPresented: $model.addingFeed) {
            AddFeedSheet(feeds: model.feeds) { added in
                model.addingFeed = false
                if let added { select(.feeds(.feed(added))) }
            }
        }
        .sheet(isPresented: $namingSection) {
            NewSectionSheet(sections: model.store.sections) { name in
                guard model.store.chooseSection(name) else { return }
                namingSection = false
                expanded.remove(SidebarOutline.inboxCollapsedKey)
                select(.section(model.store.activeSection))
            }
        }
        .alert("Edit Section", isPresented: Binding(
            get: { editingSection != nil },
            set: { if !$0 { editingSection = nil } }
        ), presenting: editingSection) { section in
            TextField("Name", text: $sectionName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                guard model.store.renameSection(section, to: sectionName) else { return }
                if selection == .section(section) {
                    select(.section(sectionName.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            .disabled(sectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Delete Section?", isPresented: Binding(
            get: { deletingSection != nil },
            set: { if !$0 { deletingSection = nil } }
        ), presenting: deletingSection) { section in
            Button("Cancel", role: .cancel) {}
            Button("Delete Section", role: .destructive) {
                guard model.store.deleteSection(section) else { return }
                if selection == .section(section) { select(.inbox) }
            }
        } message: { section in
            Text("Delete \"\(section)\" and move its notes to Inbox. You can undo this change.")
        }
        .onChange(of: model.store.sections) { _, sections in
            if case .section(let name) = selection, !sections.contains(name) { select(.inbox) }
        }
    }

    /// Every capture section and the number of notes that are not done.
    private var sectionCounts: [SidebarSection] {
        model.store.sections.map { section in
            SidebarSection(name: section, count: model.store.notes.filter { $0.parent == nil && $0.section == section && !$0.isDone }.count)
        }
    }

    /// The rows of the Feeds group and their counts.
    private var feedRows: SidebarFeeds {
        let store = model.feeds
        return SidebarFeeds(
            unread: store.totalUnread,
            starred: store.starredCount,
            suggestions: store.suggestions.filter { !$0.ignored && $0.feedURL != nil && store.feed($0.feedURL!) == nil }.count,
            rows: store.feeds.map { SidebarFeeds.Row(id: $0.id, title: $0.title, unread: store.unreadCounts[$0.id] ?? 0, error: $0.error) }
        )
    }

    /// The folders with agent sessions, and the sessions of each.
    private var sessionFolders: [SidebarSessionFolder] {
        let runner = model.agents.runner
        return runner.folders().map { folder in
            let sessions = runner.sessions(in: folder)
            return SidebarSessionFolder(
                path: folder,
                attention: sessions.filter { $0.state == .needsYou }.count,
                sessions: sessions.map { SidebarSessionRow(id: $0.id, folder: folder, title: $0.title, status: .init($0)) }
            )
        }
    }
}

/// One folder in the Claude group of the sidebar.
struct SidebarSessionFolder: Equatable {
    let path: String
    /// The sessions that wait for an answer.
    let attention: Int
    /// The sessions of the folder, the most recently changed first.
    let sessions: [SidebarSessionRow]
}

/// One session under its folder in the Claude group of the sidebar.
struct SidebarSessionRow: Equatable {
    /// What the dot at the start of the row shows.
    enum Status: Equatable {
        case needsYou, working, unread, read

        @MainActor
        init(_ session: AgentSession) {
            switch session.state {
            case .needsYou: self = .needsYou
            case .running, .waiting: self = .working
            case .idle, .failed: self = session.unread ? .unread : .read
            }
        }
    }

    let id: UUID
    let folder: String
    let title: String
    let status: Status
}

/// The rows of the Feeds group in the sidebar.
struct SidebarFeeds: Equatable {
    struct Row: Equatable {
        let id: String
        let title: String
        let unread: Int
        let error: String?
    }

    var unread = 0
    var starred = 0
    /// The sites of Discover that have a feed and wait for an answer.
    var suggestions = 0
    var rows: [Row] = []
}

/// One capture section in the sidebar.
struct SidebarSection: Equatable {
    let name: String
    let count: Int
}
