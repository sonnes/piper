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
/// The row shows the unread dot in a gutter, the title, a summary that starts
/// with the date, and the folder. One cell type draws every list of files, on
/// the home page and in the browser, so the two cannot drift apart.
struct TimelineCell: View {

    // MARK: Properties

    let file: VaultFile
    /// The name of the root folder. A file in the root shows it in place of a folder.
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
        file.folder.isEmpty ? rootName : (file.folder as NSString).lastPathComponent
    }

    /// The clock time today, and the date before today.
    private var date: String {
        Calendar.current.isDateInToday(file.modifiedAt)
            ? file.modifiedAt.formatted(date: .omitted, time: .shortened)
            : file.modifiedAt.formatted(.dateTime.month(.abbreviated).day())
    }

    var body: some View {
        TimelineRow(title: file.title, summary: summary, source: folder, date: date, showsDot: isUnread)
            .accessibilityValue(isUnread ? "Unread" : "Read")
    }
}

/// A list row with a title, a two-line summary, and a source line.
struct TimelineRow: View {
    let title: String
    let summary: String
    let source: String
    let date: String
    let showsDot: Bool

    @Environment(\.backgroundProminence) private var prominence

    private var selected: Bool { prominence == .increased }

    private var preview: Text {
        Text(date).foregroundStyle(.primary) + Text("  " + summary).foregroundStyle(.secondary)
    }

    var body: some View {
        let metrics = AppDefaults.Timeline.self
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Circle()
                .fill(showsDot ? (selected ? Color.white : PiperTheme.accent) : .clear)
                .frame(width: metrics.unreadCircleDimension, height: metrics.unreadCircleDimension)
                .frame(width: metrics.gutterWidth)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PiperTheme.ui(13, weight: .semibold))
                    .lineLimit(1)
                preview
                    .font(PiperTheme.ui(12))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Label(source, systemImage: "folder")
                    .labelStyle(SourceLabelStyle())
                    .padding(.top, 1)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(.vertical, metrics.verticalPadding)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SourceLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 10))
            configuration.title.font(PiperTheme.ui(11)).lineLimit(1).truncationMode(.middle)
        }
        .foregroundStyle(.tertiary)
    }
}
