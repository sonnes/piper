import AppKit
import SwiftUI

enum WikiReadingTheme: String, CaseIterable {
    case paper = "Paper", sepia = "Sepia", slate = "Slate"

    func background(dark: Bool) -> NSColor {
        switch self {
        case .paper: return PiperTheme.paperNS
        case .sepia: return PiperTheme.hex(dark ? 0x29231e : 0xf4edde)
        case .slate: return PiperTheme.hex(dark ? 0x1e252d : 0xedf1f5)
        }
    }
}

enum WikiReadingFont: String, CaseIterable {
    case mono = "Monospace", serif = "Serif", sans = "Sans Serif"
}

enum WikiReadingAppearance: String, CaseIterable {
    case system = "System", light = "Light", dark = "Dark"
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

/// The reading preferences of a Markdown file, with their defaults. Settings
/// and the file paper read the same four preferences through this type.
struct ReadingSettings: DynamicProperty {
    static let defaultSize = 18.0
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
