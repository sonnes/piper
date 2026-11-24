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

/// The name of a group in a completion list, over the first row of the group.
struct CompletionGroupHeader: View {
    let title: String
    let isFirst: Bool
    var tracking: CGFloat = 0

    var body: some View {
        Text(title)
            .font(PiperTheme.paperUI(.body, weight: .semibold)).tracking(tracking)
            .foregroundStyle(PiperTheme.paperFaint)
            .padding(.horizontal, PickRow.Metrics.horizontalPadding)
            .padding(.top, isFirst ? CompletionListChrome.Metrics.firstHeaderTop : CompletionListChrome.Metrics.headerTop)
            .padding(.bottom, CompletionListChrome.Metrics.headerBottom)
    }
}

extension CompletionListChrome {
    enum Metrics {
        static let padding: CGFloat = 6
        static let edge: CGFloat = 0.5
        static let shadowRadius: CGFloat = 12
        static let shadowOffset: CGFloat = 4
        /// The space over the first group name of a list, and over each group name after it.
        static let firstHeaderTop: CGFloat = 4
        static let headerTop: CGFloat = 8
        static let headerBottom: CGFloat = 3
    }
}
