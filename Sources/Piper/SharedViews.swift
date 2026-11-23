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
                .foregroundStyle(active ? PiperTheme.ink : PiperTheme.secondary)
                .background(active ? PiperTheme.selection : .clear, in: RoundedRectangle(cornerRadius: PiperTheme.radius))
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
    }
}

/// A rule in the separator color.
struct Rule: View {
    var vertical = false
    var body: some View {
        Rectangle().fill(PiperTheme.rule)
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
            Text(title).font(PiperTheme.ui(.reading, weight: .semibold)).foregroundStyle(PiperTheme.secondary)
            if let detail {
                Text(detail).font(PiperTheme.ui(.secondary)).foregroundStyle(PiperTheme.faint)
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
