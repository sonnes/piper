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
    var side: CGFloat = AppDefaults.SiteIcon.size

    private var radius: CGFloat { side * AppDefaults.SiteIcon.tileCornerFraction }

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
    /// The color of the letter tile of a site. One site has one color in every list.
    static func tagColor(for host: String) -> NSColor {
        let colors = PiperTheme.tagsNS
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
