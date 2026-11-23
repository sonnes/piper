import SwiftUI

/// A row of choices in a capsule. The chosen segment is a raised paper capsule.
///
/// The lenses of Today and the mode of each feed on Sources use it. Each
/// segment is a button, so a click, VoiceOver, and Full Keyboard Access all
/// pick it.
struct SegmentedCapsule<Value: Hashable>: View {
    let values: [Value]
    let selection: Value
    let title: (Value) -> String
    /// The number after a title, or nil for none.
    var count: (Value) -> Int? = { _ in nil }
    /// The tooltip of a segment, such as its key.
    var help: (Value) -> String = { _ in "" }
    /// True to share the width of the container. False to fit the titles.
    var fills = true
    let pick: (Value) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let metrics = CapsuleMetrics.self
        HStack(spacing: 0) {
            ForEach(values, id: \.self) { value in
                let on = selection == value
                Button { pick(value) } label: {
                    HStack(spacing: 5) {
                        Text(title(value))
                        if let count = count(value), count > 0 {
                            Text("\(count)").monospacedDigit().foregroundStyle(on ? PiperTheme.paperMuted : PiperTheme.paperFaint)
                        }
                    }
                    .font(PiperTheme.paperUI(.body, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? PiperTheme.paperInk : PiperTheme.paperMuted)
                    .padding(.horizontal, fills ? 0 : metrics.segmentPadding)
                    .frame(maxWidth: fills ? .infinity : nil, minHeight: metrics.lensHeight - metrics.lensInset * 2)
                    .background(on ? PiperTheme.paper : .clear, in: Capsule())
                    .shadow(color: on ? PiperTheme.lensShadow : .clear, radius: 1, y: 0.5)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(help(value))
                .accessibilityLabel(title(value))
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(metrics.lensInset)
        .background(PiperTheme.paperTint, in: Capsule())
        .fixedSize(horizontal: !fills, vertical: false)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selection)
    }
}

private enum CapsuleMetrics {
    static let lensHeight: CGFloat = 30
    static let lensInset: CGFloat = 3
    /// The side padding of a segment that fits its title.
    static let segmentPadding: CGFloat = 10
}
