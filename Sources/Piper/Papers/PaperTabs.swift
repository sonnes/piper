import AppKit
import SwiftUI

/// The column of file-folder tabs on the left edge of the feed paper.
///
/// Each tab lies on its side, in its own pastel color, and its label reads
/// from bottom to top. Each tab lies under the tab above it. The active tab
/// comes to the front, takes the color of the paper, and joins the paper.
///
/// The feed paper draws the column twice: the `.under` layer under the
/// paper holds every tab but the active tab, and the `.over` layer over the
/// paper holds only the active tab. The two layers have the same layout.
struct PaperTabs: View {
    enum Layer {
        case under, over
    }

    let layer: Layer
    let tabs: [PaperTab]
    let active: PaperTab
    let color: (PaperTab) -> TabColor
    let count: (PaperTab) -> Int
    /// True when the folder tabs show only the first letter of their folder.
    let stubs: Bool
    let choose: (PaperTab) -> Void
    let addFolder: () -> Void
    /// Removes a folder from the folder list. Nil when the list holds one folder.
    let removeFolder: ((String) -> Void)?

    private typealias Metrics = AppDefaults.Papers

    var body: some View {
        VStack(spacing: -Metrics.tabShoulder) {
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                let shows = (tab == active) == (layer == .over)
                FolderTab(tab: tab, number: index + 1, color: color(tab), active: tab == active, count: count(tab),
                          stub: stubs && tab.isFolder, action: { choose(tab) }, removeFolder: removeFolder)
                    .opacity(shows ? 1 : 0)
                    .allowsHitTesting(shows)
                    .accessibilityHidden(!shows)
                    // A tab lies over the tab under it.
                    .zIndex(Double(tabs.count - index))
            }
            AddFolderTab(action: addFolder)
                .padding(.top, Metrics.tabShoulder + Metrics.addTabGap)
                .opacity(layer == .under ? 1 : 0)
                .allowsHitTesting(layer == .under)
                .accessibilityHidden(layer != .under)
        }
        .frame(width: Metrics.tabWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
    }
}

// MARK: - Layout

/// The rule that shortens the folder tabs when the column is taller than the paper.
enum TabColumn {

    /// The label of the tab that adds a folder.
    static let addLabel = "+ Folder"

    /// The height of a column of tabs whose labels have these lengths, with
    /// the + Folder tab, whose label has the length `addLength`, under the last tab.
    static func height(of lengths: [CGFloat], addLength: CGFloat) -> CGFloat {
        let metrics = AppDefaults.Papers.self
        let add = addLength + 2 * metrics.tabLabelPadding
        guard !lengths.isEmpty else { return add }
        let tabs = lengths.reduce(0) { $0 + $1 + 2 * metrics.tabLabelPadding }
            - CGFloat(lengths.count - 1) * metrics.tabShoulder
        return tabs + metrics.addTabGap + add
    }

    /// True when the folder tabs show only the first letter of their folder:
    /// the column with full labels does not fit the height of the paper less
    /// the space over the first tab and under the last tab.
    static func usesStubs(lengths: [CGFloat], addLength: CGFloat, paperHeight: CGFloat) -> Bool {
        let metrics = AppDefaults.Papers.self
        return height(of: lengths, addLength: addLength) > paperHeight - metrics.tabsTop - metrics.tabRoom
    }

    /// The length of the label of a tab: the name and the count.
    @MainActor static func labelLength(title: String, count: Int) -> CGFloat {
        let metrics = AppDefaults.Papers.self
        let name = NSAttributedString(string: title, attributes: [
            .font: PiperTheme.paperUINS(.body, weight: .semibold), .kern: metrics.tabLabelTracking
        ]).size().width
        guard count > 0 else { return ceil(name) }
        let number = NSAttributedString(string: countText(count), attributes: [
            .font: PiperTheme.paperUINS(.body)
        ]).size().width
        return ceil(name + metrics.tabLabelSpacing + number)
    }

    /// The count on a tab. A large count shows as its limit and a plus sign.
    static func countText(_ count: Int) -> String {
        let limit = AppDefaults.Papers.countLimit
        return count > limit ? "\(limit)+" : "\(count)"
    }
}

/// The outline of a file-folder tab on its side, open at the right, where
/// the tab goes under the paper.
///
/// Each end is one S-curve from the edge of the paper to the outer edge of
/// the tab. The curve starts and ends parallel to the edge of the paper, so
/// the outline has no corner.
struct FolderTabShape: Shape {
    func path(in rect: CGRect) -> Path {
        let metrics = AppDefaults.Papers.self
        let w = rect.width, v = metrics.tabVisible, s = metrics.tabShoulder, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: v, y: 0))
        path.addCurve(to: CGPoint(x: 0, y: s), control1: CGPoint(x: v, y: s * 0.6), control2: CGPoint(x: 0, y: s * 0.4))
        path.addLine(to: CGPoint(x: 0, y: h - s))
        path.addCurve(to: CGPoint(x: v, y: h), control1: CGPoint(x: 0, y: h - s * 0.4), control2: CGPoint(x: v, y: h - s * 0.6))
        path.addLine(to: CGPoint(x: w, y: h))
        path.closeSubpath()
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// The line on the outer edge of the active tab, between its two curves.
private struct TabEdgeLine: Shape {
    func path(in rect: CGRect) -> Path {
        let metrics = AppDefaults.Papers.self
        let x = rect.minX + metrics.tabEdgeInset
        var path = Path()
        path.move(to: CGPoint(x: x, y: rect.minY + metrics.tabShoulder + 2))
        path.addLine(to: CGPoint(x: x, y: rect.maxY - metrics.tabShoulder - 2))
        return path
    }
}

/// The area that the active tab draws in: its shadow falls to the left, and
/// stops before the paper.
private struct ActiveTabClip: Shape {
    func path(in rect: CGRect) -> Path {
        let metrics = AppDefaults.Papers.self
        let reach = metrics.tabShoulder
        return Path(CGRect(x: rect.minX - reach, y: rect.minY - reach,
                           width: reach + rect.width - metrics.activeTabClip, height: rect.height + 2 * reach))
    }
}

/// Lays out its one subview on its side: the width of the subview is its height.
/// The subview turns itself with `rotationEffect`.
private struct Sideways: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let size = subviews.first?.sizeThatFits(.unspecified) else { return .zero }
        return CGSize(width: size.height, height: size.width)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: .unspecified)
    }
}

// MARK: - Tabs

/// One tab of the column.
private struct FolderTab: View {
    let tab: PaperTab
    let number: Int
    let color: TabColor
    let active: Bool
    let count: Int
    let stub: Bool
    let action: () -> Void
    let removeFolder: ((String) -> Void)?

    @State private var hovered = false
    @State private var spring: CGFloat = 0
    @FocusState private var focused: Bool
    /// True while the tab has the focus from a key, such as Tab. The focus
    /// that a window gives its first control at launch shows no ring.
    @State private var keyFocused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private typealias Metrics = AppDefaults.Papers

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(FolderTabStyle(color: color, active: active, hovered: hovered, focused: keyFocused))
            .focused($focused)
            .onChange(of: focused) { _, now in
                keyFocused = now && NSApp.currentEvent?.type == .keyDown
            }
            .focusEffectDisabled()
            .offset(x: spring)
            .onHover { hovered = $0 }
            .onChange(of: active) { _, now in
                if now { springOut() }
            }
            .help(stub ? "\(tab.title) · \(number)" : "Tab \(number)")
            .contextMenu {
                if case .folder(let path) = tab {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: (path as NSString).expandingTildeInPath)])
                    }
                    if let removeFolder {
                        Divider()
                        Button("Remove Folder") { removeFolder(path) }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(count > 0 ? "\(tab.title), \(count)" : tab.title)
            .accessibilityHint("Tab \(number)")
            .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, action)
    }

    private var label: some View {
        Sideways {
            HStack(spacing: Metrics.tabLabelSpacing) {
                Text(stub ? String(tab.title.prefix(1)) : tab.title)
                    .font(PiperTheme.paperUI(.body, weight: .semibold))
                if count > 0 {
                    Text(TabColumn.countText(count))
                        .font(PiperTheme.paperUI(.body))
                        .monospacedDigit()
                        .foregroundStyle(active ? PiperTheme.paperMuted : PiperTheme.tabCount)
                }
            }
            .tracking(Metrics.tabLabelTracking)
            .lineLimit(1)
            .fixedSize()
            .rotationEffect(.degrees(-90))
        }
    }

    /// The tab that becomes active springs out from under the paper.
    private func springOut() {
        guard !reduceMotion else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { spring = Metrics.tabSpringOffset }
        DispatchQueue.main.async {
            withAnimation(.timingCurve(0.3, 1.4, 0.5, 1, duration: Metrics.tabSpring)) { spring = 0 }
        }
    }
}

/// The outline, the fill, the shadows, and the states of a tab.
private struct FolderTabStyle: ButtonStyle {
    let color: TabColor
    let active: Bool
    let hovered: Bool
    let focused: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private typealias Metrics = AppDefaults.Papers

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !active
        let lifted = hovered && !active && !pressed
        let shape = FolderTabShape()
        configuration.label
            .foregroundStyle(active ? PiperTheme.paperInk : PiperTheme.tabInk)
            .padding(.vertical, Metrics.tabLabelPadding)
            .frame(width: Metrics.tabVisible - Metrics.tabLabelLeading)
            .padding(.leading, Metrics.tabLabelLeading)
            .frame(width: Metrics.tabWidth, alignment: .leading)
            .background {
                ZStack {
                    // The ring lies under the fill, so only its outer half shows.
                    if focused { shape.stroke(PiperTheme.tabFocus, lineWidth: Metrics.tabFocusLine) }
                    shape.fill(active ? PiperTheme.paper : PiperTheme.tabFill(color))
                        .overlay { if pressed { shape.fill(PiperTheme.tabPressed) } }
                        .shadow(color: PiperTheme.tabContactShadow(hovered: lifted, active: active),
                                radius: Metrics.tabContactShadow.radius, y: Metrics.tabContactShadow.y)
                        .shadow(color: PiperTheme.tabDiffuseShadow(hovered: lifted, active: active),
                                radius: diffuse(lifted).radius, x: diffuse(lifted).x, y: diffuse(lifted).y)
                    if active {
                        TabEdgeLine().stroke(PiperTheme.tabEdge(color),
                                             style: StrokeStyle(lineWidth: Metrics.tabEdgeLine, lineCap: .round))
                    } else {
                        shape.stroke(PiperTheme.tabHairline, lineWidth: Metrics.tabHairline)
                    }
                }
            }
            .contentShape(shape)
            .clipShape(active ? AnyShape(ActiveTabClip()) : AnyShape(Rectangle().inset(by: -Metrics.tabShoulder)))
            .offset(x: lifted ? -Metrics.tabHoverLift : 0)
            .animation(reduceMotion ? nil : .timingCurve(0.3, 1.4, 0.5, 1, duration: Metrics.tabSpring), value: lifted)
    }

    private func diffuse(_ lifted: Bool) -> (x: CGFloat, y: CGFloat, radius: CGFloat) {
        if active { return Metrics.activeTabShadow }
        if lifted { return Metrics.hoverTabShadow }
        let shadow = Metrics.tabDiffuseShadow
        return (shadow.x, shadow.y, scheme == .dark ? shadow.darkRadius : shadow.radius)
    }
}

/// The dashed tab at the end of the column. It adds a folder, and each folder gets a tab.
private struct AddFolderTab: View {
    let action: () -> Void

    @State private var hovered = false
    private typealias Metrics = AppDefaults.Papers

    var body: some View {
        let shape = FolderTabShape()
        Button(action: action) {
            Sideways {
                Text(TabColumn.addLabel)
                    .font(PiperTheme.paperUI(.body, weight: .semibold))
                    .tracking(Metrics.tabLabelTracking)
                    .foregroundStyle(PiperTheme.paperMuted)
                    .lineLimit(1)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
            }
            .padding(.vertical, Metrics.tabLabelPadding)
            .frame(width: Metrics.tabVisible - Metrics.tabLabelLeading)
            .padding(.leading, Metrics.tabLabelLeading)
            .frame(width: Metrics.tabWidth, alignment: .leading)
            .background {
                ZStack {
                    if hovered { shape.fill(PiperTheme.paperTint) }
                    shape.stroke(PiperTheme.tabDash, style: StrokeStyle(lineWidth: Metrics.markLine, dash: Metrics.slotDash))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Add a folder. Each folder gets a tab.")
        .accessibilityLabel("Add Folder")
        .accessibilityAction(.default, action)
    }
}
