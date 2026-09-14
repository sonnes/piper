import AppKit
import PiperTree
import SwiftUI
import Vault

/// The source list of the main window.
///
/// The pane holds the search field, the folder tree of the vault, the file
/// warnings, and the footer that names the vault. A folder row reports its path
/// through `selectFolder`. A file row opens the document.
struct SidebarView: View {

    // MARK: Properties

    @Bindable var model: AppModel
    /// The paths of the open folders. The host owns the set, so the expansion
    /// survives a hidden sidebar and focus mode.
    @Binding var expanded: Set<String>
    @FocusState.Binding var searching: Bool
    /// Called with the path of a folder row when the reader clicks it.
    let selectFolder: (String) -> Void

    private var tree: [Node] {
        PathTreeBuilder.tree(paths: model.files.map(\.relativePath)).children
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            search
            list
            if !model.wikiProblems.isEmpty { problems }
            Rule()
            footer
        }.background(PiperTheme.surface)
    }

    // MARK: Header and search

    private var header: some View {
        HStack(spacing: 2) {
            Text(model.wikiQuery.isEmpty ? "FILES" : "\(model.filteredFiles.count) RESULTS")
                .font(PiperTheme.ui(10.5, weight: .semibold)).tracking(0.4).foregroundStyle(PiperTheme.secondary)
            Spacer()
            if model.wikiQuery.isEmpty {
                IconButton(title: expanded.isEmpty ? "Expand Folders" : "Collapse Folders", icon: "list.bullet.indent") {
                    expanded = expanded.isEmpty ? Self.folders(of: model.files) : []
                }
            }
            IconButton(title: "Refresh Wiki · ⌘R", icon: "arrow.clockwise") { model.reload() }.disabled(model.loading)
        }
        .padding(.leading, 14).padding(.trailing, 6).frame(height: 30).padding(.top, 44)
    }

    private var search: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(PiperTheme.secondary)
            TextField("Search", text: $model.wikiQuery).textFieldStyle(.plain).font(PiperTheme.ui(12))
                .focused($searching).accessibilityLabel("Search Wiki")
                .onSubmit { if let first = model.filteredFiles.first { model.openDocument(first.id) } }
            if !model.wikiQuery.isEmpty {
                Button { model.wikiQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(PiperTheme.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear Wiki Search")
            } else { Text("⌘O").font(PiperTheme.ui(10)).foregroundStyle(PiperTheme.faint) }
        }
        .padding(.horizontal, 8).frame(height: 28)
        .overlay(alignment: .bottom) { Rectangle().fill(searching ? PiperTheme.accent : PiperTheme.rule).frame(height: 1) }
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    // MARK: Tree and results

    private var list: some View {
        ScrollView {
            if model.wikiQuery.isEmpty {
                SidebarRows(nodes: tree, expanded: $expanded, model: model, selectFolder: selectFolder)
                    .padding(.horizontal, 8)
            } else if model.filteredFiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No matching notes").font(PiperTheme.ui(12, weight: .medium))
                    Text("Try a title, phrase, or folder name.").font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(model.filteredFiles) { document in
                        let selected = model.selectedDocument == document.id
                        Button { model.openDocument(document.id) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(document.title).font(PiperTheme.ui(12, weight: .medium)).lineLimit(2)
                                Text(excerpt(document)).font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary).lineLimit(3)
                                Text(document.folder.isEmpty ? "Wiki" : document.folder).font(PiperTheme.ui(10)).foregroundStyle(PiperTheme.faint)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                .background(selected ? PiperTheme.selection : .clear, in: RoundedRectangle(cornerRadius: PiperTheme.radius))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 8)
            }
        }.scrollIndicators(.automatic)
    }

    // MARK: Problems and footer

    private var problems: some View {
        DisclosureGroup("\(model.wikiProblems.count) file warnings") {
            Text(model.wikiProblems.joined(separator: "\n")).textSelection(.enabled).font(PiperTheme.ui(10)).padding(.top, 5)
        }.font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.warning).padding(12)
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Image(systemName: "externaldrive").font(.system(size: 14)).foregroundStyle(PiperTheme.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.vault.root.lastPathComponent).font(PiperTheme.ui(12, weight: .medium)).lineLimit(1)
                Text((model.wikiPath as NSString).abbreviatingWithTildeInPath).font(PiperTheme.ui(10.5)).foregroundStyle(PiperTheme.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Menu {
                Button("Choose Wiki Folder…") { model.chooseWiki() }
                Button("Reveal Wiki in Finder") { NSWorkspace.shared.open(model.vault.root) }
                Divider()
                Button("Settings…") { model.route = "settings" }
            } label: { Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(PiperTheme.secondary) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Wiki Folder Options")
        }.padding(.horizontal, 14).frame(height: 52)
    }

    // MARK: Functions

    /// Every folder path in the files, at every level.
    static func folders(of files: [VaultFile]) -> Set<String> {
        var result: Set<String> = []
        for document in files {
            var folder = document.folder
            while !folder.isEmpty {
                result.insert(folder)
                folder = (folder as NSString).deletingLastPathComponent
            }
        }
        return result
    }

    /// The text under a search result. The part around the match comes first.
    private func excerpt(_ document: VaultFile) -> String {
        let text = document.body.replacingOccurrences(of: "\n", with: " ")
        let query = model.wikiQuery.trimmingCharacters(in: .whitespaces)
        if let range = text.range(of: query, options: .caseInsensitive) {
            let start = text.index(range.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
            return (start == text.startIndex ? "" : "…") + String(text[start...].prefix(150))
        }
        return document.summary.isEmpty ? String(text.prefix(130)) : document.summary
    }
}

/// One level of the folder tree.
private struct SidebarRows: View {

    // MARK: Properties

    let nodes: [Node]
    @Binding var expanded: Set<String>
    let model: AppModel
    let selectFolder: (String) -> Void
    var depth = 0

    var body: some View {
        VStack(spacing: 1) {
            ForEach(nodes, id: \.indexPath) { node in
                if let item = node.representedObject as? PathItem {
                    row(node: node, item: item)
                    if item.isFolder, expanded.contains(item.path) {
                        SidebarRows(nodes: node.children, expanded: $expanded, model: model,
                                    selectFolder: selectFolder, depth: depth + 1)
                    }
                }
            }
        }
    }

    // MARK: Functions

    private func row(node: Node, item: PathItem) -> some View {
        let selected = !item.isFolder && model.selectedDocument == item.path
        let open = expanded.contains(item.path)
        return Button {
            if item.isFolder {
                if open { expanded.remove(item.path) } else { expanded.insert(item.path) }
                selectFolder(item.path)
            } else {
                model.openDocument(item.path)
            }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(PiperTheme.secondary)
                    .opacity(item.isFolder ? 1 : 0).frame(width: 12, alignment: .leading)
                Image(systemName: item.isFolder ? "folder" : "doc.text")
                    .font(.system(size: 13))
                    .foregroundStyle(item.isFolder ? PiperTheme.accent : PiperTheme.secondary)
                    .frame(width: AppDefaults.Sidebar.imageSize.width, height: AppDefaults.Sidebar.imageSize.height)
                    .padding(.trailing, AppDefaults.Sidebar.imageMarginRight)
                Text(item.name).font(PiperTheme.ui(13)).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(item.isFolder || selected ? PiperTheme.ink : PiperTheme.secondary)
                Spacer(minLength: 0)
                if item.isFolder { badge(item.count) }
            }
            .padding(.leading, CGFloat(depth) * 14 + 6).padding(.trailing, 6)
            .frame(height: 24).frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(selected ? PiperTheme.selection : .clear, in: RoundedRectangle(cornerRadius: PiperTheme.radius))
            .overlay(alignment: .leading) { if selected && PiperTheme.isPage { Rectangle().fill(PiperTheme.accent).frame(width: 2) } }
        }.buttonStyle(.plain).help(item.path)
            .accessibilityLabel(item.isFolder ? "\(item.name) folder" : item.name)
            .contextMenu {
                Button("Reveal in Finder") {
                    if let url = try? model.vault.containedURL(item.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
    }

    /// The count of the files under a folder.
    private func badge(_ count: Int) -> some View {
        Text(count.formatted())
            .font(PiperTheme.ui(11, weight: .semibold).monospacedDigit())
            .foregroundStyle(PiperTheme.page)
            .padding(.leading, AppDefaults.Sidebar.countPadding.left)
            .padding(.trailing, AppDefaults.Sidebar.countPadding.right)
            .padding(.top, AppDefaults.Sidebar.countPadding.top)
            .padding(.bottom, AppDefaults.Sidebar.countPadding.bottom)
            .background(PiperTheme.control, in: RoundedRectangle(cornerRadius: AppDefaults.Sidebar.countCornerRadius))
            .padding(.leading, AppDefaults.Sidebar.countMarginLeft)
    }
}
