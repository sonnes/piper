import AppKit
import Captures
import Feeds
import SwiftUI

/// The index of the active tab, in place of the list of the feed paper.
///
/// Inbox shows its sections and Done. Feeds shows Discover, All Unread,
/// Starred, and each feed. Folders shows the pinned folders that have no tab,
/// then the folders and the tree of the active folder. Agents shows the
/// folders that have sessions.
struct FeedPaperIndex: View {
    @Bindable var paper: FeedPaperModel
    @Bindable var model: AppModel

    @State private var editingSection: String?
    @State private var sectionName = ""
    @State private var deletingSection: String?
    @State private var namingSection = false

    private var store: CaptureStore { model.store }
    private var feeds: FeedStore { model.feeds }
    private var scope: PaperScope { paper.state.scope }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                switch paper.state.tab {
                case .inbox: inbox
                case .feeds: feedRows
                case .folders: folderRows
                case .agents: agentRows
                case .clipboard, .pinned: EmptyView()
                }
            }
            .padding(AppDefaults.Papers.indexPadding)
        }
        .sheet(isPresented: $namingSection) {
            NewSectionSheet(sections: store.sections) { name in
                guard store.chooseSection(name) else { return }
                namingSection = false
                paper.pick(.inbox(section: store.activeSection))
            }
        }
        .alert("Edit Section", isPresented: Binding(
            get: { editingSection != nil },
            set: { if !$0 { editingSection = nil } }
        ), presenting: editingSection) { section in
            TextField("Name", text: $sectionName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                guard store.renameSection(section, to: sectionName) else { return }
                if scope == .inbox(section: section) {
                    paper.state.scope = .inbox(section: sectionName.trimmingCharacters(in: .whitespacesAndNewlines))
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
                guard store.deleteSection(section) else { return }
                if scope == .inbox(section: section) { paper.state.scope = .inbox(section: nil) }
            }
        } message: { section in
            Text("Delete \"\(section)\" and move its notes to Inbox. You can undo this change.")
        }
    }

    // MARK: - Inbox

    @ViewBuilder private var inbox: some View {
        let open = store.notes.filter { $0.parent == nil && !$0.isDone }
        IndexRow(title: "All Sections", icon: .glyph("inbox", PiperTheme.inboxNS), count: open.count,
                 current: scope == .inbox(section: nil)) { paper.pick(.inbox(section: nil)) }
        IndexHeader(title: "Sections")
        ForEach(store.sections, id: \.self) { section in
            IndexRow(title: section, icon: section == RowIcon.inboxSection ? .glyph("inbox", PiperTheme.inboxNS)
                        : .dot(RowIcon.sectionColor(section, in: store.sections)),
                     count: open.filter { $0.section == section }.count,
                     current: scope == .inbox(section: section)) { paper.pick(.inbox(section: section)) }
                .contextMenu {
                    Button("Edit Section…") {
                        sectionName = section
                        editingSection = section
                    }
                    Button("Delete Section…") { deletingSection = section }
                }
        }
        IndexHeader(title: "Finished")
        IndexRow(title: "Done", icon: .glyph("archived", PiperTheme.archivedNS), count: 0,
                 current: scope == .done) { paper.pick(.done) }
        IndexAction(title: "New Section…") { namingSection = true }
    }

    // MARK: - Feeds

    @ViewBuilder private var feedRows: some View {
        let waiting = feeds.suggestions.filter { !$0.ignored && $0.feedURL != nil && feeds.feed($0.feedURL!) == nil }.count
        IndexRow(title: "Discover", icon: .glyph("compass", PiperTheme.feedsNS), count: waiting,
                 current: scope == .feed(.discover)) { paper.pick(.feed(.discover)) }
        IndexRow(title: "All Unread", icon: .glyph("rss", PiperTheme.feedsNS), count: feeds.totalUnread,
                 current: scope == .feed(.allUnread)) { paper.pick(.feed(.allUnread)) }
            .contextMenu { Button("Mark All as Read") { feeds.markAllRead(.allUnread) } }
        IndexRow(title: "Starred", icon: .glyph("star", PiperTheme.starNS), count: feeds.starredCount,
                 current: scope == .feed(.starred)) { paper.pick(.feed(.starred)) }
        if !feeds.feeds.isEmpty { IndexHeader(title: "Feeds") }
        ForEach(Array(feeds.feeds.enumerated()), id: \.element.id) { index, feed in
            IndexRow(title: feed.title,
                     leading: AnyView(feedIcon(feed, index: index)),
                     count: feeds.unreadCounts[feed.id] ?? 0,
                     current: scope == .feed(.feed(feed.id))) { paper.pick(.feed(.feed(feed.id))) }
                .help(feed.error ?? feed.title)
                .contextMenu {
                    Button("Mark All as Read") { feeds.markAllRead(.feed(feed.id)) }
                    Divider()
                    Button("Copy Feed Address") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(feed.id, forType: .string)
                    }
                    Button("Unsubscribe") {
                        if scope == .feed(.feed(feed.id)) { paper.state.scope = .feed(.allUnread) }
                        feeds.unsubscribe(feed.id)
                    }
                }
        }
        IndexAction(title: "Add Feed…") { model.addingFeed = true }
    }

    @ViewBuilder private func feedIcon(_ feed: Feed, index: Int) -> some View {
        if feed.error != nil {
            RowIconView(icon: .glyph("rss", PiperTheme.warningNS))
        } else {
            SiteIcon(favicons: model.favicons, host: feed.host, title: feed.title, index: index)
        }
    }

    // MARK: - Folders

    @ViewBuilder private var folderRows: some View {
        let overflow = paper.column.overflow
        if !overflow.isEmpty {
            IndexHeader(title: "Pinned")
            ForEach(overflow, id: \.self) { path in
                IndexRow(title: URL(fileURLWithPath: path).lastPathComponent,
                         icon: .glyph("folder", PiperTheme.folderNS), count: 0,
                         current: false) { paper.pickPinned(path) }
                    .contextMenu { folderMenu(path, root: nil) }
            }
            IndexHeader(title: "Folders")
        }
        ForEach(Array(model.wikiPaths.enumerated()), id: \.element) { index, root in
            let name = URL(fileURLWithPath: root).lastPathComponent
            if root == model.wikiPath {
                IndexRow(title: name, icon: RowIcon.folderIcon(name, at: index), count: 0,
                         current: paper.state.tab == .folders && scope == .folder("")) { paper.pick(.folder("")) }
                    .contextMenu { folderMenu(model.vault.root.path, root: root) }
                tree
            } else {
                IndexRow(title: name, icon: RowIcon.folderIcon(name, at: index), count: 0, current: false) {
                    model.changeWiki(to: URL(fileURLWithPath: root))
                }
                .contextMenu { folderMenu(root, root: root) }
            }
        }
        IndexAction(title: "Add Folder…") { model.chooseWiki() }
        if !model.wikiProblems.isEmpty {
            DisclosureGroup("\(model.wikiProblems.count) file warnings") {
                Text(model.wikiProblems.joined(separator: "\n"))
                    .textSelection(.enabled).padding(.top, 5)
            }
            .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.warning)
            .padding(.horizontal, AppDefaults.Papers.rowPadding).padding(.top, 12)
        }
    }

    @ViewBuilder private var tree: some View {
        let expanded = Set(paper.state.expandedFolders)
        let rows = FolderIndex.rows(paths: model.files.map(\.relativePath), folders: model.folders, expanded: expanded)
        ForEach(rows) { row in
            if row.isFolder {
                IndexRow(title: row.name, icon: .glyph("folder", PiperTheme.folderNS), count: 0,
                         depth: row.depth, disclosure: row.hasChildren ? row.expanded : nil,
                         current: paper.state.tab == .folders && scope == .folder(row.path),
                         toggle: { toggle(row.path) }) { paper.pick(.folder(row.path)) }
                    .contextMenu { folderMenu(model.vault.root.appendingPathComponent(row.path).path, root: nil) }
            } else {
                IndexRow(title: row.name, icon: .glyph(RowIcon.fileIcon(row.name), PiperTheme.fileNS), count: 0,
                         depth: row.depth, weight: .regular, current: false) {
                    model.openDocument(row.path)
                    paper.open(.file)
                }
                .help(row.path)
            }
        }
    }

    @ViewBuilder private func folderMenu(_ path: String, root: String?) -> some View {
        Button(paper.state.pinnedFolders.contains(path) ? "Unpin from Tabs" : "Pin to Tabs") { paper.togglePin(path) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        if let root, model.wikiPaths.count > 1 {
            Divider()
            Button("Remove Folder") { model.removeWikiFolder(root) }
        }
    }

    private func toggle(_ path: String) {
        if let index = paper.state.expandedFolders.firstIndex(of: path) {
            paper.state.expandedFolders.remove(at: index)
        } else {
            paper.state.expandedFolders.append(path)
        }
    }

    // MARK: - Agents

    @ViewBuilder private var agentRows: some View {
        let runner = model.agents.runner
        ForEach(runner.folders(), id: \.self) { folder in
            IndexRow(title: URL(fileURLWithPath: folder).lastPathComponent, icon: .tile("claude", PiperTheme.claudeNS),
                     count: runner.sessions(in: folder).filter { $0.state == .needsYou }.count,
                     current: scope == .sessions(folder)) { paper.pick(.sessions(folder)) }
                .help(folder)
        }
    }
}

// MARK: - Rows

/// A group header on an index.
struct IndexHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(PiperTheme.paperUI(.body, weight: .medium))
            .foregroundStyle(PiperTheme.paperFaint)
            .padding(.horizontal, AppDefaults.Papers.rowPadding)
            .padding(.top, 14).padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// An action at the end of an index, such as Add Feed.
private struct IndexAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(PiperTheme.paperUI(.body, weight: .medium)).foregroundStyle(PiperTheme.brand)
                .padding(.horizontal, AppDefaults.Papers.rowPadding).padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }
}

/// One row of an index: an icon, a title, and a count. A folder row has a
/// disclosure button that opens or closes the folder.
struct IndexRow: View {
    let title: String
    var leading: AnyView?
    var icon: RowIcon?
    let count: Int
    var depth = 0
    /// Nil for a row with nothing under it. True for an open folder.
    var disclosure: Bool?
    var weight: NSFont.Weight = .medium
    let current: Bool
    var toggle: () -> Void = {}
    let action: () -> Void

    @State private var hovered = false
    private typealias Metrics = AppDefaults.Papers

    init(title: String, leading: AnyView? = nil, icon: RowIcon? = nil, count: Int, depth: Int = 0,
         disclosure: Bool? = nil, weight: NSFont.Weight = .medium, current: Bool,
         toggle: @escaping () -> Void = {}, action: @escaping () -> Void) {
        self.title = title
        self.leading = leading
        self.icon = icon
        self.count = count
        self.depth = depth
        self.disclosure = disclosure
        self.weight = weight
        self.current = current
        self.toggle = toggle
        self.action = action
    }

    var body: some View {
        HStack(spacing: 10) {
            if depth > 0 {
                Button(action: toggle) {
                    Image(systemName: disclosure == true ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PiperTheme.paperFaint)
                        .frame(width: 12)
                        .opacity(disclosure == nil ? 0 : 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disclosure == nil)
                .accessibilityLabel(disclosure == true ? "Close \(title)" : "Open \(title)")
                .accessibilityHidden(disclosure == nil)
            }
            if let leading { leading } else if let icon { RowIconView(icon: icon) }
            Text(title).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if count > 0 {
                Text("\(count)").monospacedDigit().foregroundStyle(current ? PiperTheme.paperInk : PiperTheme.paperFaint)
            }
        }
        .font(PiperTheme.paperUI(.row, weight: weight))
        .foregroundStyle(PiperTheme.paperInk)
        .padding(.leading, Metrics.rowPadding + CGFloat(max(0, depth - 1)) * Metrics.indent)
        .padding(.trailing, Metrics.rowPadding)
        .frame(minHeight: Metrics.rowHeight)
        .background(current ? PiperTheme.currentRow : hovered ? PiperTheme.paperTint : .clear,
                    in: RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovered = $0 }
        // The row is one element. A press picks the row. The disclosure is a named action.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count > 0 ? "\(title), \(count)" : title)
        .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, action)
        .accessibilityActions {
            if disclosure != nil {
                Button(disclosure == true ? "Close \(title)" : "Open \(title)", action: toggle)
            }
        }
    }
}

/// A `RowIcon` at the size of a row.
struct RowIconView: View {
    let icon: RowIcon
    var side = AppDefaults.RowIcon.size

    var body: some View {
        if case .glyph(_, let color) = icon, let image = icon.image(side: side) {
            Image(nsImage: image).renderingMode(.template).resizable().interpolation(.high)
                .foregroundStyle(Color(nsColor: color))
                .frame(width: side, height: side)
                .accessibilityHidden(true)
        } else if let image = icon.image(side: side) {
            Image(nsImage: image).frame(width: side, height: side).accessibilityHidden(true)
        }
    }
}
