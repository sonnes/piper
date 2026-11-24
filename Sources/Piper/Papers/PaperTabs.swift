import AppKit
import SwiftUI
import Vault

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

    var body: some View {
        VStack(spacing: -Metrics.tabShoulder) {
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                let shows = (tab == active) == (layer == .over)
                FolderTab(tab: tab, number: index + 1, color: color(tab), active: tab == active, count: count(tab),
                          stub: stubs && tab.isFolder, action: { choose(tab) }, removeFolder: removeFolder)
                    .opacity(shows ? 1 : 0)
                    .allowsHitTesting(shows)
                    .accessibilityHidden(!shows)
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
        let metrics = PaperTabs.Metrics.self
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
        let metrics = PaperTabs.Metrics.self
        return height(of: lengths, addLength: addLength) > paperHeight - metrics.tabsTop - metrics.tabRoom
    }

    /// The length of the label of a tab: the name and the count.
    @MainActor static func labelLength(title: String, count: Int) -> CGFloat {
        let metrics = PaperTabs.Metrics.self
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
        let limit = PaperTabs.Metrics.countLimit
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
        let metrics = PaperTabs.Metrics.self
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
        let metrics = PaperTabs.Metrics.self
        let x = rect.minX + metrics.tabEdgeInset
        var path = Path()
        path.move(to: CGPoint(x: x, y: rect.minY + metrics.tabShoulder + metrics.tabEdgeGap))
        path.addLine(to: CGPoint(x: x, y: rect.maxY - metrics.tabShoulder - metrics.tabEdgeGap))
        return path
    }
}

/// The area that the active tab draws in: its shadow falls to the left, and
/// stops before the paper.
private struct ActiveTabClip: Shape {
    func path(in rect: CGRect) -> Path {
        let metrics = PaperTabs.Metrics.self
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
    private typealias Metrics = PaperTabs.Metrics

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
                        NSWorkspace.shared.activateFileViewerSelecting([Vault(path: path).root])
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
                        .foregroundStyle(active ? PiperTheme.paperMuted : Metrics.countColor)
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
    private typealias Metrics = PaperTabs.Metrics

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !active
        let lifted = hovered && !active && !pressed
        let shape = FolderTabShape()
        configuration.label
            .foregroundStyle(active ? PiperTheme.paperInk : Metrics.ink)
            .padding(.vertical, Metrics.tabLabelPadding)
            .frame(width: Metrics.tabVisible - Metrics.tabLabelLeading)
            .padding(.leading, Metrics.tabLabelLeading)
            .frame(width: Metrics.tabWidth, alignment: .leading)
            .background {
                ZStack {
                    // The ring lies under the fill, so only its outer half shows.
                    if focused { shape.stroke(Metrics.focus, lineWidth: Metrics.tabFocusLine) }
                    shape.fill(active ? PiperTheme.paper : Metrics.fill(color))
                        .overlay { if pressed { shape.fill(Metrics.pressed) } }
                        .shadow(color: Metrics.contactShadowColor(hovered: lifted, active: active),
                                radius: Metrics.tabContactShadow.radius, y: Metrics.tabContactShadow.y)
                        .shadow(color: Metrics.diffuseShadowColor(hovered: lifted, active: active),
                                radius: diffuse(lifted).radius, x: diffuse(lifted).x, y: diffuse(lifted).y)
                    if active {
                        TabEdgeLine().stroke(Metrics.edge(color),
                                             style: StrokeStyle(lineWidth: Metrics.tabEdgeLine, lineCap: .round))
                    } else {
                        shape.stroke(Metrics.hairlineColor, lineWidth: Metrics.tabHairline)
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
    private typealias Metrics = PaperTabs.Metrics

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
                    shape.stroke(Metrics.dash, style: StrokeStyle(lineWidth: PaperRowMetrics.markLine, dash: PaperRowMetrics.slotDash))
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

// MARK: - Metrics

/// The vertical tabs on the left edge of the feed paper, as in variant C of
/// `mocks/vertical-tabs.html`.
extension PaperTabs {
    enum Metrics {
        /// A tab is 50 points wide. 40 points show, and 10 points lie under the paper.
        static let tabWidth: CGFloat = 50
        static let tabVisible: CGFloat = 40
        /// The height of the curve at each end of a tab. Each tab lies this far
        /// under the tab above it, so that one curve shows between two tabs.
        static let tabShoulder: CGFloat = 24
        static let tabLabelPadding: CGFloat = 20
        static let tabLabelLeading: CGFloat = 4
        static let tabLabelSpacing: CGFloat = 6
        /// The letter spacing of a tab label: -0.01 em at 14 points.
        static let tabLabelTracking: CGFloat = -0.14
        /// The space between the top of the paper and the first tab.
        static let tabsTop: CGFloat = 20
        /// The space that the column of tabs leaves free at the foot of the paper.
        static let tabRoom: CGFloat = 40
        static let tabHairline: CGFloat = 0.75
        /// The line on the outer edge of the active tab.
        static let tabEdgeLine: CGFloat = 3
        static let tabEdgeInset: CGFloat = 3.5
        /// The edge line stops this far from the curve at each end of the tab.
        static let tabEdgeGap: CGFloat = 2
        static let tabFocusLine: CGFloat = 3
        /// The active tab covers the paper by 1 point, so no seam shows. Its
        /// shadow stops 9 points from the inner edge of the tab.
        static let activeTabClip: CGFloat = 9
        /// The distance that a tab moves out under the pointer.
        static let tabHoverLift: CGFloat = 1
        /// The active tab springs out from this distance under the paper.
        static let tabSpringOffset: CGFloat = 5
        static let tabSpring: Double = 0.25
        /// `drop-shadow(0 .5px .5px)`: the tight shadow at the outline of a tab.
        static let tabContactShadow = (radius: CGFloat(0.25), y: CGFloat(0.5))
        /// `drop-shadow(-2px 3px 6px)`, or 8 points of blur in the dark: the wide soft shadow of a tab.
        static let tabDiffuseShadow = (x: CGFloat(-2), y: CGFloat(3), radius: CGFloat(3), darkRadius: CGFloat(4))
        /// `drop-shadow(-3px 4px 10px)`: the soft shadow of a tab under the pointer.
        static let hoverTabShadow = (x: CGFloat(-3), y: CGFloat(4), radius: CGFloat(5))
        /// `drop-shadow(-4px 3px 10px)`: the soft shadow of the active tab.
        static let activeTabShadow = (x: CGFloat(-4), y: CGFloat(3), radius: CGFloat(5))
        /// The dashed tab at the end of the column, which adds a folder.
        static let addTabGap: CGFloat = 8
        /// The most a count on a tab shows. A larger count shows as this number and a plus sign.
        static let countLimit = 999

        // The tabs on the edge of the feed paper are pastel file-folder tabs, as
        // in variant C of `mocks/vertical-tabs.html`. In the light, a fill is the
        // 100 shade of its color. In the dark, a fill is its 600 shade at 42
        // percent on the zinc 900 desk, and the label is white.

        /// The fill of a tab that is not active.
        static func fill(_ color: TabColor) -> Color {
            let (light, dark) = fills[color] ?? (0xE4E4E7, 0x525257)
            return Color(nsColor: PiperTheme.color(light: light, dark: dark))
        }

        /// The line on the outer edge of the active tab: the 600 or 700 shade in
        /// the light, and the 400 shade in the dark.
        static func edge(_ color: TabColor) -> Color {
            edges[color] ?? PiperTheme.paperMuted
        }

        /// Zinc 900, and white. The label of a tab that is not active.
        static let ink = PiperTheme.paperInk
        /// Zinc 600, and white at 78 percent. The count of a tab that is not active.
        static let countColor = Color(nsColor: NSColor(name: nil) { appearance in
            PiperTheme.isDark(appearance) ? NSColor.white.withAlphaComponent(0.78) : PiperTheme.hex(0x52525B)
        })
        /// The hairline at the outline of a tab: black at 10 percent, and white at 14 percent in the dark.
        static let hairlineColor = Color(nsColor: NSColor(name: nil) { appearance in
            PiperTheme.isDark(appearance) ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.10)
        })
        /// The focus ring of a tab: indigo 600 at 70 percent, and indigo 400 at 80 percent in the dark.
        static let focus = Color(nsColor: NSColor(name: nil) { appearance in
            PiperTheme.brandNS.withAlphaComponent(PiperTheme.isDark(appearance) ? 0.8 : 0.7)
        })
        /// The darker fill of a pressed tab: black at 6 percent, and 10 percent in the dark.
        static let pressed = Color(nsColor: PiperTheme.shade(light: 0.06, dark: 0.10))
        /// Zinc 400. The dashed outline of the tab that adds a folder.
        static let dash = Color(nsColor: PiperTheme.hex(0xA1A1AA))

        /// The tight contact shadow of a tab. Black at 12 percent, 14 percent
        /// under the pointer, 10 percent for the active tab, and 40 percent in the dark.
        static func contactShadowColor(hovered: Bool, active: Bool) -> Color {
            Color(nsColor: PiperTheme.shade(light: active ? 0.10 : hovered ? 0.14 : 0.12, dark: 0.40))
        }

        /// The wide soft shadow of a tab. Black at 6 percent, 10 percent under the
        /// pointer and for the active tab, and 30 or 40 percent in the dark.
        static func diffuseShadowColor(hovered: Bool, active: Bool) -> Color {
            Color(nsColor: PiperTheme.shade(light: active || hovered ? 0.10 : 0.06, dark: active ? 0.40 : 0.30))
        }

        private static let fills: [TabColor: (UInt32, UInt32)] = [
            .indigo: (0xE0E7FF, 0x2F2B70), .zinc: (0xE4E4E7, 0x525257), .sky: (0xE0F2FE, 0x0F4563),
            .emerald: (0xD1FAE5, 0x104D3C), .plum: (0xFAE8FF, 0x5F1E68), .teal: (0xCCFBF1, 0x134C49),
            .rose: (0xFFE4E6, 0x6C1A2E), .clay: (0xFFEDD5, 0x703315)
        ]

        private static let edges: [TabColor: Color] = [
            .indigo: PiperTheme.brand, .zinc: PiperTheme.paperMuted,
            .sky: Color(nsColor: PiperTheme.color(light: 0x0369A1, dark: 0x38BDF8)),
            .emerald: Color(nsColor: PiperTheme.color(light: 0x047857, dark: 0x34D399)),
            .plum: Color(nsColor: PiperTheme.color(light: 0x86198F, dark: 0xE879F9)),
            .teal: Color(nsColor: PiperTheme.color(light: 0x0F766E, dark: 0x2DD4BF)),
            .rose: Color(nsColor: PiperTheme.color(light: 0xBE123C, dark: 0xFB7185)),
            .clay: Color(nsColor: PiperTheme.color(light: 0xC2410C, dark: 0xFB923C))
        ]
    }
}
