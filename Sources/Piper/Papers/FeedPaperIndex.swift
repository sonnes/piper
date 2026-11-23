import AppKit
import Captures
import Feeds
import Stream
import SwiftUI

/// The index of the active tab, in place of the list of the feed paper.
///
/// Today shows its lenses, its sections, and Done. Feeds shows Sources and
/// each feed. Agents shows the folders that have sessions.
struct FeedPaperIndex: View {
    @Bindable var paper: FeedPaperModel
    @Bindable var model: AppModel

    @State private var editingSection: String?
    @State private var sectionName = ""
    @State private var deletingSection: String?
    @State private var namingSection = false

    private var store: CaptureStore { model.store }
    private var scope: PaperScope { paper.state.scope }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                switch paper.state.tab {
                case .today: todayRows
                case .feeds: feedRows
                case .agents: agentRows
                case .folder: EmptyView()
                }
            }
            .padding(FeedPaperIndex.Metrics.indexPadding)
        }
        .sheet(isPresented: $namingSection) {
            NewSectionSheet(sections: store.sections) { name in
                do { try store.chooseSection(name) } catch { return model.messages.report(error) }
                namingSection = false
                paper.pick(.today(section: store.activeSection))
            }
        }
        .alert("Edit Section", isPresented: Binding(
            get: { editingSection != nil },
            set: { if !$0 { editingSection = nil } }
        ), presenting: editingSection) { section in
            TextField("Name", text: $sectionName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                do { try store.renameSection(section, to: sectionName) } catch { return model.messages.report(error) }
                if scope == .today(section: section) {
                    paper.state.scope = .today(section: sectionName.trimmingCharacters(in: .whitespacesAndNewlines))
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
                do { try store.deleteSection(section) } catch { return model.messages.report(error) }
                if scope == .today(section: section) { paper.state.scope = .today(section: nil) }
            }
        } message: { section in
            Text("Delete \"\(section)\" and move its notes to Inbox. You can undo this change.")
        }
    }

    // MARK: - Today

    @ViewBuilder private var todayRows: some View {
        let stream = UnifiedStream(paper.today.input(), lens: .all)
        let open = store.notes.filter { $0.parent == nil && !$0.isDone }
        ForEach(UnifiedStream.Lens.allCases, id: \.self) { lens in
            row(.lens(lens), title: lens.title, count: stream.counts[lens] ?? 0)
        }
        IndexHeader(title: "Sections")
        ForEach(store.sections, id: \.self) { section in
            row(.scope(.today(section: section)), title: section, count: open.filter { $0.section == section }.count)
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
    private func row(_ entry: IndexEntry, title: String, leading: AnyView? = nil, count: Int) -> IndexRow {
        IndexRow(title: title, leading: leading, count: count, current: paper.currentEntry == entry,
                 cursor: paper.indexCursor == entry) { paper.pick(entry) }
    }

    // MARK: - Feeds

    /// Sources first, where the reader adds a feed, then each feed with its unread count.
    @ViewBuilder private var feedRows: some View {
        let feeds = model.feeds
        let unread = feeds.unreadCounts()
        row(.scope(.sources), title: "Sources", leading: AnyView(Image(systemName: "plus.circle")
            .foregroundStyle(PiperTheme.paperFaint).accessibilityHidden(true)), count: 0)
            .help("Add a feed and manage feeds")
        IndexHeader(title: "Feeds")
        ForEach(feeds.feeds) { feed in
            row(.scope(.feed(feed.id)), title: feed.title,
                leading: AnyView(SiteIcon(favicons: model.favicons, host: feed.host, title: feed.title)),
                count: unread[feed.id] ?? 0)
                .help(feed.id)
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
            .font(PiperTheme.paperUI(.body, weight: .semibold))
            .foregroundStyle(PiperTheme.paperMuted)
            .padding(FeedPaperIndex.Metrics.indexHeaderPadding)
            .accessibilityAddTraits(.isHeader)
    }
}

/// An action at the end of an index, such as New Section.
struct IndexAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(PiperTheme.paperUI(.body, weight: .medium)).foregroundStyle(PiperTheme.brand)
                .padding(.horizontal, PaperRowMetrics.rowPadding).padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }
}

/// One row of an index: a leading mark, a title, and a count.
struct IndexRow: View {
    let title: String
    var leading: AnyView?
    let count: Int
    let current: Bool
    /// True for the row that Return picks.
    var cursor = false
    let action: () -> Void

    @Environment(DeskMarks.self) private var marks: DeskMarks?
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private typealias Metrics = FeedPaperIndex.Metrics

    var body: some View {
        HStack(spacing: 10) {
            if let leading { leading }
            Text(title).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if count > 0 {
                Text("\(count)").monospacedDigit().fontWeight(.regular)
                    .foregroundStyle(PiperTheme.paperMuted)
            }
        }
        .font(PiperTheme.paperUI(.row, weight: .medium))
        .foregroundStyle(PiperTheme.paperInk)
        .padding(.horizontal, PaperRowMetrics.rowPadding)
        .frame(minHeight: Metrics.rowHeight)
        .background(background, in: RoundedRectangle(cornerRadius: PaperRowMetrics.rowRadius, style: .continuous))
        .overlay {
            // The keyboard cursor is a focus ring, as in the Apple apps.
            if keyed {
                RoundedRectangle(cornerRadius: PaperRowMetrics.rowRadius, style: .continuous)
                    .strokeBorder(PiperTheme.brand, lineWidth: Metrics.cursorRing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PaperRowMetrics.rowRadius, style: .continuous))
        .animation(reduceMotion ? nil : .easeOut(duration: PaperRowMetrics.hoverFade), value: hovered)
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
        if current { return PiperTheme.rowSelection }
        return hovered ? PiperTheme.rowHover : .clear
    }
}

/// The folder of a row: a folder outline in the color of the faint text.
struct FolderMark: View {
    var color = PiperTheme.paperFaint

    var body: some View {
        let metrics = FeedPaperIndex.Metrics.self
        RoundedRectangle(cornerRadius: 2)
            .strokeBorder(color, lineWidth: PaperRowMetrics.markLine)
            .frame(width: metrics.folderMark.width, height: metrics.folderMark.height)
            .overlay(alignment: .topLeading) {
                UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                    .stroke(color, lineWidth: PaperRowMetrics.markLine)
                    .frame(width: 7, height: 3)
                    .offset(x: 0, y: -3)
            }
            .padding(.top, 3)
            .accessibilityHidden(true)
    }
}

// MARK: - Metrics

extension FeedPaperIndex {
    enum Metrics {
        static let indexPadding = EdgeInsets(top: 16, leading: 20, bottom: 20, trailing: 20)
        /// A group header of an index, such as Sections.
        static let indexHeaderPadding = EdgeInsets(top: 12, leading: 12, bottom: 4, trailing: 12)
        /// The folder outline of a row of an index and of the folder tree.
        static let folderMark = CGSize(width: 16, height: 12)
        static let rowHeight: CGFloat = 48
        /// The ring of the keyboard cursor on a row of an index.
        static let cursorRing: CGFloat = 2
    }
}
