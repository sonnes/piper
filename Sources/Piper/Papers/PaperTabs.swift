import SwiftUI

/// The column of rounded indigo tabs on the left edge of the feed paper.
///
/// Each tab shows a count. The active tab is darker and wider, and a dot
/// marks it. A pinned folder has a paler tab. The dashed + Folder tab at
/// the end shows the Folders index, where a folder gets its pin.
struct PaperTabs: View {
    let tabs: [PaperTab]
    let active: PaperTab
    let count: (PaperTab) -> Int
    let choose: (PaperTab) -> Void
    let addFolder: () -> Void

    private typealias Metrics = AppDefaults.Papers

    var body: some View {
        VStack(alignment: .trailing, spacing: Metrics.tabSpacing) {
            ForEach(tabs, id: \.self) { tab in
                TabButton(tab: tab, active: tab == active, count: count(tab)) { choose(tab) }
                    .padding(.top, isFirstPin(tab) ? Metrics.pinGap : 0)
            }
            AddFolderTab(action: addFolder)
        }
        .frame(width: Metrics.activeTabWidth, alignment: .trailing)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
    }

    private func isFirstPin(_ tab: PaperTab) -> Bool {
        guard case .pinned = tab else { return false }
        return tabs.first { if case .pinned = $0 { return true } else { return false } } == tab
    }
}

/// One tab of the column.
private struct TabButton: View {
    let tab: PaperTab
    let active: Bool
    let count: Int
    let action: () -> Void

    @State private var hovered = false
    private typealias Metrics = AppDefaults.Papers

    private var pinned: Bool {
        if case .pinned = tab { return true }
        return false
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if active {
                    Circle().fill(ink).frame(width: 6, height: 6)
                }
                Text(tab.title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                if count > 0 {
                    Text(count > Metrics.countLimit ? "\(Metrics.countLimit)+" : "\(count)").monospacedDigit()
                }
            }
            .font(PiperTheme.paperUI(.body, weight: active ? .semibold : .medium))
            .foregroundStyle(ink)
            .padding(.leading, 16)
            .padding(.trailing, Metrics.tabOverlap + 12)
            .frame(width: active ? Metrics.activeTabWidth : Metrics.tabWidth, height: Metrics.tabHeight)
            .background(fill, in: UnevenRoundedRectangle(topLeadingRadius: Metrics.tabCornerRadius,
                                                         bottomLeadingRadius: Metrics.tabCornerRadius,
                                                         style: .continuous))
            .shadow(color: active ? PiperTheme.activeTabShadowColor : PiperTheme.tabShadowColor,
                    radius: active ? Metrics.activeTabShadowRadius : Metrics.tabShadowRadius, y: Metrics.tabShadowOffset)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(tab.hasIndex ? "Show the \(tab.title) index" : "Show \(tab.title)")
        .accessibilityLabel(count > 0 ? "\(tab.title), \(count)" : tab.title)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

    private var ink: Color { pinned ? PiperTheme.pinTabInk : PiperTheme.onAccent }

    private var fill: Color {
        if pinned { return active || hovered ? PiperTheme.pinTabActive : PiperTheme.pinTab }
        return active || hovered ? PiperTheme.tabActive : PiperTheme.tab
    }
}

/// The dashed tab at the end of the column. It shows the Folders index.
private struct AddFolderTab: View {
    let action: () -> Void

    @State private var hovered = false
    private typealias Metrics = AppDefaults.Papers

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: Metrics.tabCornerRadius,
                                           bottomLeadingRadius: Metrics.tabCornerRadius, style: .continuous)
        Button(action: action) {
            Text("+ Folder")
                .font(PiperTheme.paperUI(.body, weight: .medium))
                .foregroundStyle(PiperTheme.paperMuted)
                .padding(.leading, 16)
                .frame(width: Metrics.addTabWidth, height: Metrics.tabHeight, alignment: .leading)
                .background(hovered ? PiperTheme.paperTint : .clear, in: shape)
                .overlay {
                    // The right edge has no border: the tab goes under the paper.
                    shape.strokeBorder(PiperTheme.paperBar, style: StrokeStyle(lineWidth: Metrics.markLine, dash: Metrics.slotDash))
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: Metrics.addTabWidth - Metrics.markLine)
                        }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, Metrics.activeTabWidth - Metrics.tabWidth)
        .onHover { hovered = $0 }
        .help("Show the Folders index, where a folder gets a tab")
        .accessibilityLabel("Add a folder tab")
    }
}
