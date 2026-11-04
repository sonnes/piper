import AppKit
import SwiftUI

enum WikiReadingTheme: String, CaseIterable {
    case paper = "Paper", sepia = "Sepia", slate = "Slate"

    func background(dark: Bool) -> NSColor {
        switch self {
        case .paper: return PiperTheme.readerNS
        case .sepia: return hex(dark ? 0x29231e : 0xf4edde)
        case .slate: return hex(dark ? 0x1e252d : 0xedf1f5)
        }
    }

    private func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
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
