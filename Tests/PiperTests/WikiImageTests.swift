import AppKit
import MarkdownEngine
import XCTest
@testable import Piper

final class WikiImageTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("piper-image-tests-" + UUID().uuidString)
        let assets = root.appendingPathComponent("sources/assets/page")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8,
                                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: assets.appendingPathComponent("figure one.png"))
        try Data("outside".utf8).write(to: root.deletingLastPathComponent().appendingPathComponent("outside-\(root.lastPathComponent).png"))
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent().appendingPathComponent("outside-\(root.lastPathComponent).png"))
    }

    private var provider: VaultImageProvider { VaultImageProvider(root: root, documentPath: "sources/page.md") }

    func testRelativeAndRootedPathsLoadTheImage() throws {
        for name in ["assets/page/figure one.png", "assets/page/figure%20one.png", "/sources/assets/page/figure one.png",
                     "<assets/page/figure one.png>", #"assets/page/figure%20one.png "A title""#] {
            let image = try XCTUnwrap(provider.image(for: EmbeddedImageRequest(name: name)), name)
            XCTAssertEqual(image.size, NSSize(width: 4, height: 3), name)
        }
    }

    func testRemoteMissingAndEscapingPathsLoadNothing() {
        let outside = "../../outside-\(root.lastPathComponent).png"
        for name in ["https://example.com/a.png", "assets/page/missing.png", outside, ""] {
            XCTAssertNil(provider.url(for: name), name)
        }
    }
}
