import AppKit
import SwiftUI
import Vault

/// How the file list orders its rows.
enum FileSort: String, CaseIterable {
    case name = "Name", modified = "Date"

    var title: String { rawValue }
}

/// The middle pane of the main window: the files of one folder.
///
/// Each row is a `TimelineCell`. A selected row takes the accent while the list
/// has focus. A file needs no frontmatter. Where a file carries none, the title
/// falls back to the file name and the summary to the first lines of the text.
struct FileListView: View {

    // MARK: Properties

    @Bindable var model: AppModel
    /// A nil folder shows the results of a vault-wide search from Home.
    let folder: String?
    let selectFile: (VaultFile) -> Void

    @AppStorage(AppDefaults.Key.fileSort) private var sort = FileSort.name
    @FocusState private var searching: Bool

    private var isSearching: Bool {
        !model.wikiQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Search filters the current list.
    private var files: [VaultFile] {
        let folderFiles = model.filteredFiles(in: folder)
        switch sort {
        case .name:
            return folderFiles.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .modified:
            return folderFiles.sorted { $0.modifiedAt > $1.modifiedAt }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                searchField
                sortMenu
            }
            .padding(.leading, AppDefaults.ListSearch.horizontalInset)
            .padding(.trailing, AppDefaults.ListSearch.horizontalInset - 4)
            .padding(.vertical, AppDefaults.ListSearch.verticalInset)
            List(selection: Binding<String?>(get: { model.selectedDocument }, set: { path in
                if let file = files.first(where: { $0.id == path }) { selectFile(file) }
            })) {
                ForEach(files) { file in
                    TimelineCell(file: file, rootName: model.vault.root.lastPathComponent, isUnread: model.isUnread(file))
                        .tag(file.id)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .help(file.relativePath)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(file.title)
                        .accessibilityValue(model.isUnread(file) ? "Unread" : "Read")
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .overlay {
                if files.isEmpty {
                    if isSearching {
                        EmptyPane(title: "No Results", detail: "Try another word.")
                    } else {
                        EmptyPane(title: "No Files", detail: "Files you add to this folder appear here.")
                    }
                }
            }
            .accessibilityLabel("Files")
        }
        .background(PiperTheme.page)
    }

    // MARK: Parts

    /// Name or Date. The window title names the list, so the pane has no title.
    private var sortMenu: some View {
        Menu {
                Picker("Sort By", selection: $sort) {
                    ForEach(FileSort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12))
                    .foregroundStyle(PiperTheme.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .tint(PiperTheme.secondary)
            .frame(width: 22, height: 22)
            .help("Sort Files")
            .accessibilityLabel("Sort Files")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(PiperTheme.faint)
            TextField("Search", text: $model.wikiQuery)
                .textFieldStyle(.plain)
                .font(PiperTheme.ui(13))
                .focused($searching)
                .accessibilityLabel("Search \(title)")
            if !model.wikiQuery.isEmpty {
                Button { model.wikiQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(PiperTheme.faint) }
                    .buttonStyle(.plain).accessibilityLabel("Clear file search")
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(PiperTheme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: PiperTheme.radius))
        .overlay {
            RoundedRectangle(cornerRadius: PiperTheme.radius + 2)
                .strokeBorder(searching ? PiperTheme.focusRing : .clear, lineWidth: 3)
                .padding(-2)
        }
    }

    private var title: String {
        guard let folder else { return "All Files" }
        return folder.isEmpty ? model.vault.root.lastPathComponent : (folder as NSString).lastPathComponent
    }
}
