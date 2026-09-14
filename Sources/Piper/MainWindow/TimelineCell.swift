import SwiftUI
import Vault

/// One file row.
///
/// The metrics come from `AppDefaults.Timeline`. One cell type draws every list
/// of files, on the home page and in the browser, so the two cannot drift apart.
struct TimelineCell: View {

    // MARK: Properties

    let file: VaultFile
    /// The name of the Wiki folder. A file in the root shows it in place of a folder.
    let rootName: String
    /// Draws the dot in the gutter. Piper keeps no read state for a file, so the
    /// caller decides what the dot means in its list.
    let showsDot: Bool
    /// Fills the row, for the file the browser has open.
    var isSelected = false

    /// The `description` key of the frontmatter, or the first prose of the file.
    ///
    /// Heading lines drop out, because a heading repeats the title that the row
    /// already shows.
    private var summary: String {
        guard file.summary.isEmpty else { return file.summary }
        let prose = file.body
            .split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return String(prose.prefix(240))
    }

    private var folder: String {
        file.folder.isEmpty ? rootName : file.folder
    }

    /// A file of the last day reads as a relative time. An older one reads as a date.
    private var date: String {
        if Date().timeIntervalSince(file.modifiedAt) < 24 * 60 * 60 {
            return file.modifiedAt.formatted(.relative(presentation: .named))
        }
        return file.modifiedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        let metrics = AppDefaults.Timeline.self
        HStack(alignment: .top, spacing: 0) {
            Circle()
                .fill(showsDot ? PiperTheme.accent : .clear)
                .frame(width: metrics.unreadCircleDimension, height: metrics.unreadCircleDimension)
                .padding(.top, 3)
                .padding(.trailing, metrics.unreadCircleMarginRight)
            VStack(alignment: .leading, spacing: 0) {
                Text(file.title)
                    .font(PiperTheme.ui(AppDefaults.FontSize.large, weight: .semibold))
                    .lineLimit(metrics.titleNumberOfLines)
                    .padding(.bottom, metrics.titleBottomMargin)
                if !summary.isEmpty {
                    Text(summary)
                        .font(PiperTheme.ui(AppDefaults.FontSize.large))
                        .foregroundStyle(PiperTheme.secondary)
                        .lineLimit(2)
                }
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(folder)
                        .font(PiperTheme.ui(AppDefaults.FontSize.small, weight: .bold))
                        .foregroundStyle(PiperTheme.secondary)
                    Text(date)
                        .font(PiperTheme.ui(AppDefaults.FontSize.small, weight: .bold))
                        .foregroundStyle(PiperTheme.faint)
                        .padding(.leading, metrics.dateMarginLeft)
                }
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .multilineTextAlignment(.leading)
        .padding(.top, metrics.cellPadding.top)
        .padding(.leading, metrics.cellPadding.left)
        .padding(.bottom, metrics.cellPadding.bottom)
        .padding(.trailing, metrics.cellPadding.right)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(isSelected ? PiperTheme.selection : .clear)
    }
}
