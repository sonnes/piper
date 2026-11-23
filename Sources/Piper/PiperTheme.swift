import AppKit
import CoreText
import SwiftUI

/// The shared colors, fonts, and type sizes of the application. A feature
/// keeps its own colors in its `Metrics`.
///
/// The app has one palette: the zinc and indigo of September. Each color has
/// a light and a dark value. The brand indigo is the one saturated color, and
/// it marks selection with focus, links, and the primary button.
enum PiperTheme {
    static let resources: Bundle = {
        if let url = Bundle.main.url(forResource: "Piper_Piper", withExtension: "bundle"), let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }()
    static let mark = resources.image(forResource: "Sandpiper")

    // MARK: Colors

    static let warningNS = NSColor.systemOrange
    static let dangerNS = NSColor.systemRed
    static let successNS = NSColor.systemGreen

    // These colors use the Tailwind CSS palette: shade 500 in the light
    // appearance and shade 400 in the dark, unless a comment names others.

    /// Amber 500 and 400. A kept article.
    static let starNS = color(light: 0xF59E0B, dark: 0xFBBF24)
    /// Orange. The tile of a sessions folder, its count of sessions that wait, and the mark of Claude Code.
    static let claudeNS = color(light: 0xF97316, dark: 0xFB923C)
    /// Teal 600 and 400. The mark of an agent that speaks ACP.
    static let acpAgentNS = color(light: 0x0D9488, dark: 0x2DD4BF)

    /// Yellow 400. The bar beside a highlight.
    static let markYellow = Color(nsColor: hex(0xFACC15))

    static let warning = Color(nsColor: warningNS)
    /// The fill of the bar over the editor when Piper stopped saving.
    static let warningFill = warning.opacity(0.14)
    static let danger = Color(nsColor: dangerNS)
    static let success = Color(nsColor: successNS)
    static let claude = Color(nsColor: claudeNS)
    static let star = Color(nsColor: starNS)
    static let acpAgent = Color(nsColor: acpAgentNS)
    /// The ring around a focused field.
    static let focusRing = brand.opacity(0.45)
    /// Text and symbols on an accent fill, such as a check or a toast button.
    static let onAccent = Color.white
    /// Faint text on an accent or warning fill, such as the shortcut in the Needs You pill.
    static let onAccentSecondary = onAccent.opacity(0.8)

    // MARK: Papers

    // The papers use the zinc and indigo of September. Each color names the
    // Tailwind shade for the light appearance, then for the dark.

    /// White, and zinc 800.
    static let paperNS = color(light: 0xFFFFFF, dark: 0x27272A)
    /// Zinc 100 and 900. The desk behind the papers.
    static let deskNS = color(light: 0xF4F4F5, dark: 0x18181B)
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
    /// Indigo 500 at 26 percent. Selected text on a paper.
    static let paperSelectionNS = NSColor(srgbRed: 0x63 / 255, green: 0x66 / 255, blue: 0xF1 / 255, alpha: 0.26)
    /// Indigo 600 in both appearances. The check of a done capture, and the fill of a pill.
    static let indigoNS = hex(0x4F46E5)

    /// Zinc 300 and 600. The dashed slot of a row whose item is open as a paper.
    static let paperSlotNS = color(light: 0xD4D4D8, dark: 0x52525B)
    /// Zinc 400 and 500. The selection bar of a row while the paper has no focus, and the ring of a read article.
    static let paperBarNS = color(light: 0xA1A1AA, dark: 0x71717A)
    /// Indigo 300. The bar beside the notes under a row, and beside a quote.
    static let quoteBarNS = hex(0xA5B4FC)

    static let paperSlot = Color(nsColor: paperSlotNS)
    static let quoteBar = Color(nsColor: quoteBarNS)
    static let paper = Color(nsColor: paperNS)
    static let paperInk = Color(nsColor: paperInkNS)
    static let paperMuted = Color(nsColor: paperMutedNS)
    static let paperFaint = Color(nsColor: paperFaintNS)
    static let paperRule = Color(nsColor: paperRuleNS)
    static let paperTint = Color(nsColor: paperTintNS)
    static let brand = Color(nsColor: brandNS)
    static let currentRow = Color(nsColor: currentRowNS)
    static let indigo = Color(nsColor: indigoNS)
    /// `Tokens.writeCardShadow` of September: the shadow of the paper with the
    /// keyboard focus. Black at 18 percent, and 55 percent in the dark.
    static let paperShadowNS = shade(light: 0.18, dark: 0.55)
    /// The shadow of a paper without the keyboard focus. Black at 10 percent, and 40 percent in the dark.
    static let paperRestShadowNS = shade(light: 0.10, dark: 0.40)
    /// The line under the focused paper. Black at 4 percent.
    static let paperEdgeShadowNS = shade(light: 0.04, dark: 0)
    static let paperShadow = Color(nsColor: paperShadowNS)

    // MARK: Lists And Chrome

    // The lists and the chrome of the papers follow the Apple apps, such as
    // Mail and Reminders. Text has three levels: `paperInk` for a row and a
    // title, `paperMuted` for a meta line and a group header, and `paperFaint`
    // for a count, an empty state, and a done row.

    /// The band around a paper that resizes it: black at the least alpha
    /// that the window server counts, so that the band takes a click.
    static let resizeBand = NSColor(white: 0, alpha: 1 / 255)
    /// The fill of a row under the pointer: zinc 900 at 4 percent, and white at 6 percent.
    static let rowHoverNS = NSColor(name: nil) { appearance in
        isDark(appearance)
            ? NSColor.white.withAlphaComponent(0.06) : NSColor(srgbRed: 0x18 / 255, green: 0x18 / 255, blue: 0x1B / 255, alpha: 0.04)
    }
    static let rowHover = Color(nsColor: rowHoverNS)
    /// The fill of the selected row while its paper has the focus: indigo at
    /// 14 percent, and indigo 400 at 24 percent in the dark.
    static let rowSelectionNS = NSColor(name: nil) { appearance in
        isDark(appearance)
            ? NSColor(srgbRed: 0x81 / 255, green: 0x8C / 255, blue: 0xF8 / 255, alpha: 0.24)
            : NSColor(srgbRed: 0x4F / 255, green: 0x46 / 255, blue: 0xE5 / 255, alpha: 0.12)
    }
    static let rowSelection = Color(nsColor: rowSelectionNS)

    /// The fill of a row: the selection, the fill under the pointer, or none.
    /// The selection of a paper without the focus is gray, as in Finder.
    static func rowFill(selected: Bool, focused: Bool, hovered: Bool) -> Color {
        if selected { return focused ? rowSelection : paperTint }
        return hovered ? rowHover : .clear
    }

    /// The soft shadow under the chosen lens and under a floating bar of Today.
    static let lensShadow = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance)
            ? NSColor.black.withAlphaComponent(0.4) : NSColor.black.withAlphaComponent(0.12)
    })

    /// The thin line around a floating bar, such as the toolbar of a reader paper.
    static let barEdgeNS = NSColor(name: nil) { appearance in
        isDark(appearance)
            ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.08)
    }
    static let barEdge = Color(nsColor: barEdgeNS)
    /// The two shadows of a floating bar: a contact shadow and a soft shadow.
    static let barContactShadow = Color.black.opacity(0.08)
    static let barSoftShadow = Color.black.opacity(0.12)
    static let paperRestShadow = Color(nsColor: paperRestShadowNS)
    static let paperEdgeShadow = Color(nsColor: paperEdgeShadowNS)

    // MARK: Shapes

    /// Corner radius for cards, the composer, and popovers.
    static let cardRadius: CGFloat = 10

    // MARK: Fonts

    private static let registeredFonts: Void = {
        for name in ["Regular", "Medium", "Bold"] {
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

    /// The type scale of the app. No size of the scale is smaller than 14 points.
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

    /// The title of a row in every list of the papers: Noto Sans at the row
    /// size, semibold for a new item. Titles never use the serif.
    static func listTitle(bold: Bool = false) -> Font {
        paperUI(.row, weight: bold ? .semibold : .regular)
    }

    /// Iowan Old Style, the serif of text that the reader reads: a quote and
    /// the body of an article.
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
            return Font.system(size: size.rawValue, weight: .semibold, design: .serif)
        }
        let weightAxis = 0x77676874
        let descriptor = base.fontDescriptor.addingAttributes([.variation: [weightAxis: 600]])
        return Font((NSFont(descriptor: descriptor, size: size.rawValue) ?? base) as CTFont)
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func color(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            hex(isDark(appearance) ? dark : light)
        }
    }

    static func shade(light: CGFloat, dark: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            NSColor.black.withAlphaComponent(isDark(appearance) ? dark : light)
        }
    }

    static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
