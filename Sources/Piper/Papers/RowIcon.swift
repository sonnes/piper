import AppKit
import UniformTypeIdentifiers

/// The icon at the start of a row of an index.
enum RowIcon: Equatable {
    /// A Lucide SVG from the resources, in one color.
    case glyph(String, NSColor)
    /// A colored dot, for a capture section.
    case dot(NSColor)
    /// A rounded tile with a letter, for a top-level folder.
    case monogram(String, NSColor)
    /// A rounded tile with a white glyph, for a sessions folder.
    case tile(String, NSColor)
    /// The icon of a site, for a feed.
    case favicon(Data)

    /// The row icon of a file, by its kind. The name is an SVG in the resources, after `glyph-`.
    static func fileIcon(_ name: String) -> String {
        let type = UTType(filenameExtension: (name as NSString).pathExtension)
        if ["md", "markdown"].contains((name as NSString).pathExtension.lowercased()) { return "note" }
        if type?.conforms(to: .image) == true { return "image" }
        if type?.conforms(to: .html) == true { return "web" }
        return "file"
    }

    /// The color of the section dot or folder tile at a position in its group.
    /// Neighbors get different colors, and the colors repeat after the last one.
    static func tagColor(at index: Int) -> NSColor {
        PiperTheme.tagsNS[max(index, 0) % PiperTheme.tagsNS.count]
    }

    /// The section that the Inbox stream adds to when no section is picked.
    static let inboxSection = "Inbox"

    /// The dot color of a capture section. Inbox has no dot, so the colors
    /// start at the first other section.
    static func sectionColor(_ section: String, in sections: [String]) -> NSColor {
        tagColor(at: sections.filter { $0 != inboxSection }.firstIndex(of: section) ?? 0)
    }

    /// The letter on a folder tile: the first letter or digit of the name, in capitals.
    static func monogram(_ name: String) -> String {
        name.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "•"
    }

    /// The tile of the folder at a position in the list of folders.
    static func folderIcon(_ name: String, at index: Int) -> RowIcon {
        .monogram(monogram(name), tagColor(at: index))
    }

    /// The image of the icon. A drawn image resolves its colors each time it
    /// draws, so it follows the dark appearance.
    @MainActor
    func image(side: CGFloat) -> NSImage? {
        if case .glyph(let name, _) = self { return RowIcon.glyph(name) }
        var tileGlyph: NSImage?
        if case .tile(let name, _) = self, let glyph = RowIcon.glyph(name) {
            // Paint white through the alpha of the template, in its own image so
            // that the fill does not cover the tile.
            tileGlyph = NSImage(size: glyph.size, flipped: false) { rect in
                glyph.draw(in: rect)
                NSColor.white.set()
                rect.fill(using: .sourceAtop)
                return true
            }
        }
        let size = NSSize(width: side, height: side)
        return NSImage(size: size, flipped: false) { rect in
            let radius = side * AppDefaults.RowIcon.tileCornerFraction
            switch self {
            case .glyph:
                break
            case .dot(let color):
                let diameter = side * AppDefaults.RowIcon.dotFraction
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2,
                                            width: diameter, height: diameter)).fill()
            case .monogram(let letter, let color):
                color.setFill()
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
                let text = NSAttributedString(string: letter, attributes: [
                    .font: NSFont.systemFont(ofSize: side * 0.6, weight: .bold),
                    .foregroundColor: NSColor.white
                ])
                let textSize = text.size()
                text.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
            case .favicon(let data):
                guard let icon = RowIcon.favicon(data) else { break }
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
                icon.draw(in: rect)
            case .tile(_, let color):
                color.setFill()
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
                guard let glyph = tileGlyph else { break }
                let glyphSide = side * AppDefaults.RowIcon.tileSymbolFraction
                let glyphRect = NSRect(x: rect.midX - glyphSide / 2, y: rect.midY - glyphSide / 2, width: glyphSide, height: glyphSide)
                glyph.draw(in: glyphRect)
            }
            return true
        }
    }

    private static var glyphs: [String: NSImage] = [:]
    private static var favicons: [Data: NSImage] = [:]

    /// The image of a site icon, decoded once.
    @MainActor
    static func favicon(_ data: Data) -> NSImage? {
        if let image = favicons[data] { return image }
        guard let image = NSImage(data: data) else { return nil }
        favicons[data] = image
        return image
    }

    /// A template image from `glyph-<name>.svg` in the resources.
    @MainActor
    static func glyph(_ name: String) -> NSImage? {
        if let image = glyphs[name] { return image }
        guard let url = PiperTheme.resources.url(forResource: "glyph-\(name)", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        glyphs[name] = image
        return image
    }
}
