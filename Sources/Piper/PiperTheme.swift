import AppKit
import CoreText
import SwiftUI
import Captures

/// The visual style of the whole application. Vault is the default. Page is the switchable alternative.
enum PiperStyle: String, CaseIterable {
    case vault = "Vault", page = "Page"

    static let key = "piperStyle"
    static var current: PiperStyle {
        PiperStyle(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .vault
    }

    var summary: String {
        switch self {
        case .vault: return "System type for controls, tinted panes, and bordered buttons."
        case .page: return "One monospace face everywhere, flat surfaces, and controls as words."
        }
    }
}

enum PiperTheme {
    static let resources: Bundle = {
        if let url = Bundle.main.url(forResource: "Piper_Piper", withExtension: "bundle"), let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }()
    static let mark = resources.image(forResource: "Sandpiper")

    static var style: PiperStyle { PiperStyle.current }
    static var isPage: Bool { style == .page }

    // Vault takes the system colors. They carry the dark appearance and the
    // reader's contrast settings at no cost. Page keeps its own flat palette.
    static let pageNS = system(.textBackgroundColor, page: (0xFCFCFA, 0x18191A))
    static let surfaceNS = system(.windowBackgroundColor, page: (0xFCFCFA, 0x18191A))
    static let hoverNS = color(vault: (0xECECEE, 0x2C2C2C), page: (0xF1F1ED, 0x212224))
    static let inkNS = system(.labelColor, page: (0x232323, 0xEDEDE9))
    static let secondaryNS = system(.secondaryLabelColor, page: (0x686867, 0x8E8F8C))
    static let faintNS = system(.tertiaryLabelColor, page: (0xB4B4AE, 0x5C5D5B))
    /// The accent color: srgb 0.031 0.416 0.933, and 0.369 0.620 0.957 in the dark.
    static let accentNS = color(vault: (0x086AEE, 0x5E9EF4), page: (0x086AEE, 0x5E9EF4))
    static let selectionNS = color(vault: (0xEEF1FA, 0x2A3245), page: (0xEEF2FF, 0x1F2636))
    /// The row separator: white 0.9 in gray gamma 2.2.
    static let ruleNS = color(vault: (0xE5E5E5, 0x333333), page: (0xE5E5E5, 0x2A2B2C))
    static let controlNS = color(vault: (0x868680, 0x838781), page: (0x868680, 0x838781))
    /// The status bar background: srgb 0.94 in all three channels.
    static let statusBarNS = color(vault: (0xF0F0F0, 0x2A2A2A), page: (0xF0F0F0, 0x232323))
    /// `rgba(255,0,0,.6)`, darkened so that a
    /// 12-point bold label keeps its contrast.
    static let feedLinkNS = color(vault: (0xC23C3C, 0xE07C7C), page: (0xC23C3C, 0xE07C7C))
    static let successNS = color(vault: (0x49654B, 0xA3C39F), page: (0x49654B, 0xA3C39F))
    static let dangerNS = color(vault: (0xA03432, 0xEFA5A0), page: (0xA03432, 0xEFA5A0))
    static let warningNS = color(vault: (0xE0A125, 0xE0A125), page: (0xE0A125, 0xE0A125))

    static let page = Color(nsColor: pageNS)
    static let surface = Color(nsColor: surfaceNS)
    static let hover = Color(nsColor: hoverNS)
    static let ink = Color(nsColor: inkNS)
    static let secondary = Color(nsColor: secondaryNS)
    static let faint = Color(nsColor: faintNS)
    static let accent = Color(nsColor: accentNS)
    static let selection = Color(nsColor: selectionNS)
    static let rule = Color(nsColor: ruleNS)
    static let control = Color(nsColor: controlNS)
    static let statusBar = Color(nsColor: statusBarNS)
    static let feedLink = Color(nsColor: feedLinkNS)
    static let success = Color(nsColor: successNS)
    static let danger = Color(nsColor: dangerNS)
    static let warning = Color(nsColor: warningNS)

    /// The fill of a card on the capture panel.
    ///
    /// The panel draws over the desktop through a vibrant material, so a card
    /// carries a translucent fill and reads as a sheet of paper on top of it.
    static let card = Color(nsColor: system(.textBackgroundColor, page: (0xFFFFFF, 0x202124))).opacity(0.7)

    /// The corner radius of a card and of the panel itself.
    static let cardRadius: CGFloat = 14

    /// The fill behind a selected row in the source list and the timeline.
    ///
    /// The fill is the system selection, not the accent color. A pane that
    /// does not hold the keyboard focus keeps the gray fill, which is what every
    /// row of a SwiftUI pane does here.
    static let rowSelection = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)

    /// The unread count badge and its text color.
    static let badge = Color(white: 0, opacity: 0.5)
    static let badgeText = Color(white: 1, opacity: 0.9)

    /// Corner radius for controls and selection backgrounds.
    static var radius: CGFloat { isPage ? 3 : 5 }

    private static func color(vault: (UInt32, UInt32), page: (UInt32, UInt32)) -> NSColor {
        NSColor(name: nil) { appearance in
            let pair = isPage ? page : vault
            return hex(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? pair.1 : pair.0)
        }
    }

    /// A system color in Vault, and a flat color in Page.
    private static func system(_ color: NSColor, page: (UInt32, UInt32)) -> NSColor {
        NSColor(name: nil) { appearance in
            guard isPage else { return color }
            return hex(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? page.1 : page.0)
        }
    }

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    private static let registeredFonts: Void = {
        for name in ["Regular", "Medium", "Italic", "Bold", "BoldItalic"] {
            if let url = resources.url(forResource: "IBMPlexMono-\(name)", withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()

    /// Note and document text. Always IBM Plex Mono.
    static func manuscript(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        _ = registeredFonts
        let face = weight >= .semibold ? "Bold" : weight >= .medium ? "Medium" : "Regular"
        return NSFont(name: "IBMPlexMono-\(face)", size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Control and label text. System font in Vault, IBM Plex Mono in Page.
    static func uiNS(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        isPage ? manuscript(size: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
    }

    static func ui(_ size: CGFloat, weight: NSFont.Weight = .regular) -> Font {
        Font(uiNS(size, weight: weight))
    }
}

/// Bordered button in Vault. A plain word in Page.
struct PiperButtonStyle: ButtonStyle {
    var prominent = false
    var ghost = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(PiperTheme.ui(12, weight: prominent ? .medium : .regular))
            .lineLimit(1)
        Group {
            if PiperTheme.isPage {
                label
                    .padding(.horizontal, 4).padding(.vertical, 5)
                    .foregroundStyle(enabled ? (prominent ? PiperTheme.accent : PiperTheme.ink) : PiperTheme.secondary)
            } else {
                label
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .foregroundStyle(enabled ? (prominent ? Color.white : PiperTheme.ink) : PiperTheme.secondary)
                    .background(prominent && enabled ? PiperTheme.accent : .clear, in: RoundedRectangle(cornerRadius: PiperTheme.radius))
                    .overlay {
                        if !prominent && !ghost {
                            RoundedRectangle(cornerRadius: PiperTheme.radius).strokeBorder(PiperTheme.rule, lineWidth: 1)
                        }
                    }
            }
        }
        .contentShape(Rectangle())
        .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A 26-point icon button with an optional active state.
struct IconButton: View {
    let title: String
    let icon: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
                .foregroundStyle(active ? PiperTheme.ink : PiperTheme.secondary)
                .background(active ? PiperTheme.hover : .clear, in: RoundedRectangle(cornerRadius: PiperTheme.radius))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// A one-point rule in the theme's rule color.
struct Rule: View {
    var vertical = false
    var body: some View {
        Rectangle().fill(PiperTheme.rule)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}
