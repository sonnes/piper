import Feeds
import SwiftUI

/// The comments of a story of the Hacker News tab, on a reader paper, as a tree.
///
/// Each reply shows under its parent. A thread line runs down from each
/// comment past all of its replies. A click on the line, or on the button
/// at the top of the line, collapses the comment and its replies. Piper reads
/// the comments each time the paper opens, and it saves none of them.
struct HackerNewsComments: View {
    let story: HackerNews.Story
    /// Reads the comments. A test or a preview replaces it.
    var fetch: (HackerNews.Story) async throws -> HackerNews.Thread = { try await HackerNews.thread(of: $0) }

    @State private var thread: HackerNews.Thread?
    @State private var error: String?
    @State private var collapsed: Set<Int> = []
    /// The comment whose thread line is under the pointer. Its whole line shows in the brand color.
    @State private var hovered: Int?

    var body: some View {
        Group {
            if let thread {
                content(thread)
            } else if let error {
                EmptyPane(title: "Cannot Load Comments", detail: error)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(PiperTheme.paper)
        .task { await load() }
    }

    private func content(_ thread: HackerNews.Thread) -> some View {
        ScrollView {
            // No space between the rows, so the thread lines join from row to row.
            LazyVStack(alignment: .leading, spacing: 0) {
                storyHeader(thread)
                ForEach(HackerNews.rows(of: thread.comments, collapsed: collapsed)) { row in
                    CommentRow(row: row, op: story.author, collapsed: collapsed.contains(row.id), hovered: $hovered,
                               toggle: toggle)
                        .padding(.top, row.depth == 0 ? Metrics.threadGap : 0)
                }
            }
            .frame(maxWidth: Metrics.readingWidth, alignment: .leading)
            .padding(Metrics.padding)
            .frame(maxWidth: .infinity)
        }
    }

    private func storyHeader(_ thread: HackerNews.Thread) -> some View {
        VStack(alignment: .leading, spacing: Metrics.storySpacing) {
            Text(story.title)
                .font(PiperTheme.paperTitle(.heading))
                .foregroundStyle(PiperTheme.paperInk)
                .textSelection(.enabled)
            Text(["\(story.points) points", story.author, "\(story.comments) comments", RowTime.text(story.time)]
                .joined(separator: " · "))
                .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
            if let text = thread.text {
                Text(text).font(PiperTheme.paperUI(.row)).foregroundStyle(PiperTheme.paperInk)
                    .textSelection(.enabled)
            }
            if thread.comments.isEmpty {
                Text("No comments yet.").font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted)
            }
        }
        .padding(.bottom, Metrics.storyBottom)
    }

    private func toggle(_ id: Int) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        hovered = nil
    }

    private func load() async {
        do {
            thread = try await fetch(story)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension HackerNewsComments {
    enum Metrics {
        static let padding = EdgeInsets(top: 16, leading: 32, bottom: 32, trailing: 32)
        /// The widest line of the comments, as in the Reader tab.
        static let readingWidth: CGFloat = 680
        static let storySpacing: CGFloat = 6
        static let storyBottom: CGFloat = 8
        /// The space over each top comment.
        static let threadGap: CGFloat = 16
        /// The width of the column of one thread line.
        static let column: CGFloat = 20
        /// The most thread lines that a comment shows. A deeper reply shows the lines of its nearest parents.
        static let maxColumns = 10
        static let lineWidth: CGFloat = 1.5
        static let hoverLineWidth: CGFloat = 2.5
        /// The circle at the top of the thread line of a comment.
        static let toggleSize: CGFloat = 16
        static let toggleGlyph: CGFloat = 9
        static let toggleBorder: CGFloat = 1
        /// The dot of a comment with no replies.
        static let dotSize: CGFloat = 5
        static let headerSpacing: CGFloat = 8
        static let headerHeight: CGFloat = 20
        static let textTop: CGFloat = 2
        /// The space under the text of a comment, inside the row, so that the lines run through it.
        static let rowBottom: CGFloat = 12
        static let opPadding = EdgeInsets(top: 1, leading: 5, bottom: 1, trailing: 5)
        static let opRadius: CGFloat = 4
    }
}

/// One comment of the tree: the thread lines of the comments above it, its
/// own line with the collapse button, and its author, time, and text.
private struct CommentRow: View {
    let row: HackerNews.Row
    /// The author of the story, whose comments show an OP mark.
    let op: String
    let collapsed: Bool
    @Binding var hovered: Int?
    let toggle: (Int) -> Void

    private typealias Metrics = HackerNewsComments.Metrics

    private var lines: ArraySlice<Int> { row.ancestors.suffix(Metrics.maxColumns) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(lines), id: \.self) { ancestor in
                ThreadLine(id: ancestor, hovered: $hovered, toggle: toggle)
            }
            ownColumn
            VStack(alignment: .leading, spacing: Metrics.textTop) {
                header
                if !collapsed {
                    Text(row.comment.text).font(PiperTheme.paperUI(.row)).foregroundStyle(PiperTheme.paperInk)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, Metrics.rowBottom)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The row takes the height of its text, and the thread lines fill that height.
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(spacing: Metrics.headerSpacing) {
            Text(row.comment.author).font(PiperTheme.paperUI(.body, weight: .semibold))
                .foregroundStyle(row.comment.author == op ? PiperTheme.brand : PiperTheme.paperMuted)
            if row.comment.author == op {
                Text("OP").font(PiperTheme.paperUI(.body, weight: .semibold)).foregroundStyle(PiperTheme.onAccent)
                    .padding(Metrics.opPadding)
                    .background(PiperTheme.brand, in: RoundedRectangle(cornerRadius: Metrics.opRadius, style: .continuous))
                    .accessibilityLabel("Author of the story")
            }
            Text(RowTime.text(row.comment.time)).font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
            if collapsed && row.replyCount > 0 {
                Text(row.replyCount == 1 ? "1 reply" : "\(row.replyCount) replies")
                    .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
            }
        }
        .frame(height: Metrics.headerHeight)
    }

    /// The column of the comment: the button that collapses it, and the line
    /// that runs down past its replies.
    private var ownColumn: some View {
        VStack(spacing: 0) {
            Button { toggle(row.id) } label: {
                ZStack {
                    Circle().strokeBorder(hovered == row.id ? PiperTheme.brand : PiperTheme.paperRule,
                                          lineWidth: Metrics.toggleBorder)
                    Image(systemName: collapsed ? "plus" : "minus")
                        .font(.system(size: Metrics.toggleGlyph, weight: .bold))
                        .foregroundStyle(hovered == row.id ? PiperTheme.brand : PiperTheme.paperFaint)
                }
                .frame(width: Metrics.toggleSize, height: Metrics.toggleSize)
                .frame(width: Metrics.column, height: Metrics.headerHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 ? row.id : (hovered == row.id ? nil : hovered) }
            .help(collapsed ? "Expand the comment" : "Collapse the comment and its replies")
            .accessibilityLabel(collapsed ? "Expand the comment by \(row.comment.author)"
                                          : "Collapse the comment by \(row.comment.author)")
            if !collapsed && row.replyCount > 0 {
                ThreadLine(id: row.id, hovered: $hovered, toggle: toggle)
            } else {
                Color.clear.frame(width: Metrics.column)
            }
        }
    }
}

/// The thread line of one comment, in the rows of its replies. A click on the line collapses the comment.
private struct ThreadLine: View {
    let id: Int
    @Binding var hovered: Int?
    let toggle: (Int) -> Void

    private typealias Metrics = HackerNewsComments.Metrics

    var body: some View {
        let lit = hovered == id
        Rectangle()
            .fill(lit ? PiperTheme.brand : PiperTheme.paperRule)
            .frame(width: lit ? Metrics.hoverLineWidth : Metrics.lineWidth)
            .frame(width: Metrics.column)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { toggle(id) }
            .onHover { hovered = $0 ? id : (hovered == id ? nil : hovered) }
            .help("Collapse the thread")
            .accessibilityHidden(true)
    }
}
