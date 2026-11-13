import Feeds
import SwiftUI

/// The icon of a site, or a tile with the first letter of its title while the
/// site has no icon.
struct SiteIcon: View {
    let favicons: FaviconStore
    let host: String
    let title: String
    /// The place of the site in its list, for the color of the letter tile.
    let index: Int
    var side: CGFloat = AppDefaults.Sidebar.imageSize

    private var radius: CGFloat { side * AppDefaults.Sidebar.tileCornerFraction }

    var body: some View {
        if let data = favicons.icon(for: host), let image = SidebarIcon.favicon(data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: radius))
                .accessibilityHidden(true)
        } else {
            Text(SidebarOutline.monogram(title))
                .font(.system(size: side * 0.6, weight: .bold))
                .foregroundStyle(PiperTheme.onAccent)
                .frame(width: side, height: side)
                .background(Color(nsColor: SidebarOutline.tagColor(at: index)), in: RoundedRectangle(cornerRadius: radius))
                .accessibilityHidden(true)
        }
    }
}
