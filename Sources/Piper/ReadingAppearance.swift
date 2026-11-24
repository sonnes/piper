import AppKit
import SwiftUI

enum WikiReadingTheme: String, CaseIterable, Encodable {
    case paper = "Paper", sepia = "Sepia", slate = "Slate"

    func background(dark: Bool) -> NSColor {
        switch self {
        case .paper: return PiperTheme.paperNS
        case .sepia: return PiperTheme.hex(dark ? 0x29231e : 0xf4edde)
        case .slate: return PiperTheme.hex(dark ? 0x1e252d : 0xedf1f5)
        }
    }

    /// The background as a CSS color, such as `#f4edde`, for the editor page.
    func cssBackground(dark: Bool) -> String {
        var rgb = NSColor.black
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            rgb = background(dark: dark).usingColorSpace(.sRGB) ?? .black
        }
        let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { Int(($0 * 255).rounded()) }
        return "#" + channels.map { String(format: "%02x", $0) }.joined()
    }
}

enum WikiReadingFont: String, CaseIterable, Encodable {
    case mono = "Monospace", serif = "Serif", sans = "Sans Serif"
}

enum WikiReadingAppearance: String, CaseIterable, Encodable {
    case system = "System", light = "Light", dark = "Dark"
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

/// The reading preferences of a Markdown file, with their defaults. Settings
/// and the file paper read the same four preferences through this type.
struct ReadingSettings: DynamicProperty {
    static let defaultSize = 18.0
    /// The type sizes that Settings offers.
    static let sizes = 13.0...24.0
    static let defaultTheme = WikiReadingTheme.paper
    static let defaultFont = WikiReadingFont.serif
    static let defaultAppearance = WikiReadingAppearance.system

    @AppStorage(AppDefaults.Key.readerSize) var size = defaultSize
    @AppStorage(AppDefaults.Key.readerTheme) var theme = defaultTheme
    @AppStorage(AppDefaults.Key.readerFont) var font = defaultFont
    @AppStorage(AppDefaults.Key.readerAppearance) var appearance = defaultAppearance

    func reset() {
        size = Self.defaultSize
        theme = Self.defaultTheme
        font = Self.defaultFont
        appearance = Self.defaultAppearance
    }
}
