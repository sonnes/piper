import PiperCore
import XCTest
@testable import Piper

@MainActor
final class MessagesTests: XCTestCase {
    func testMessagesBeforeTheToastShowInOrderWhenItIsSet() {
        let messages = Messages()
        messages.show("First")
        messages.report(PiperError("Second"))

        var shown: [String] = []
        messages.present = { shown.append($0.text) }
        XCTAssertEqual(shown, ["First", "Second"])

        messages.show("Third")
        XCTAssertEqual(shown, ["First", "Second", "Third"])
    }
}
