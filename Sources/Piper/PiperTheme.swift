import AppKit
import CoreText
import SwiftUI

/// The colors, fonts, and shapes of the application.
///
/// Text and surfaces use the system colors, so they follow the dark appearance
/// and the contrast settings of the reader. The accent is the one saturated
/// color, and it marks selection with focus, links, and the primary button.
enum PiperTheme {
    static let resources: Bundle = {
        if let url = Bundle.main.url(forResource: "Piper_Piper", withExtension: "bundle"), let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }()
    static let mark = resources.image(forResource: "Sandpiper")

    // MARK: Colors

    /// The background of a list and of a reader paper.
    static let pageNS = paperNS
    /// The background of the capture panel, the reader bar, and the link card.
    static let panelNS = color(light: 0xF3F3F4, dark: 0x232324)
    /// The background of a grouped card on the panel.
    static let cardNS = color(light: 0xFFFFFF, dark: 0x2C2C2E)
    static let inkNS = NSColor.labelColor
    static let secondaryNS = NSColor.secondaryLabelColor
    static let faintNS = NSColor.tertiaryLabelColor
    /// The accent color: srgb 0.031 0.416 0.933, and 0.369 0.620 0.957 in the dark.
    static let accentNS = color(light: 0x086AEE, dark: 0x5E9EF4)
    /// The selection of a row without keyboard focus.
    static let selectionNS = NSColor.unemphasizedSelectedContentBackgroundColor
    static let ruleNS = NSColor.separatorColor
    /// Selected text on the reader page and in a Markdown file: the accent at 20 percent, and 30 percent in the dark.
    static let readerSelectionNS = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? hex(0x5E9EF4).withAlphaComponent(0.3) : hex(0x086AEE).withAlphaComponent(0.2)
    }
    /// The fill of code in a Markdown file: the code fill of the reader page
    /// over its paper. It is opaque, because the editor paints each line of a
    /// code block, and a clear fill doubles where two lines meet.
    static let readerCodeNS = color(light: 0xF0EFEC, dark: 0x262627)
    /// A yellow highlight on the reader page, and `==text==` in a Markdown file.
    static let readerMarkNS = NSColor(name: nil) { appearance in
        hex(0xFACC15).withAlphaComponent(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.28 : 0.38)
    }
    static let warningNS = NSColor.systemOrange
    static let dangerNS = NSColor.systemRed
    static let successNS = NSColor.systemGreen

    // The row icons use the Tailwind CSS palette: shade 500 in the light
    // appearance and shade 400 in the dark, unless a comment names others.

    /// Amber.
    /// Blue.
    static let inboxNS = color(light: 0x3B82F6, dark: 0x60A5FA)
    /// Violet.
    static let clipboardNS = color(light: 0x8B5CF6, dark: 0xA78BFA)
    /// Amber 700 and 600.
    static let archivedNS = color(light: 0xB45309, dark: 0xD97706)
    /// Emerald 600 and 400. The rows of the Feeds group.
    static let feedsNS = color(light: 0x059669, dark: 0x34D399)
    /// Amber 500 and 400. A starred article.
    static let starNS = color(light: 0xF59E0B, dark: 0xFBBF24)
    /// Orange. The tile of a sessions folder, its count of sessions that wait, and the mark of Claude Code.
    static let claudeNS = color(light: 0xF97316, dark: 0xFB923C)
    /// Teal 600 and 400. The mark of an agent that speaks ACP.
    static let acpAgentNS = color(light: 0x0D9488, dark: 0x2DD4BF)
    /// Zinc 500 and 400.
    static let folderNS = color(light: 0x71717A, dark: 0xA1A1AA)
    /// Zinc 400 and 500.
    static let fileNS = color(light: 0xA1A1AA, dark: 0x71717A)
    /// The colors of section dots and folder tiles, in the order of the rows:
    /// violet, emerald, orange, sky, rose, lime, fuchsia, and amber. Rows next
    /// to each other get hues that are far apart.
    static let tagsNS: [NSColor] = [
        color(light: 0x8B5CF6, dark: 0xA78BFA), color(light: 0x10B981, dark: 0x34D399),
        color(light: 0xF97316, dark: 0xFB923C), color(light: 0x0EA5E9, dark: 0x38BDF8),
        color(light: 0xF43F5E, dark: 0xFB7185), color(light: 0x84CC16, dark: 0xA3E635),
        color(light: 0xD946EF, dark: 0xE879F9), color(light: 0xF59E0B, dark: 0xFBBF24)
    ]

    // The tags of child notes and the highlight colors. The reader page uses
    // the same values. Highlight is amber 700 and yellow 400, question is
    // orange 700 and 400, and other tags are sky 700 and 400.

    static let markYellow = Color(nsColor: hex(0xFACC15))
    /// Text on a yellow chip, such as the count of highlights.
    static let markText = Color(nsColor: color(light: 0xA16207, dark: 0xFDE047))
    static let markGreen = Color(nsColor: hex(0x4ADE80))
    static let markPink = Color(nsColor: hex(0xF472B6))
    static let tagHighlight = Color(nsColor: color(light: 0xA16207, dark: 0xFACC15))
    static let tagHighlightFill = Color(nsColor: hex(0xEAB308)).opacity(0.16)
    static let tagQuestion = Color(nsColor: color(light: 0xC2410C, dark: 0xFB923C))
    static let tagQuestionFill = Color(nsColor: hex(0xF97316)).opacity(0.14)
    static let tagOther = Color(nsColor: color(light: 0x0369A1, dark: 0x38BDF8))
    static let tagOtherFill = Color(nsColor: hex(0x0EA5E9)).opacity(0.14)

    static let page = Color(nsColor: pageNS)
    static let panel = Color(nsColor: panelNS)
    static let card = Color(nsColor: cardNS)
    static let ink = Color(nsColor: inkNS)
    static let secondary = Color(nsColor: secondaryNS)
    static let faint = Color(nsColor: faintNS)
    static let accent = Color(nsColor: accentNS)
    static let selection = Color(nsColor: selectionNS)
    static let rule = Color(nsColor: ruleNS)
    static let warning = Color(nsColor: warningNS)
    /// The fill of the bar over the editor when Piper stopped saving.
    static let warningFill = warning.opacity(0.14)
    static let danger = Color(nsColor: dangerNS)
    static let success = Color(nsColor: successNS)
    static let claude = Color(nsColor: claudeNS)
    static let feeds = Color(nsColor: feedsNS)
    static let star = Color(nsColor: starNS)
    static let acpAgent = Color(nsColor: acpAgentNS)
    /// The fill and the ring of a request that waits in a session.
    static let requestFill = Color(nsColor: color(light: 0xF97316, dark: 0xFB923C)).opacity(0.12)
    static let requestRing = Color(nsColor: hex(0xF97316)).opacity(0.35)
    /// The lines that an edit adds and removes.
    static let diffAdded = Color(nsColor: hex(0x22C55E)).opacity(0.14)
    static let diffRemoved = Color(nsColor: hex(0xEF4444)).opacity(0.12)
    /// The mark of a finished tool call. Green 600.
    static let toolDone = Color(nsColor: color(light: 0x16A34A, dark: 0x4ADE80))
    /// A row under the pointer.
    static let hover = Color.primary.opacity(0.045)
    /// The track behind the tabs of the capture panel, and the shadow of the active tab.
    static let tabTrack = Color.primary.opacity(0.06)
    static let tabShadow = Color.black.opacity(0.12)
    /// The ring around a focused field.
    static let focusRing = accent.opacity(0.45)
    /// Text and symbols on an accent fill, such as a check or a toast button.
    static let onAccent = Color.white
    /// Faint text on an accent or warning fill, such as the shortcut in the Needs You pill.
    static let onAccentSecondary = onAccent.opacity(0.8)
    /// The shadows of the session card and of its pill.
    static let sessionCardShadow = Color.black.opacity(0.2)
    static let sessionPillShadow = Color.black.opacity(0.16)
    /// The shadow of a control that floats over content, such as the tabs of a reader paper.
    static let floatingShadow = Color.black.opacity(0.14)
    /// The line over an article that says where it opened.

    // MARK: Papers

    // The papers use the zinc and indigo of September. Each color names the
    // Tailwind shade for the light appearance, then for the dark.

    /// White, and zinc 800.
    static let paperNS = color(light: 0xFFFFFF, dark: 0x27272A)
    /// Zinc 900, and white.
    static let paperInkNS = color(light: 0x18181B, dark: 0xFFFFFF)
    /// Zinc 600 and 300.
    static let paperMutedNS = color(light: 0x52525B, dark: 0xD4D4D8)
    /// Zinc 500 and 400.
    static let paperFaintNS = color(light: 0x71717A, dark: 0xA1A1AA)
    /// Zinc 200 and 700.
    static let paperRuleNS = color(light: 0xE4E4E7, dark: 0x3F3F46)
    /// Zinc 100 and 700. A row under the pointer, and a field.
    static let paperTintNS = color(light: 0xF4F4F5, dark: 0x3F3F46)
    /// Indigo 600 and 400. Links, the current mark, and the focus line.
    static let brandNS = color(light: 0x4F46E5, dark: 0x818CF8)
    /// Indigo 100 and 900. The current row of an index.
    static let currentRowNS = color(light: 0xE0E7FF, dark: 0x312E81)
    /// Zinc 900 and white. The text of the current row of an index, and of a highlight.
    static let markInkNS = color(light: 0x18181B, dark: 0xFFFFFF)
    /// Indigo 500 at 26 percent. Selected text on a paper.
    static let paperSelectionNS = NSColor(srgbRed: 0x63 / 255, green: 0x66 / 255, blue: 0xF1 / 255, alpha: 0.26)
    /// Indigo 500. A tab on the edge of the feed paper.
    static let tabNS = hex(0x6366F1)
    /// Indigo 600. The active tab.
    static let tabActiveNS = hex(0x4F46E5)
    /// Indigo 100, and indigo 200 when active. The tab of a pinned folder.
    static let pinTabNS = hex(0xE0E7FF)
    static let pinTabActiveNS = hex(0xC7D2FE)
    /// Indigo 800. The text of a pinned folder tab.
    static let pinTabInkNS = hex(0x3730A3)

    /// Zinc 300 and 600. The dashed slot of a row whose item is open as a paper.
    static let paperSlotNS = color(light: 0xD4D4D8, dark: 0x52525B)
    /// Zinc 400 and 500. The selection bar of a row while the paper has no focus, and the ring of a read article.
    static let paperBarNS = color(light: 0xA1A1AA, dark: 0x71717A)
    /// Indigo 300. The bar beside the notes under a row, and beside a quote.
    static let quoteBarNS = hex(0xA5B4FC)
    /// Zinc 900. The selection bar of a reader page, and the hint key caps on it.
    static let selectionBarNS = hex(0x18181B)

    static let paperSlot = Color(nsColor: paperSlotNS)
    static let paperBar = Color(nsColor: paperBarNS)
    static let quoteBar = Color(nsColor: quoteBarNS)
    static let paper = Color(nsColor: paperNS)
    static let paperInk = Color(nsColor: paperInkNS)
    static let paperMuted = Color(nsColor: paperMutedNS)
    static let paperFaint = Color(nsColor: paperFaintNS)
    static let paperRule = Color(nsColor: paperRuleNS)
    static let paperTint = Color(nsColor: paperTintNS)
    static let brand = Color(nsColor: brandNS)
    static let currentRow = Color(nsColor: currentRowNS)
    static let markInk = Color(nsColor: markInkNS)
    static let tab = Color(nsColor: tabNS)
    static let tabActive = Color(nsColor: tabActiveNS)
    static let pinTab = Color(nsColor: pinTabNS)
    static let pinTabActive = Color(nsColor: pinTabActiveNS)
    static let pinTabInk = Color(nsColor: pinTabInkNS)
    /// The shadow of a tab: 12 percent black, and 18 percent for the active tab.
    static let tabShadowColor = Color.black.opacity(0.12)
    static let activeTabShadowColor = Color.black.opacity(0.18)
    /// `Tokens.writeCardShadow` of September: the shadow of the paper with the
    /// keyboard focus. Black at 18 percent, and 55 percent in the dark.
    static let paperShadowNS = shade(light: 0.18, dark: 0.55)
    /// The shadow of a paper without the keyboard focus. Black at 10 percent, and 40 percent in the dark.
    static let paperRestShadowNS = shade(light: 0.10, dark: 0.40)
    /// The line under the focused paper. Black at 4 percent.
    static let paperEdgeShadowNS = shade(light: 0.04, dark: 0)
    static let paperShadow = Color(nsColor: paperShadowNS)
    static let paperRestShadow = Color(nsColor: paperRestShadowNS)
    static let paperEdgeShadow = Color(nsColor: paperEdgeShadowNS)

    // MARK: Shapes

    /// Corner radius for controls, rows, and selection backgrounds.
    static let radius: CGFloat = 6
    /// Corner radius for cards, the composer, and popovers.
    static let cardRadius: CGFloat = 10

    // MARK: Fonts

    private static let registeredFonts: Void = {
        for name in ["Regular", "Medium", "Italic", "Bold", "BoldItalic"] {
            if let url = resources.url(forResource: "IBMPlexMono-\(name)", withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()

    /// Monospaced text: file sources, file names, and code.
    static func manuscript(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        _ = registeredFonts
        let face = weight >= .semibold ? "Bold" : weight >= .medium ? "Medium" : "Regular"
        return NSFont(name: "IBMPlexMono-\(face)", size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }

    private static let registeredPaperFonts: Void = {
        for name in ["Fraunces", "NotoSans-Regular", "NotoSans-Medium", "NotoSans-SemiBold", "NotoSans-Bold"] {
            if let url = resources.url(forResource: name, withExtension: "woff2") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()

    /// The type scale of the papers. No text on a paper is smaller than 14 points.
    enum PaperSize: CGFloat {
        /// Meta lines, counts, tabs, and buttons.
        case body = 14
        /// Rows of an index and of a list.
        case row = 16
        /// Text that the reader reads.
        case reading = 18
        /// The title of an index.
        case heading = 22
        /// The title of the feed paper.
        case title = 28
    }

    /// Noto Sans, the text of the papers.
    static func paperUINS(_ size: PaperSize, weight: NSFont.Weight = .regular) -> NSFont {
        _ = registeredPaperFonts
        let face = weight >= .bold ? "Bold" : weight >= .semibold ? "SemiBold" : weight >= .medium ? "Medium" : "Regular"
        return NSFont(name: "NotoSans-\(face)", size: size.rawValue) ?? .systemFont(ofSize: size.rawValue, weight: weight)
    }

    static func paperUI(_ size: PaperSize, weight: NSFont.Weight = .regular) -> Font {
        Font(paperUINS(size, weight: weight) as CTFont)
    }

    /// Iowan Old Style, the serif of text that the reader reads: the title of
    /// an article or a file in a list, a quote, and the body of an article.
    static func paperSerifNS(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: "Iowan Old Style",
            .traits: [NSFontDescriptor.TraitKey.weight: weight]
        ])
        if let font = NSFont(descriptor: descriptor, size: size), font.familyName == "Iowan Old Style" { return font }
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        return system.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? system
    }

    static func paperSerif(_ size: CGFloat, weight: NSFont.Weight = .regular) -> Font {
        Font(paperSerifNS(size, weight: weight) as CTFont)
    }

    /// Fraunces at weight 600, the titles of the papers.
    static func paperTitle(_ size: PaperSize) -> Font {
        _ = registeredPaperFonts
        guard let base = NSFont(name: "Fraunces-Regular", size: size.rawValue) else {
            return Font(serifNS(.title).withSize(size.rawValue) as CTFont).weight(.semibold)
        }
        let weightAxis = 0x77676874
        let descriptor = base.fontDescriptor.addingAttributes([.variation: [weightAxis: 600]])
        return Font((NSFont(descriptor: descriptor, size: size.rawValue) ?? base) as CTFont)
    }

    /// The type scale. Each text of the app outside a web page uses one of
    /// these sizes. A larger size marks a higher level of the hierarchy.
    enum TextSize: CGFloat {
        /// Group headers, counts, hints, and times.
        case caption = 11
        /// Meta lines, reasons, tabs, and tool rows.
        case secondary = 12
        /// List rows and controls.
        case body = 13
        /// Notes and agent messages: text that the reader reads, not scans.
        case reading = 15
        /// Pane titles and the palette field.
        case title = 17
        /// The title of an article notebook.
        case display = 24
    }

    /// Control and label text.
    static func uiNS(_ size: TextSize, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size.rawValue, weight: weight)
    }

    /// Serif text that the reader reads, such as the body of a note.
    static func serifNS(_ size: TextSize) -> NSFont {
        let font = NSFont.systemFont(ofSize: size.rawValue)
        return font.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size.rawValue) } ?? font
    }

    static func ui(_ size: TextSize, weight: Font.Weight = .regular) -> Font {
        .system(size: size.rawValue, weight: weight)
    }

    private static func color(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            hex(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        }
    }

    private static func shade(light: CGFloat, dark: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            NSColor.black.withAlphaComponent(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        }
    }

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

/// A button without a bezel that reads as a link in the accent color.
struct TextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PiperTheme.ui(.secondary))
            .foregroundStyle(enabled ? PiperTheme.accent : PiperTheme.faint)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == TextButtonStyle {
    static var text: TextButtonStyle { TextButtonStyle() }
}

/// A 28 by 24 point icon button with an optional active state.
struct IconButton: View {
    let title: String
    let icon: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .frame(width: 28, height: 24)
                .foregroundStyle(active ? PiperTheme.ink : PiperTheme.secondary)
                .background(active ? PiperTheme.selection : .clear, in: RoundedRectangle(cornerRadius: PiperTheme.radius))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// A one-point rule in the separator color.
struct Rule: View {
    var vertical = false
    var body: some View {
        Rectangle().fill(PiperTheme.rule)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// A title and a line under it, centered in a pane that has nothing to show.
struct EmptyPane: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(spacing: 3) {
            Text(title).font(PiperTheme.ui(.reading, weight: .semibold)).foregroundStyle(PiperTheme.secondary)
            if let detail {
                Text(detail).font(PiperTheme.ui(.secondary)).foregroundStyle(PiperTheme.faint)
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
