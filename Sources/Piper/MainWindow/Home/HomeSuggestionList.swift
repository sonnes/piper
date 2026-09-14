import PiperCommands
import SwiftUI

/// The rows under the search field.
///
/// `CommandParser` returns the rows in rank order, grouped by kind. A heading
/// appears wherever the kind changes.
struct HomeSuggestionList: View {

    // MARK: Properties

    let suggestions: [CommandSuggestion]
    /// The index of the row that Return runs.
    let selection: Int
    let run: (CommandSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                if index == 0 || suggestions[index - 1].kind != suggestion.kind {
                    Text(suggestion.kind.groupTitle)
                        .font(PiperTheme.ui(11, weight: .bold).smallCaps())
                        .tracking(0.3)
                        .foregroundStyle(PiperTheme.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 7)
                        .padding(.bottom, 2)
                }
                Button { run(suggestion) } label: {
                    HomeSuggestionRow(suggestion: suggestion, selected: index == selection)
                }
                .buttonStyle(.plain)
                .id(suggestion.id)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PiperTheme.page, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(PiperTheme.rule, lineWidth: 1))
    }
}

/// One suggestion: icon, title, detail, and the scope tag at the trailing edge.
struct HomeSuggestionRow: View {

    // MARK: Properties

    let suggestion: CommandSuggestion
    let selected: Bool

    private var foreground: Color { selected ? .white : PiperTheme.ink }
    private var secondary: Color { selected ? .white : PiperTheme.secondary }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: suggestion.iconName)
                .font(PiperTheme.ui(12))
                .frame(width: 16)
                .foregroundStyle(secondary)
            Text(suggestion.title)
                .font(PiperTheme.ui(13))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .layoutPriority(1)
            Text(suggestion.detail)
                .font(PiperTheme.ui(12))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !suggestion.tag.isEmpty {
                Text(suggestion.tag)
                    .font(Font(PiperTheme.manuscript(size: 11)))
                    .foregroundStyle(selected ? .white : PiperTheme.faint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(minHeight: 24)
        .contentShape(Rectangle())
        .background(selected ? PiperTheme.accent : .clear)
    }
}
