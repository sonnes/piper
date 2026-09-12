import AppKit
import CoreText
import SwiftUI

enum PiperTheme {
    static let resources: Bundle = {
        if let url = Bundle.main.url(forResource: "Piper_Piper", withExtension: "bundle"), let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }()
    static let mark = resources.image(forResource: "Sandpiper")

    static let pageNS = color(light: 0xFCFCFA, dark: 0x18191A)
    static let surfaceNS = color(light: 0xF1F1ED, dark: 0x212224)
    static let inkNS = color(light: 0x232323, dark: 0xEDEDE9)
    static let secondaryNS = color(light: 0x686867, dark: 0xADAEAC)
    static let accentNS = color(light: 0x2455F5, dark: 0x6D9BFF)
    static let selectionNS = color(light: 0xE4EAFF, dark: 0x25324E)
    static let ruleNS = color(light: 0xDCDCD7, dark: 0x3B3D3E)
    static let controlNS = color(light: 0x868680, dark: 0x838781)
    static let successNS = color(light: 0x49654B, dark: 0xA3C39F)
    static let dangerNS = color(light: 0xA03432, dark: 0xEFA5A0)

    static let page = Color(nsColor: pageNS)
    static let surface = Color(nsColor: surfaceNS)
    static let ink = Color(nsColor: inkNS)
    static let secondary = Color(nsColor: secondaryNS)
    static let accent = Color(nsColor: accentNS)
    static let selection = Color(nsColor: selectionNS)
    static let rule = Color(nsColor: ruleNS)
    static let control = Color(nsColor: controlNS)
    static let success = Color(nsColor: successNS)
    static let danger = Color(nsColor: dangerNS)

    private static func color(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }

    private static let registeredFonts: Void = {
        for name in ["Regular", "Medium", "Italic", "Bold", "BoldItalic"] {
            if let url = resources.url(forResource: "IBMPlexMono-\(name)", withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()

    static func manuscript(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        _ = registeredFonts
        let face = weight >= .semibold ? "Bold" : weight >= .medium ? "Medium" : "Regular"
        return NSFont(name: "IBMPlexMono-\(face)", size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }
}
