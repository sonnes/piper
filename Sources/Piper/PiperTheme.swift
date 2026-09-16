import AppKit
import CoreText
import SwiftUI

/// The colors, fonts, and shapes of the application.
///
/// Text and surfaces use the system colors, so they follow the dark appearance
/// and the contrast settings of the reader. The accent is the one saturated
/// color, and it marks selection with focus, links, unread files, and the
/// primary button.
enum PiperTheme {
    static let resources: Bundle = {
        if let url = Bundle.main.url(forResource: "Piper_Piper", withExtension: "bundle"), let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }()
    static let mark = resources.image(forResource: "Sandpiper")

    // MARK: Colors

    /// The background of the list and the detail pane.
    static let pageNS = NSColor.textBackgroundColor
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
    static let warningNS = NSColor.systemOrange
    static let dangerNS = NSColor.systemRed

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
    static let danger = Color(nsColor: dangerNS)
    /// A row under the pointer.
    static let hover = Color.primary.opacity(0.045)
    /// The ring around a focused field.
    static let focusRing = accent.opacity(0.45)

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

    /// Control and label text.
    static func uiNS(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    private static func color(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            hex(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
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
            .font(PiperTheme.ui(12))
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
            Text(title).font(PiperTheme.ui(15, weight: .semibold)).foregroundStyle(PiperTheme.secondary)
            if let detail {
                Text(detail).font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.faint)
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
