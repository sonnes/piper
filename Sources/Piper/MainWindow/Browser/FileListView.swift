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
/// Each row is a `TimelineCell`. Rows carry no dividing line, and a selected
/// row takes the system selection fill. A file needs no frontmatter. Where a
/// file carries none, the title falls back to the file name and the summary
/// falls back to the first lines of the text.
struct FileListView: View {

    // MARK: Properties

    @Bindable var model: AppModel
    /// The folder path from the vault root. The empty path holds the root files.
    let folder: String
    let selectFile: (VaultFile) -> Void

    @AppStorage(AppDefaults.Key.fileSort) private var sort = FileSort.name

    private var searching: Bool {
        !model.wikiQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The rows of the list. A search reads the whole vault.
    private var files: [VaultFile] {
        let folderFiles = searching ? model.filteredFiles : model.files.filter { $0.folder == folder }
        switch sort {
        case .name:
            return folderFiles.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .modified:
            return folderFiles.sorted { $0.modifiedAt > $1.modifiedAt }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            List(selection: Binding<String?>(get: { model.selectedDocument }, set: { path in
                if let file = files.first(where: { $0.id == path }) { selectFile(file) }
            })) {
                ForEach(files) { file in
                    TimelineCell(file: file, rootName: model.vault.root.lastPathComponent, isUnread: model.isUnread(file))
                        .tag(file.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
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
                    Text(searching ? "No matching files" : "No files in this folder")
                        .font(PiperTheme.ui(AppDefaults.FontSize.small))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Files")
        }
        .background(PiperTheme.page)
    }

    // MARK: Parts

    /// The title block over the list.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(PiperTheme.ui(13, weight: .bold))
                    .foregroundStyle(PiperTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(files.filter { model.isUnread($0) }.count) unread")
                    .font(PiperTheme.ui(11))
                    .foregroundStyle(PiperTheme.secondary)
            }
            Spacer(minLength: 8)
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(FileSort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11))
                    .foregroundStyle(PiperTheme.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Sort Files")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
    }

    private var title: String {
        if searching { return "Search Results" }
        return folder.isEmpty ? model.vault.root.lastPathComponent : (folder as NSString).lastPathComponent
    }

}
