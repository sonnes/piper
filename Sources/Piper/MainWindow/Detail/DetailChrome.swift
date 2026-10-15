import AppKit
import SwiftUI
import Vault

/// The byline over a Markdown file and, for a file without a heading, the title.
///
/// The byline matches the reader page: the date and the reading time. The
/// window title names the folder, so the header repeats neither the folder
/// nor the file name. When the editor holds a change that the file on disk
/// does not, the byline says so and shows a Save button. The header scrolls
/// with the page.
struct DetailHeader: View {
    let file: VaultFile
    let hasChanges: Bool
    let font: NSFont
    let save: () -> Void

    private var bodyHasTitle: Bool {
        file.body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("# ")
    }

    private var dateLine: String {
        let date = file.modifiedAt.formatted(date: .long, time: .shortened)
        return [date, Self.readingTime(of: file.body)].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(dateLine)
                    .foregroundStyle(PiperTheme.secondary)
                    .accessibilityLabel("Modified \(dateLine)")
                if hasChanges {
                    Text("·").foregroundStyle(PiperTheme.secondary)
                    Text("Edited").foregroundStyle(PiperTheme.ink)
                    Button("Save", action: save)
                        .buttonStyle(.text)
                        .help("Save Markdown File · ⌘S")
                }
            }
            .font(PiperTheme.ui(AppDefaults.Reader.bylineFontSize))
            .lineLimit(1)
            if !bodyHasTitle {
                Text(file.title)
                    .font(Font(NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                        .withSize(font.pointSize * AppDefaults.Reader.headingMultipliers[0])))
                    .foregroundStyle(PiperTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppDefaults.Reader.horizontalInset)
        .padding(.top, AppDefaults.Reader.headerTopInset)
    }

    /// The minutes to read a body, such as "6 min read", or nil for a body without words.
    static func readingTime(of body: String) -> String? {
        let words = body.split(whereSeparator: \.isWhitespace).count
        guard words > 0 else { return nil }
        return "\(max(1, Int((Double(words) / AppDefaults.ArticleReader.wordsPerMinute).rounded()))) min read"
    }
}

/// The detail pane when nothing is selected.
struct NoSelection: View {
    var body: some View {
        EmptyPane(title: "No Selection")
            .background(PiperTheme.page)
    }
}
