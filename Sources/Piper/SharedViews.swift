import SwiftUI

/// An icon button with an optional active state.
struct IconButton: View {
    let title: String
    let icon: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: Metrics.glyph, weight: .regular))
                .frame(width: Metrics.size.width, height: Metrics.size.height)
                .foregroundStyle(active ? PiperTheme.paperInk : PiperTheme.paperMuted)
                .background(active ? PiperTheme.paperTint : .clear, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

extension IconButton {
    enum Metrics {
        static let glyph: CGFloat = 14
        static let size = CGSize(width: 28, height: 24)
        static let cornerRadius: CGFloat = 6
    }
}

/// A rule in the separator color.
struct Rule: View {
    var vertical = false
    var body: some View {
        Rectangle().fill(PiperTheme.paperRule)
            .frame(width: vertical ? Metrics.thickness : nil, height: vertical ? nil : Metrics.thickness)
    }
}

extension Rule {
    enum Metrics {
        static let thickness: CGFloat = 1
    }
}

/// A title and a line under it, centered in a pane that has nothing to show.
struct EmptyPane: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(spacing: Metrics.spacing) {
            Text(title).font(PiperTheme.paperUI(.row, weight: .semibold)).foregroundStyle(PiperTheme.paperMuted)
            if let detail {
                Text(detail).font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
            }
        }
        .multilineTextAlignment(.center)
        .padding(Metrics.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

extension EmptyPane {
    enum Metrics {
        static let spacing: CGFloat = 3
        static let padding: CGFloat = 24
    }
}

/// A row of a pick list, such as the command palette, the file picker, and the
/// `/` and `@` lists of the composer. The chosen row has an accent fill.
struct PickRow: ViewModifier {
    let chosen: Bool

    func body(content: Content) -> some View {
        content
            .foregroundStyle(chosen ? PiperTheme.onAccent : PiperTheme.paperInk)
            .padding(.horizontal, Metrics.horizontalPadding)
            .padding(.vertical, Metrics.verticalPadding)
            .frame(minHeight: Metrics.height)
            .background(chosen ? PiperTheme.brand : .clear, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius))
            .contentShape(Rectangle())
    }

    /// The color of a second text on a row, such as a folder or a shortcut.
    static func secondary(_ chosen: Bool, otherwise color: Color) -> Color {
        chosen ? PiperTheme.onAccentSecondary : color
    }
}

extension PickRow {
    enum Metrics {
        static let height: CGFloat = 28
        static let horizontalPadding: CGFloat = 8
        /// The space over and under a row of two lines.
        static let verticalPadding: CGFloat = 4
        static let cornerRadius: CGFloat = 6
    }
}

extension View {
    func pickRow(chosen: Bool) -> some View {
        modifier(PickRow(chosen: chosen))
    }
}
