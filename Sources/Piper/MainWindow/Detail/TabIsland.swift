import SwiftUI

/// The tabs of the detail pane, in a capsule that floats over the bottom of
/// the pane: Reader, Web, and Notes for a link capture, or Preview and Source
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
    @Environment(DetailPaneLayout.self) private var layout
    private var metrics: AppDefaults.TabIsland.Type { AppDefaults.TabIsland.self }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.tab) { item in
                let active = item.tab == selection
                Button { selection = item.tab } label: {
                    Text(item.title)
                        .font(PiperTheme.ui(metrics.fontSize, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? PiperTheme.ink : PiperTheme.secondary)
                        .padding(.horizontal, metrics.segmentPadding)
                        .frame(height: metrics.segmentHeight)
                        .background {
                            if active {
                                Capsule().fill(PiperTheme.card)
                                    .shadow(color: PiperTheme.tabShadow, radius: metrics.segmentShadowRadius, y: metrics.segmentShadowOffset)
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
        .overlay(Capsule().strokeBorder(PiperTheme.rule, lineWidth: 0.5))
        .shadow(color: PiperTheme.floatingShadow, radius: metrics.shadowRadius, y: metrics.shadowOffset)
        .padding(.bottom, metrics.bottomMargin)
        .padding(.trailing, cardPresented ? layout.tabsTrailingInset : 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View")
    }
}

extension TabIsland where Tab == ArticleTab {
    /// Reader, Web, and Notes.
    init(selection: Binding<ArticleTab>, cardPresented: Bool) {
        self.init(items: [
            Item(tab: .reader, title: "Reader", help: "Show the article as clean text"),
            Item(tab: .web, title: "Web", help: "Show the original page"),
            Item(tab: .notes, title: "Notes", help: "Show the highlights, notes, and questions of the article")
        ], selection: selection, cardPresented: cardPresented)
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
