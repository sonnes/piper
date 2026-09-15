import SwiftUI
import Vault

/// The document's source and title, aligned with the reading column.
struct DetailHeader: View {
    let file: VaultFile
    let rootName: String

    private var bodyHasTitle: Bool {
        file.body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("# ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.folder.isEmpty ? rootName : rootName + " / " + file.folder)
                        .font(PiperTheme.ui(13, weight: .bold))
                    Text(file.name)
                        .font(PiperTheme.ui(12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(PiperTheme.secondary)
                Spacer(minLength: 12)
                Image(systemName: "doc.text")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(PiperTheme.secondary)
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
            }
            .frame(height: AppDefaults.Reader.headerHeight)
            Rule()
            if !bodyHasTitle {
                Text(file.title)
                    .font(PiperTheme.ui(AppDefaults.Reader.titleSize, weight: .bold))
                    .foregroundStyle(PiperTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(file.modifiedAt.formatted(date: .abbreviated, time: .shortened).uppercased())
                .font(PiperTheme.ui(11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(PiperTheme.secondary)
                .padding(.top, 6)
        }
        .frame(maxWidth: AppDefaults.Reader.columnWidth, alignment: .leading)
        .padding(.horizontal, AppDefaults.Reader.horizontalInset)
        .padding(.top, AppDefaults.Reader.topInset)
        .frame(maxWidth: .infinity)
    }
}

/// The bar under the file.
///
/// It shows the path, the length, and whether the editor holds a change that
/// the file on disk does not.
struct DetailStatusBar: View {

    // MARK: Properties

    let path: String
    let words: Int
    let hasChanges: Bool

    var body: some View {
        VStack(spacing: 0) {
            Rule()
            HStack(spacing: 14) {
                Text(path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path)
                Spacer(minLength: 8)
                Text("\(words) \(words == 1 ? "word" : "words")")
                Text(hasChanges ? "Unsaved" : "Saved")
                    .foregroundStyle(hasChanges ? PiperTheme.accent : PiperTheme.secondary)
            }
            .font(PiperTheme.ui(11))
            .foregroundStyle(PiperTheme.secondary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(PiperTheme.statusBar)
        }
    }
}
