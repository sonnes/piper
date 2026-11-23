import AppKit
import SwiftUI

/// The tree of folders and files on the tab of a folder.
///
/// The tree shows the folders and files of the active folder, under a row
/// of swatches for the color of its tab. A click on a folder opens or closes
/// it. A click on a file opens it as a file paper. The folder tabs share the
/// list of open folders.
struct FolderTreeView: View {
    @Bindable var paper: FeedPaperModel
    let library: Library

    var body: some View {
        let rows = paper.treeRows
        let cursor = paper.treeCursor(in: rows)
        let dates = Dictionary(library.files.map { ($0.relativePath, $0.modifiedAt) }, uniquingKeysWith: { first, _ in first })
        VStack(alignment: .leading, spacing: 0) {
            swatches
                .padding(Metrics.subPadding)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            TreeRow(row: row, selected: row.id == cursor, date: dates[row.path],
                                    click: { paper.clickTreeRow(row) },
                                    toggle: { paper.toggleFolder(row) })
                                .id(row.id)
                        }
                        warnings
                    }
                    .padding(Metrics.treePadding)
                }
                .onChange(of: cursor) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
        .overlay {
            if rows.isEmpty, !library.loading {
                if let error = library.scanError {
                    PaperEmpty(symbol: "exclamationmark.triangle", title: "Cannot Read the Folder", detail: error)
                } else {
                    PaperEmpty(symbol: "folder", title: "No Files", detail: "This folder holds no files.")
                }
            }
        }
    }

    // MARK: - Parts

    /// The swatches for the color of the tab of the folder.
    private var swatches: some View {
        let current = paper.color(of: paper.state.tab)
        return HStack(spacing: 10) {
            Text("Tab color").foregroundStyle(PiperTheme.paperFaint)
            ForEach(TabColor.allCases) { color in
                Swatch(color: color, selected: color == current) { paper.setTabColor(color) }
            }
        }
        .font(PiperTheme.paperUI(.body))
    }

    @ViewBuilder private var warnings: some View {
        if !library.problems.isEmpty {
            DisclosureGroup("\(library.problems.count) file warnings") {
                Text(library.problems.joined(separator: "\n"))
                    .textSelection(.enabled).padding(.top, 5)
            }
            .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.warning)
            .padding(.horizontal, PaperRowMetrics.rowPadding).padding(.top, 12)
        }
    }
}

// MARK: - Rows

/// One row of the tree: a chevron, a folder or a sheet, the name, and a count or a date.
private struct TreeRow: View {
    let row: FolderTreeRow
    let selected: Bool
    let date: Date?
    let click: () -> Void
    let toggle: () -> Void

    @Environment(DeskMarks.self) private var marks: DeskMarks?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    private typealias Metrics = FolderTreeView.Metrics

    private var onDesk: Bool { !row.isFolder && marks?.isOpenFile(row.path) == true }

    var body: some View {
        HStack(spacing: Metrics.treeSpacing) {
            chevron
            if row.isFolder {
                FolderMark()
            } else {
                SheetMark().padding(.horizontal, 2)
            }
            name
            Spacer(minLength: 8)
            meta
        }
        .padding(.leading, Metrics.treeRowPadding.leading + CGFloat(row.depth) * Metrics.treeIndent)
        .padding(.trailing, Metrics.treeRowPadding.trailing)
        .padding(.vertical, Metrics.treeRowPadding.top)
        .frame(maxWidth: .infinity, minHeight: Metrics.treeRowHeight, alignment: .leading)
        .background(alignment: .leading) { guide }
        .background(PiperTheme.rowFill(selected: selected, focused: marks?.feedFocused == true, hovered: hovered),
                    in: RoundedRectangle(cornerRadius: PaperRowMetrics.rowRadius, style: .continuous))
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: PaperRowMetrics.hoverFade), value: hovered)
        .overlay { slot }
        .contentShape(Rectangle())
        .onTapGesture(perform: click)
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(row.isFolder ? (row.expanded ? "Open" : "Closed") : (onDesk ? "On the desk" : ""))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, click)
        .accessibilityActions {
            if row.isFolder {
                Button(row.expanded ? "Close \(row.name)" : "Open \(row.name)", action: toggle)
            }
        }
    }

    // MARK: - Parts

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: Metrics.treeChevronGlyph, weight: .semibold))
            .foregroundStyle(PiperTheme.paperFaint)
            .rotationEffect(.degrees(row.expanded ? 90 : 0))
            .animation(.easeOut(duration: 0.15), value: row.expanded)
            .frame(width: Metrics.treeChevron, height: Metrics.treeChevron)
            .opacity(row.isFolder ? 1 : 0)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var name: some View {
        let color = onDesk ? PiperTheme.paperFaint : PiperTheme.paperInk
        if row.isFolder {
            Text(row.name).font(PiperTheme.paperUI(.row, weight: .medium)).foregroundStyle(color)
                .lineLimit(1).truncationMode(.middle)
        } else {
            Text(row.name).font(PiperTheme.listTitle()).foregroundStyle(color)
                .lineLimit(1).truncationMode(.middle)
        }
    }

    @ViewBuilder private var meta: some View {
        Group {
            if row.isFolder {
                Text("\(row.count)").foregroundStyle(PiperTheme.paperMuted)
            } else if onDesk {
                Text("on the desk").fontWeight(.medium).foregroundStyle(PiperTheme.brand)
            } else if let date {
                Text(RowTime.text(date)).foregroundStyle(PiperTheme.paperMuted)
            }
        }
        .font(PiperTheme.paperUI(.body))
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
    }

    /// The line that joins the rows of one folder.
    @ViewBuilder private var guide: some View {
        if row.depth > 0 {
            Rectangle().fill(PiperTheme.paperRule).frame(width: 1)
                .padding(.leading, Metrics.treeGuide + CGFloat(row.depth - 1) * Metrics.treeIndent)
        }
    }

    @ViewBuilder private var slot: some View {
        if onDesk {
            RoundedRectangle(cornerRadius: PaperRowMetrics.rowRadius, style: .continuous)
                .strokeBorder(PiperTheme.paperSlot, style: StrokeStyle(lineWidth: PaperRowMetrics.markLine, dash: PaperRowMetrics.slotDash))
                .padding(PaperRowMetrics.markLine)
        }
    }

    @ViewBuilder private var menu: some View {
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: row.id)]) }
    }

    private var accessibilityTitle: String {
        guard row.isFolder else { return row.name }
        let files = row.count == 1 ? "1 file" : "\(row.count) files"
        return "\(row.name), folder, \(files)"
    }
}

/// A swatch of a tab color on the tree of a folder.
private struct Swatch: View {
    let color: TabColor
    let selected: Bool
    let action: () -> Void

    private typealias Metrics = FolderTreeView.Metrics

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(PaperTabs.Metrics.fill(color))
                .overlay(Circle().strokeBorder(PiperTheme.paper, lineWidth: Metrics.swatchBorder))
                .overlay {
                    let line: CGFloat = selected ? 2 : 1
                    Circle().inset(by: -line / 2).stroke(selected ? PiperTheme.paperInk : PiperTheme.paperRule, lineWidth: line)
                }
                .frame(width: Metrics.swatchSize, height: Metrics.swatchSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(color.name)
        .accessibilityLabel(color.name)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, action)
    }
}

// MARK: - Metrics

/// The folder tree of a folder tab.
extension FolderTreeView {
    enum Metrics {
        static let treeRowHeight: CGFloat = 40
        static let treeRowPadding = EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 14)
        static let treePadding = EdgeInsets(top: 10, leading: 12, bottom: 8, trailing: 12)
        static let treeIndent: CGFloat = 22
        static let treeSpacing: CGFloat = 8
        /// The guide line of a nested row lies at this distance from the left of its row, at level 1.
        static let treeGuide: CGFloat = 23
        static let treeChevron: CGFloat = 16
        static let treeChevronGlyph: CGFloat = 10
        /// The row of swatches under the title of a folder tab.
        static let subPadding = EdgeInsets(top: 8, leading: 32, bottom: 0, trailing: 32)
        static let swatchSize: CGFloat = 22
        static let swatchBorder: CGFloat = 2
    }
}
