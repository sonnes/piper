import SwiftUI
import Vault

/// The date line and, for a file without a heading, the title.
///
/// The window title names the folder, so the header repeats neither the folder
/// nor the file name. The date line also says when the editor holds a change
/// that the file on disk does not.
struct DetailHeader: View {
    let file: VaultFile
    let hasChanges: Bool

    private var bodyHasTitle: Bool {
        file.body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("# ")
    }

    private var dateLine: String {
        let date = file.modifiedAt.formatted(date: .long, time: .shortened)
        return hasChanges ? date + " · Edited" : date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(dateLine)
                .font(PiperTheme.ui(11))
                .foregroundStyle(PiperTheme.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Modified \(dateLine)")
            if !bodyHasTitle {
                Text(file.title)
                    .font(PiperTheme.ui(AppDefaults.Reader.titleSize, weight: .bold))
                    .foregroundStyle(PiperTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .frame(maxWidth: AppDefaults.Reader.columnWidth, alignment: .leading)
        .padding(.horizontal, AppDefaults.Reader.horizontalInset)
        .padding(.top, AppDefaults.Reader.topInset)
        .frame(maxWidth: .infinity)
    }
}

/// The detail pane when nothing is selected.
struct NoSelection: View {
    var body: some View {
        EmptyPane(title: "No Selection")
            .background(PiperTheme.page)
    }
}
