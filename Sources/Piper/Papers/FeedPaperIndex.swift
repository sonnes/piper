import AppKit
import Captures
import Feeds
import SwiftUI

/// The index of the active tab, in place of the list of the feed paper.
///
/// Inbox shows its sections and Done. Feeds shows Discover, All Unread,
/// Starred, and each feed. Agents shows the folders that have sessions.
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
                case .agents: agentRows
                case .clipboard, .folders, .pinned: EmptyView()
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
        row(.scope(.inbox(section: nil)), title: "All Sections", count: open.count)
        IndexHeader(title: "Show")
        row(.inboxFilter(.notes), title: "Notes", count: open.filter { !$0.isArticle }.count)
        row(.inboxFilter(.reading), title: "Reading", count: open.filter(\.isArticle).count)
        IndexHeader(title: "Sections")
        ForEach(store.sections, id: \.self) { section in
            row(.scope(.inbox(section: section)), title: section, count: open.filter { $0.section == section }.count)
                .contextMenu {
                    Button("Edit Section…") {
                        sectionName = section
                        editingSection = section
                    }
                    Button("Delete Section…") { deletingSection = section }
                }
        }
        IndexHeader(title: "Finished")
        row(.scope(.done), title: "Done", count: 0)
        IndexAction(title: "New Section…") { namingSection = true }
    }

    /// A row that the keyboard can pick. It is current while the list shows its scope.
    private func row(_ entry: IndexEntry, title: String, leading: AnyView? = nil, count: Int,
                     current: Bool? = nil) -> IndexRow {
        IndexRow(title: title, leading: leading, count: count, current: current ?? (paper.currentEntry == entry),
                 cursor: paper.indexCursor == entry) { paper.pick(entry) }
    }

    // MARK: - Feeds

    @ViewBuilder private var feedRows: some View {
        let waiting = feeds.suggestions.filter { !$0.ignored && $0.feedURL != nil && feeds.feed($0.feedURL!) == nil }.count
        row(.scope(.feed(.discover)), title: "Discover", count: waiting)
        row(.scope(.feed(.allUnread)), title: "All Unread", count: feeds.totalUnread)
            .contextMenu { Button("Mark All as Read") { feeds.markAllRead(.allUnread) } }
        row(.scope(.feed(.starred)), title: "Starred", count: feeds.starredCount)
        if !feeds.feeds.isEmpty { IndexHeader(title: "Feeds") }
        ForEach(Array(feeds.feeds.enumerated()), id: \.element.id) { index, feed in
            row(.scope(.feed(.feed(feed.id))), title: feed.title, leading: AnyView(feedIcon(feed, index: index)),
                count: feeds.unreadCounts[feed.id] ?? 0)
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

    // MARK: - Agents

    @ViewBuilder private var agentRows: some View {
        let runner = model.agents.runner
        ForEach(runner.folders(), id: \.self) { folder in
            row(.scope(.sessions(folder)), title: URL(fileURLWithPath: folder).lastPathComponent,
                leading: AnyView(FolderMark()),
                count: runner.sessions(in: folder).filter { $0.state == .needsYou }.count)
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
            .padding(AppDefaults.Papers.indexHeaderPadding)
            .accessibilityAddTraits(.isHeader)
    }
}

/// An action at the end of an index or of the folder tree, such as Add Feed.
struct IndexAction: View {
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

/// One row of an index: an icon, a title, and a count.
struct IndexRow: View {
    let title: String
    var leading: AnyView?
    var icon: RowIcon?
    let count: Int
    let current: Bool
    /// True for the row that Return picks.
    var cursor = false
    let action: () -> Void

    @Environment(DeskMarks.self) private var marks: DeskMarks?
    @State private var hovered = false
    private typealias Metrics = AppDefaults.Papers

    var body: some View {
        HStack(spacing: 10) {
            if let leading { leading } else if let icon { RowIconView(icon: icon) }
            Text(title).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if count > 0 {
                Text("\(count)").monospacedDigit().fontWeight(.regular)
                    .foregroundStyle(current ? PiperTheme.markInk : PiperTheme.paperFaint)
            }
        }
        .font(PiperTheme.paperUI(.row, weight: .medium))
        .foregroundStyle(current ? PiperTheme.markInk : PiperTheme.paperInk)
        .padding(.horizontal, Metrics.rowPadding)
        .frame(minHeight: Metrics.rowHeight)
        .background(background, in: RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous))
        .overlay(alignment: .leading) {
            if keyed {
                Rectangle().fill(PiperTheme.brand).frame(width: Metrics.selectionBarWidth)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovered = $0 }
        // The row is one element. A press picks the row.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count > 0 ? "\(title), \(count)" : title)
        .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, action)
    }
}

extension IndexRow {
    /// True when the row shows the keyboard cursor: the cursor is on the row and the feed paper has the focus.
    fileprivate var keyed: Bool { cursor && marks?.feedFocused == true }

    fileprivate var background: Color {
        if current { return PiperTheme.currentRow }
        if keyed || hovered { return PiperTheme.paperTint }
        return .clear
    }
}

/// The folder of a row: a folder outline, in the color of the faint text or
/// in the color of the tab of a pinned folder.
struct FolderMark: View {
    var color = PiperTheme.paperFaint

    var body: some View {
        let metrics = AppDefaults.Papers.self
        RoundedRectangle(cornerRadius: 2)
            .strokeBorder(color, lineWidth: metrics.markLine)
            .frame(width: metrics.folderMark.width, height: metrics.folderMark.height)
            .overlay(alignment: .topLeading) {
                UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                    .stroke(color, lineWidth: metrics.markLine)
                    .frame(width: 7, height: 3)
                    .offset(x: 0, y: -3)
            }
            .padding(.top, 3)
            .accessibilityHidden(true)
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
