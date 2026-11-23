import AppKit
import SwiftUI

/// The tree of folders and files on the Folders tab and on a pinned folder tab.
///
/// Folders shows the whole tree. A pinned folder tab shows the folders and
/// files in its folder, under a row of swatches for the color of its tab. A
/// click on a folder opens or closes it. A click on a file opens it as a
/// file paper. The two tabs share the open folders.
struct FolderTreeView: View {
    @Bindable var paper: FeedPaperModel
    @Bindable var model: AppModel

    private typealias Metrics = AppDefaults.Papers

    var body: some View {
        let rows = paper.treeRows
        let cursor = paper.treeCursor(in: rows)
        let tabs = Set(paper.column.tabs.compactMap { tab -> String? in
            if case .pinned(let path) = tab { return path }
            return nil
        })
        let dates = Dictionary(model.files.map { ($0.relativePath, $0.modifiedAt) }, uniquingKeysWith: { first, _ in first })
        VStack(alignment: .leading, spacing: 0) {
            subline(rows: rows, tabs: tabs.count)
                .padding(Metrics.subPadding)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            TreeRow(row: row, selected: row.id == cursor,
                                    tabColor: tabs.contains(row.id) ? paper.color(of: .pinned(row.id)) : nil,
                                    date: dates[row.path],
                                    click: { paper.clickTreeRow(row) },
                                    toggle: { paper.toggleFolder(row) },
                                    pin: { paper.togglePin(row.id) },
                                    removeRoot: model.wikiPaths.count > 1 && row.path.isEmpty && row.depth == 0
                                        ? { model.removeWikiFolder(row.id) } : nil)
                                .id(row.id)
                        }
                        if paper.state.tab == .folders { footer }
                    }
                    .padding(Metrics.treePadding)
                }
                .onChange(of: cursor) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
        .overlay {
            if rows.isEmpty, !model.loading {
                PaperEmpty(title: "No Files", detail: "This folder holds no files.")
            }
        }
    }

    // MARK: - Parts

    /// The summary of the Folders tab, or the swatches of a pinned folder.
    @ViewBuilder private func subline(rows: [FolderTreeRow], tabs: Int) -> some View {
        if case .pinned(let path) = paper.state.tab {
            let current = paper.color(of: .pinned(path))
            HStack(spacing: 10) {
                Text("Tab color").foregroundStyle(PiperTheme.paperFaint)
                ForEach(TabColor.allCases) { color in
                    Swatch(color: color, selected: color == current) { paper.setTabColor(color) }
                }
            }
            .font(PiperTheme.paperUI(.body))
        } else {
            Text(paper.treeMessage ?? Self.summary(folders: rows.filter { $0.depth == 0 && $0.isFolder }.count, tabs: tabs))
                .font(PiperTheme.paperUI(.body))
                .foregroundStyle(PiperTheme.paperMuted)
        }
    }

    /// "4 folders. 3 have a tab."
    static func summary(folders: Int, tabs: Int) -> String {
        let first = folders == 1 ? "1 folder." : "\(folders) folders."
        switch tabs {
        case 0: return first + " None has a tab."
        case 1: return first + " 1 has a tab."
        default: return first + " \(tabs) have a tab."
        }
    }

    @ViewBuilder private var footer: some View {
        IndexAction(title: "Add Folder…") { model.chooseWiki() }
        if !model.wikiProblems.isEmpty {
            DisclosureGroup("\(model.wikiProblems.count) file warnings") {
                Text(model.wikiProblems.joined(separator: "\n"))
                    .textSelection(.enabled).padding(.top, 5)
            }
            .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.warning)
            .padding(.horizontal, Metrics.rowPadding).padding(.top, 12)
        }
    }
}

// MARK: - Rows

/// One row of the tree: a chevron, a folder or a sheet, the name, and a count or a date.
private struct TreeRow: View {
    let row: FolderTreeRow
    let selected: Bool
    /// The color of the tab of a pinned folder, or nil for a row without a tab.
    let tabColor: TabColor?
    let date: Date?
    let click: () -> Void
    let toggle: () -> Void
    let pin: () -> Void
    /// Removes a folder from the folder list. Nil for a row that is not in the list.
    let removeRoot: (() -> Void)?

    @Environment(DeskMarks.self) private var marks: DeskMarks?
    private typealias Metrics = AppDefaults.Papers

    private var onDesk: Bool { !row.isFolder && marks?.isOpenFile(row.path) == true }

    var body: some View {
        HStack(spacing: Metrics.treeSpacing) {
            chevron
            if row.isFolder {
                FolderMark(color: tabColor.map(PiperTheme.tabEdge) ?? PiperTheme.paperFaint)
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
        .background(selected ? PiperTheme.paperTint : .clear,
                    in: RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous))
        .overlay(alignment: .leading) { selectionBar }
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
                Button(tabColor == nil ? "Pin to Tabs" : "Unpin from Tabs", action: pin)
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
            Text(row.name).font(PiperTheme.paperSerif(Metrics.treeFileSize)).foregroundStyle(color)
                .lineLimit(1).truncationMode(.middle)
        }
    }

    @ViewBuilder private var meta: some View {
        Group {
            if row.isFolder {
                if !row.isOtherRoot {
                    Text(tabColor != nil ? "Tab · \(row.count)" : "\(row.count)")
                        .foregroundStyle(tabColor != nil ? PiperTheme.paperMuted : PiperTheme.paperFaint)
                }
            } else if onDesk {
                Text("on the desk").fontWeight(.medium).foregroundStyle(PiperTheme.brand)
            } else if let date {
                Text(RowTime.text(date)).foregroundStyle(PiperTheme.paperFaint)
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

    @ViewBuilder private var selectionBar: some View {
        if selected {
            RoundedRectangle(cornerRadius: Metrics.selectionBarWidth)
                .fill(marks?.feedFocused == true ? PiperTheme.brand : PiperTheme.paperBar)
                .frame(width: Metrics.selectionBarWidth)
                .padding(.vertical, Metrics.selectionBarInset)
        }
    }

    @ViewBuilder private var slot: some View {
        if onDesk {
            RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                .strokeBorder(PiperTheme.paperSlot, style: StrokeStyle(lineWidth: Metrics.markLine, dash: Metrics.slotDash))
                .padding(Metrics.markLine)
        }
    }

    @ViewBuilder private var menu: some View {
        if row.isFolder {
            Button(tabColor == nil ? "Pin to Tabs" : "Unpin from Tabs", action: pin)
        }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: row.id)]) }
        if let removeRoot {
            Divider()
            Button("Remove Folder", action: removeRoot)
        }
    }

    private var accessibilityTitle: String {
        guard row.isFolder else { return row.name }
        let files = row.count == 1 ? "1 file" : "\(row.count) files"
        if row.isOtherRoot { return "\(row.name), folder" }
        return tabColor != nil ? "\(row.name), folder, \(files), has a tab" : "\(row.name), folder, \(files)"
    }
}

/// A swatch of a tab color on a pinned folder.
private struct Swatch: View {
    let color: TabColor
    let selected: Bool
    let action: () -> Void

    private typealias Metrics = AppDefaults.Papers

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(PiperTheme.tabFill(color))
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
