import SwiftUI
import Vault

/// The bar over the file.
///
/// It is 68 points high, with a one-point bottom border. It shows the folder,
/// because a folder is what a file belongs to here.
struct DetailHeader: View {

    // MARK: Properties

    let file: VaultFile
    let rootName: String

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.folder.isEmpty ? rootName : file.folder)
                        .font(PiperTheme.ui(13, weight: .bold))
                        .foregroundStyle(PiperTheme.feedLink)
                        .lineLimit(1)
                    Text(file.name)
                        .font(PiperTheme.ui(12))
                        .foregroundStyle(PiperTheme.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Self.byteFormatter.string(fromByteCount: Int64(file.size)))
                    Text(file.modifiedAt.formatted(date: .long, time: .omitted))
                }
                .font(PiperTheme.ui(12))
                .foregroundStyle(PiperTheme.secondary)
            }
            .padding(.horizontal, 32)
            .frame(height: 68)
            Rule()
        }
        .background(PiperTheme.page)
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
