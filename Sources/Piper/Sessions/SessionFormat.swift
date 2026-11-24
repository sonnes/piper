import SwiftUI

/// The formats that the session views share.
enum SessionFormat {
    /// A turn time in minutes and seconds, such as "2m 5s".
    static func duration(milliseconds: Int) -> String {
        Duration.milliseconds(milliseconds).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated, fractionalPart: .hide))
    }

    /// A cost in US dollars, such as "$0.42".
    static func cost(_ dollars: Double) -> String {
        String(format: "$%.2f", dollars)
    }
}

/// The card around a completion list over a composer.
struct CompletionListChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Metrics.padding)
            .background(PiperTheme.paper, in: RoundedRectangle(cornerRadius: PiperTheme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: PiperTheme.cardRadius).strokeBorder(PiperTheme.paperRule, lineWidth: Metrics.edge))
            .shadow(color: PiperTheme.barSoftShadow, radius: Metrics.shadowRadius, y: Metrics.shadowOffset)
    }
}

extension CompletionListChrome {
    enum Metrics {
        static let padding: CGFloat = 6
        static let edge: CGFloat = 0.5
        static let shadowRadius: CGFloat = 12
        static let shadowOffset: CGFloat = 4
    }
}
