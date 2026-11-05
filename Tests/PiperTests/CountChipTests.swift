import AppKit
import SwiftUI
import XCTest
@testable import Piper

@MainActor
final class CountChipTests: XCTestCase {
    /// A narrow meta line cuts the site name. The chip keeps its full text.
    func testChipKeepsItsWidthInANarrowRow() {
        let chip = NSHostingController(rootView: CountChip(text: "3 highlights · 2 notes", open: false))
        let ideal = chip.sizeThatFits(in: CGSize(width: 1000, height: 100))
        let narrow = chip.sizeThatFits(in: CGSize(width: 20, height: 100))
        XCTAssertGreaterThan(ideal.width, 100)
        XCTAssertEqual(narrow.width, ideal.width, accuracy: 0.5)
    }
}
