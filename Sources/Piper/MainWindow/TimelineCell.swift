import SwiftUI
import Vault

/// Markdown read as one line of text.
enum SummaryText {

    /// Drops the markup from a body, so that a row shows the words alone.
    ///
    /// A link reads as its label. Emphasis, code marks, quote marks, and list
    /// markers carry nothing in one line, so they go.
    static func plain(_ markdown: String) -> String {
        var text = markdown
        for (pattern, replacement) in [
            (#"\[\[[^\]|]+\|([^\]]+)\]\]"#, "$1"),
            (#"\[\[([^\]]+)\]\]"#, "$1"),
            (#"!?\[([^\]]*)\]\([^)]*\)"#, "$1"),
            (#"(?m)^\s*[-*+]\s+"#, ""),
            (#"[*_`>]"#, ""),
            (#"\s+"#, " ")
        ] {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}

/// One file row.
///
/// The metrics come from `AppDefaults.Timeline`. The row shows the unread dot,
/// then the text, with the date at the trailing edge of the last line. One cell type draws every list of files, on the home page and in
/// the browser, so the two cannot drift apart.
struct TimelineCell: View {

    // MARK: Properties

    let file: VaultFile
    /// The name of the Wiki folder. A file in the root shows it in place of a folder.
    let rootName: String
    let isUnread: Bool

    /// The `description` key of the frontmatter, or the first prose of the file.
    ///
    /// Heading lines drop out, because a heading repeats the title that the row
    /// already shows. The summary is plain text, so the row shows no markup.
    private var summary: String {
        if !file.isMarkdown {
            if FilePresentation(file) == .text {
                return String(file.body.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(240))
            }
            return FilePresentation.typeName(for: file) + " · " +
                ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)
        }
        guard file.summary.isEmpty else { return SummaryText.plain(file.summary) }
        let prose = file.body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .joined(separator: " ")
        return String(SummaryText.plain(prose).prefix(240))
    }

    private var folder: String {
        file.folder.isEmpty ? rootName : file.folder
    }

    /// A file of the last day reads as a relative time. An older one reads as a date.
    private var date: String {
        if Date().timeIntervalSince(file.modifiedAt) < 24 * 60 * 60 {
            return file.modifiedAt.formatted(.relative(presentation: .named))
        }
        return file.modifiedAt.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        TimelineRow(title: file.title, summary: summary, source: folder, date: date,
                    showsDot: isUnread, emphasizesTitle: isUnread)
            .accessibilityValue(isUnread ? "Unread" : "Read")
    }
}

/// A fixed-height timeline row. The title and summary share three lines.
struct TimelineRow: View {
    let title: String
    let summary: String
    let source: String
    let date: String
    let showsDot: Bool
    var emphasizesTitle = true
    var isDone = false

    private var preview: AttributedString {
        var heading = AttributedString(title)
        heading.font = PiperTheme.ui(AppDefaults.FontSize.large, weight: emphasizesTitle ? .semibold : .regular)
        if isDone { heading.strikethroughStyle = .single }
        var excerpt = AttributedString(summary.isEmpty ? "" : "\n" + summary)
        excerpt.font = PiperTheme.ui(AppDefaults.FontSize.large)
        excerpt.foregroundColor = .secondary
        return heading + excerpt
    }

    var body: some View {
        let metrics = AppDefaults.Timeline.self
        HStack(alignment: .top, spacing: metrics.unreadCircleMarginRight) {
            Circle()
                .fill(showsDot ? PiperTheme.accent : .clear)
                .frame(width: metrics.unreadCircleDimension, height: metrics.unreadCircleDimension)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 0) {
                Text(preview)
                    .lineLimit(metrics.titleNumberOfLines)
                    .frame(height: metrics.textHeight, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .firstTextBaseline, spacing: metrics.dateMarginLeft) {
                    Text(source).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Text(date).fixedSize()
                }
                .font(PiperTheme.ui(AppDefaults.FontSize.small, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(.top, metrics.cellPadding.top)
        .padding(.leading, metrics.cellPadding.left)
        .padding(.bottom, metrics.cellPadding.bottom)
        .padding(.trailing, metrics.cellPadding.right)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
