import AppKit
import SwiftUI
import Vault

/// The middle pane of the main window: the files of one folder.
///
/// Each row is a `TimelineCell`. A file needs no frontmatter. Where
/// a file carries none, the title falls back to the file name and the summary
/// falls back to the first lines of the text.
struct FileListView: View {

    // MARK: Properties

    @Bindable var model: AppModel
    /// The folder path from the vault root. The empty path holds the root files.
    let folder: String
    let selectFile: (VaultFile) -> Void

    private var files: [VaultFile] {
        model.files.filter { $0.folder == folder }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            if files.isEmpty {
                Text("No files in this folder.")
                    .font(PiperTheme.ui(AppDefaults.FontSize.small))
                    .foregroundStyle(PiperTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                        if index > 0 { Rule() }
                        cell(file)
                    }
                }
            }
        }
        .scrollIndicators(.automatic)
        .background(PiperTheme.page)
    }

    // MARK: Functions

    private func cell(_ file: VaultFile) -> some View {
        let selected = model.selectedDocument == file.id
        return Button { selectFile(file) } label: {
            TimelineCell(file: file,
                         rootName: model.vault.root.lastPathComponent,
                         showsDot: selected,
                         isSelected: selected)
        }
        .buttonStyle(.plain)
        .help(file.relativePath)
        .accessibilityLabel(file.title)
    }
}
