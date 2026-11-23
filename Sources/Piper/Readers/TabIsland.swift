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
    private var metrics: AppDefaults.TabIsland.Type { AppDefaults.TabIsland.self }

    /// A segmented control in a capsule on a material, as on macOS. The
    /// selected segment is a raised capsule that slides to the new segment.
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab) { item in
                let active = item.tab == selection
                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: AppDefaults.Papers.spring)) { selection = item.tab }
                } label: {
                    Text(item.title)
                        .font(PiperTheme.paperUI(.body, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? PiperTheme.label : PiperTheme.secondaryLabel)
                        .padding(.horizontal, metrics.segmentPadding)
                        .frame(height: metrics.segmentHeight)
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
        .padding(metrics.inset)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(PiperTheme.barEdge, lineWidth: 0.5))
        .shadow(color: PiperTheme.barContactShadow, radius: 1, y: 0.5)
        .shadow(color: PiperTheme.barSoftShadow, radius: metrics.shadowRadius * 1.6, y: metrics.shadowOffset + 1)
        .padding(.bottom, metrics.bottomMargin)
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
