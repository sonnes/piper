import SwiftUI

/// The tabs of a reader paper, in a capsule that floats over the bottom of
/// the paper: Reader, Web, and Notes for a link capture, or Preview and Source
/// for a file.
struct TabIsland<Tab: Hashable>: View {

    struct Item {
        let tab: Tab
        let title: String
        let help: String
    }

    // MARK: - Properties

    let items: [Item]
    @Binding var selection: Tab
    let cardPresented: Bool
    @Environment(PaperLayout.self) private var layout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var thumb
    private typealias Metrics = TabIslandMetrics

    /// A segmented control in a capsule on a material, as on macOS. The
    /// selected segment is a raised capsule that slides to the new segment.
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab) { item in
                let active = item.tab == selection
                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: ReaderPaper.Metrics.spring)) { selection = item.tab }
                } label: {
                    Text(item.title)
                        .font(PiperTheme.paperUI(.body, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? PiperTheme.paperInk : PiperTheme.paperMuted)
                        .padding(.horizontal, Metrics.segmentPadding)
                        .frame(height: Metrics.segmentHeight)
                        .background {
                            if active {
                                Capsule()
                                    .fill(PiperTheme.paper)
                                    .shadow(color: PiperTheme.barContactShadow, radius: 1, y: 0.5)
                                    .shadow(color: PiperTheme.barSoftShadow, radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(item.help)
                .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(Metrics.inset)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(PiperTheme.barEdge, lineWidth: 0.5))
        .shadow(color: PiperTheme.barContactShadow, radius: 1, y: 0.5)
        .shadow(color: PiperTheme.barSoftShadow, radius: Metrics.shadowRadius * 1.6, y: Metrics.shadowOffset + 1)
        .padding(.bottom, Metrics.bottomMargin)
        .padding(.trailing, cardPresented ? layout.tabsTrailingInset : 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View")
    }
}

extension TabIsland where Tab == ArticleTab {
    /// Reader, Web, and Notes. A feed article that is not in Inbox has no notes,
    /// so it shows Reader and Web only.
    init(selection: Binding<ArticleTab>, cardPresented: Bool, showsNotes: Bool = true) {
        let items = [
            Item(tab: .reader, title: "Reader", help: "Show the article as clean text"),
            Item(tab: .web, title: "Web", help: "Show the original page"),
            Item(tab: .notes, title: "Notes", help: "Show the highlights, notes, and questions of the article")
        ]
        self.init(items: showsNotes ? items : items.filter { $0.tab != .notes }, selection: selection, cardPresented: cardPresented)
    }
}

extension TabIsland where Tab == Bool {
    /// Preview and Source. True selects Source.
    init(showsSource: Binding<Bool>, cardPresented: Bool) {
        self.init(items: [
            Item(tab: false, title: "Preview", help: "Show the formatted file"),
            Item(tab: true, title: "Source", help: "Show the text of the file")
        ], selection: showsSource, cardPresented: cardPresented)
    }
}

// MARK: - Metrics

/// The tabs that float over the bottom of a reader paper.
enum TabIslandMetrics {
    static let segmentHeight: CGFloat = 30
    static let segmentPadding: CGFloat = 16
    /// The space between the capsule and the segments.
    static let inset: CGFloat = 3
    static let shadowRadius: CGFloat = 5
    static let shadowOffset: CGFloat = 2
    static let bottomMargin: CGFloat = 14
    /// The space that content leaves free under its last line for the tabs.
    static let clearance: CGFloat = 64
}
