import PiperCore
import SwiftUI

/// The rows under the search field.
///
/// `HomeSearch` returns the rows in rank order, grouped by kind. A heading
/// appears wherever the kind changes.
struct HomeSuggestionList: View {

    // MARK: Properties

    let suggestions: [HomeSuggestion]
    /// The index of the row that Return runs.
    let selection: Int
    let run: (HomeSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                if index == 0 || suggestions[index - 1].kind != suggestion.kind {
                    Text(suggestion.kind.groupTitle.uppercased())
                        .font(PiperTheme.ui(10.5, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(PiperTheme.faint)
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                        .padding(.bottom, 3)
                }
                Button { run(suggestion) } label: {
                    HomeSuggestionRow(suggestion: suggestion, selected: index == selection)
                }
                .buttonStyle(.plain)
                .id(suggestion.id)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PiperTheme.card, in: RoundedRectangle(cornerRadius: PiperTheme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: PiperTheme.cardRadius).strokeBorder(PiperTheme.rule, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
    }
}

/// One suggestion: icon, title, detail, and the shortcut at the trailing edge.
struct HomeSuggestionRow: View {

    // MARK: Properties

    let suggestion: HomeSuggestion
    let selected: Bool

    private var foreground: Color { selected ? .white : PiperTheme.ink }
    private var secondary: Color { selected ? .white : PiperTheme.secondary }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: suggestion.iconName)
                .font(.system(size: 12))
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
                    .font(PiperTheme.ui(11))
                    .foregroundStyle(selected ? .white : PiperTheme.faint)
            } else if selected {
                Image(systemName: "return").font(.system(size: 10)).foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .contentShape(Rectangle())
        .background(selected ? PiperTheme.accent : .clear, in: RoundedRectangle(cornerRadius: PiperTheme.radius))
    }
}
