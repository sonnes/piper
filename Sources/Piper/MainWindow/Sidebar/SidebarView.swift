import AppKit
import PiperTree
import SwiftUI
import Vault

/// The source list of the main window.
///
/// The pane holds two groups. The first holds the home page and the capture
/// inbox, which belong to no folder. The second holds the folder tree of the
/// vault.
///
/// The pane paints no background, so the sidebar material of the split view item
/// shows through. A row reports its selection upward and touches no other pane.
struct SidebarView: View {

    // MARK: Properties

    @Bindable var model: AppModel
    /// The paths of the open folders. The host owns the set, so the expansion
    /// survives a hidden sidebar.
    @Binding var expanded: Set<String>
    /// The row that carries the selection fill.
    let selection: SidebarSelection
    /// Called with the row the reader clicks.
    let select: (SidebarSelection) -> Void

    /// The whole tree, including the root.
    ///
    /// A node holds its parent weakly, so the root has to stay alive. Passing
    /// only `root.children` releases the root, and every top-level `indexPath`
    /// then reads as the same value.
    private var root: Node {
        PathTreeBuilder.tree(paths: model.files.map(\.relativePath), folders: model.folders)
    }

    /// The captures that are still open.
    private var openCaptures: Int {
        model.store.notes.filter { !$0.isDone }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupHeader("Smart Feeds", top: AppDefaults.Sidebar.firstHeaderTopMargin)
            smartRows
            groupHeader((model.wikiPath as NSString).abbreviatingWithTildeInPath,
                        top: AppDefaults.Sidebar.headerTopMargin)
            list
            if !model.wikiProblems.isEmpty { problems }
        }
    }

    // MARK: Smart rows

    private var smartRows: some View {
        VStack(spacing: 0) {
            SmartRow(title: "Home", icon: "house", count: 0,
                     selected: selection == .home) { select(.home) }
            SmartRow(title: "Inbox", icon: "tray", count: openCaptures,
                     selected: selection == .inbox) { select(.inbox) }
        }
        .padding(.horizontal, AppDefaults.Sidebar.rowInset)
    }

    // MARK: Header

    /// The group header of the source list. The first one names the
    /// rows that belong to no folder. The second names the vault, because a
    /// vault is what a folder belongs to.
    private func groupHeader(_ title: String, top: CGFloat) -> some View {
        Text(title)
            .font(PiperTheme.ui(AppDefaults.Sidebar.headerFontSize, weight: .semibold))
            .foregroundStyle(PiperTheme.secondary)
            .lineLimit(1)
            .truncationMode(.head)
            .padding(.leading, AppDefaults.Sidebar.rowInset + AppDefaults.Sidebar.disclosureWidth)
            .padding(.trailing, AppDefaults.Sidebar.rowInset)
            .padding(.top, top)
            .padding(.bottom, AppDefaults.Sidebar.headerBottomMargin)
    }

    // MARK: Tree

    private var list: some View {
        ScrollView {
            SidebarRows(parent: root, expanded: $expanded, model: model,
                        selection: selection, select: select)
                .padding(.horizontal, AppDefaults.Sidebar.rowInset)
        }.scrollIndicators(.automatic)
    }

    // MARK: Problems

    private var problems: some View {
        DisclosureGroup("\(model.wikiProblems.count) file warnings") {
            Text(model.wikiProblems.joined(separator: "\n")).textSelection(.enabled).font(PiperTheme.ui(10)).padding(.top, 5)
        }.font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.warning).padding(12)
    }

    // MARK: Functions

    /// Every folder path in the files, at every level.
    static func folders(of files: [VaultFile], including empty: [String] = []) -> Set<String> {
        var result = Set(empty)
        for document in files {
            var folder = document.folder
            while !folder.isEmpty {
                result.insert(folder)
                folder = (folder as NSString).deletingLastPathComponent
            }
        }
        return result
    }
}

/// A row that stands for no folder: the home page or the capture inbox.
private struct SmartRow: View {
    let title: String
    let icon: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Color.clear.frame(width: AppDefaults.Sidebar.disclosureWidth)
                Image(systemName: icon)
                    .font(.system(size: AppDefaults.Sidebar.iconPointSize))
                    .foregroundStyle(PiperTheme.accent)
                    .frame(width: AppDefaults.Sidebar.imageSize.width, height: AppDefaults.Sidebar.imageSize.height)
                    .padding(.trailing, AppDefaults.Sidebar.imageMarginRight)
                Text(title).font(PiperTheme.ui(AppDefaults.Sidebar.fontSize)).foregroundStyle(PiperTheme.ink)
                Spacer(minLength: 0)
                if count > 0 { SidebarBadge(count: count) }
            }
            .frame(height: AppDefaults.Sidebar.rowHeight).frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(selected ? PiperTheme.rowSelection : .clear,
                        in: RoundedRectangle(cornerRadius: AppDefaults.Sidebar.rowCornerRadius))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// An unread count.
private struct SidebarBadge: View {
    let count: Int

    var body: some View {
        Text(count.formatted())
            .font(PiperTheme.ui(11, weight: .semibold).monospacedDigit())
            .foregroundStyle(PiperTheme.badgeText)
            .padding(.leading, AppDefaults.Sidebar.countPadding.left)
            .padding(.trailing, AppDefaults.Sidebar.countPadding.right)
            .padding(.top, AppDefaults.Sidebar.countPadding.top)
            .padding(.bottom, AppDefaults.Sidebar.countPadding.bottom)
            .background(PiperTheme.badge, in: RoundedRectangle(cornerRadius: AppDefaults.Sidebar.countCornerRadius))
            .padding(.leading, AppDefaults.Sidebar.countMarginLeft)
    }
}

/// One row of the tree, with the node it draws. The path identifies it, because
/// a path is unique in one vault.
private struct SidebarEntry: Identifiable {
    let node: Node
    let item: PathItem
    var id: String { item.path }
}

/// One level of the folder tree.
private struct SidebarRows: View {

    // MARK: Properties

    /// The node whose children this level draws. Holding the parent keeps that
    /// branch of the tree alive.
    let parent: Node
    @Binding var expanded: Set<String>
    let model: AppModel
    let selection: SidebarSelection
    let select: (SidebarSelection) -> Void
    var depth = 0

    private var entries: [SidebarEntry] {
        parent.children.compactMap { node in
            (node.representedObject as? PathItem).map { SidebarEntry(node: node, item: $0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                row(node: entry.node, item: entry.item)
                if entry.item.isFolder, expanded.contains(entry.item.path) {
                    SidebarRows(parent: entry.node, expanded: $expanded, model: model,
                                selection: selection, select: select, depth: depth + 1)
                }
            }
        }
    }

    // MARK: Functions

    private func row(node: Node, item: PathItem) -> some View {
        let selected = item.isFolder ? selection == .folder(item.path) : model.selectedDocument == item.path
        let open = expanded.contains(item.path)
        return Button {
            if item.isFolder {
                if open { expanded.remove(item.path) } else { expanded.insert(item.path) }
                select(.folder(item.path))
            } else {
                model.openDocument(item.path)
            }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.system(size: AppDefaults.Sidebar.disclosurePointSize, weight: .semibold))
                    .foregroundStyle(PiperTheme.secondary)
                    .opacity(node.children.isEmpty ? 0 : 1)
                    .frame(width: AppDefaults.Sidebar.disclosureWidth, alignment: .leading)
                Image(systemName: item.isFolder ? "folder" : "doc.text")
                    .font(.system(size: AppDefaults.Sidebar.iconPointSize))
                    .foregroundStyle(item.isFolder ? PiperTheme.accent : PiperTheme.secondary)
                    .frame(width: AppDefaults.Sidebar.imageSize.width, height: AppDefaults.Sidebar.imageSize.height)
                    .padding(.trailing, AppDefaults.Sidebar.imageMarginRight)
                Text(item.name).font(PiperTheme.ui(AppDefaults.Sidebar.fontSize)).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(PiperTheme.ink)
                Spacer(minLength: 0)
                if item.isFolder { SidebarBadge(count: item.count) }
            }
            .padding(.leading, CGFloat(depth) * AppDefaults.Sidebar.indent)
            .frame(height: AppDefaults.Sidebar.rowHeight).frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(selected ? PiperTheme.rowSelection : .clear,
                        in: RoundedRectangle(cornerRadius: AppDefaults.Sidebar.rowCornerRadius))
        }.buttonStyle(.plain).focusEffectDisabled().help(item.path)
            .accessibilityLabel(item.isFolder ? "\(item.name) folder" : item.name)
            .contextMenu {
                Button("Reveal in Finder") {
                    if let url = try? model.vault.containedURL(item.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
    }
}
