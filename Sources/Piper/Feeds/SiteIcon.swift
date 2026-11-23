import AppKit
import Feeds
import PiperCore
import SwiftUI

/// The icon of a site, or a tile with the first letter of its title while the
/// site has no icon.
struct SiteIcon: View {
    let favicons: FaviconStore
    let host: String
    let title: String
    var side: CGFloat = Metrics.size

    private var radius: CGFloat { side * Metrics.tileCornerFraction }

    var body: some View {
        if let data = favicons.icon(for: host), let image = Self.favicon(data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: radius))
                .accessibilityHidden(true)
        } else {
            Text(Self.monogram(title))
                .font(.system(size: side * 0.6, weight: .bold))
                .foregroundStyle(PiperTheme.onAccent)
                .frame(width: side, height: side)
                .background(Color(nsColor: Self.tagColor(for: host)), in: RoundedRectangle(cornerRadius: radius))
                .accessibilityHidden(true)
        }
    }
}

extension SiteIcon {
    enum Metrics {
        static let size: CGFloat = 18
        /// The corner radius of a tile, as a fraction of its side.
        static let tileCornerFraction: CGFloat = 0.28
        /// The colors of the letter tiles of sites, in the order of the rows:
        /// violet, emerald, orange, sky, rose, lime, fuchsia, and amber. Rows
        /// next to each other get hues that are far apart. Each color is the
        /// Tailwind shade 500 in the light appearance and 400 in the dark.
        static let tags: [NSColor] = [
            PiperTheme.color(light: 0x8B5CF6, dark: 0xA78BFA), PiperTheme.color(light: 0x10B981, dark: 0x34D399),
            PiperTheme.color(light: 0xF97316, dark: 0xFB923C), PiperTheme.color(light: 0x0EA5E9, dark: 0x38BDF8),
            PiperTheme.color(light: 0xF43F5E, dark: 0xFB7185), PiperTheme.color(light: 0x84CC16, dark: 0xA3E635),
            PiperTheme.color(light: 0xD946EF, dark: 0xE879F9), PiperTheme.color(light: 0xF59E0B, dark: 0xFBBF24)
        ]
    }

    /// The color of the letter tile of a site. One site has one color in every list.
    static func tagColor(for host: String) -> NSColor {
        let colors = Metrics.tags
        return colors[Site(host: host).key.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 997 } % colors.count]
    }

    /// The letter on a tile: the first letter or digit of the name, in capitals.
    static func monogram(_ name: String) -> String {
        name.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "•"
    }

    private static var favicons: [Data: NSImage] = [:]

    /// The image of a site icon, decoded once.
    @MainActor
    static func favicon(_ data: Data) -> NSImage? {
        if let image = favicons[data] { return image }
        guard let image = NSImage(data: data) else { return nil }
        favicons[data] = image
        return image
    }
}
