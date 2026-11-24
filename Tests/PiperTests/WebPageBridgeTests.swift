import Captures
import XCTest
@testable import Piper

/// Decodes the sample messages of `web/test/fixtures`. The Vitest file
/// `web/test/bridge.test.ts` checks the editor samples against `Outgoing`.
final class WebPageBridgeTests: XCTestCase {
    private let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("web/test/fixtures")

    private func samples(_ name: String) throws -> [Any] {
        let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [Any])
    }

    func testEachEditorMessageSampleDecodes() throws {
        let messages: [EditorMessage] = try samples("editor-messages.json").map { try WebPageBridge.decode($0) }
        let anchor = NoteAnchor(quote: "less caffeine", block: 1, offset: 14)
        let id = try XCTUnwrap(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        XCTAssertEqual(messages, [
            .ready,
            .change(path: "Tea.md", text: "# Tea\n\nGreen tea.\n"),
            .link(kind: "url", target: "https://example.com/tea"),
            .link(kind: "wiki", target: "Matcha#Shade"),
            .image(path: "Tea.md", type: "image/png", data: "iVBORw0KGgo="),
            .lossy(path: "Tea.md", reasons: ["link titles"]),
            .mark(.explain(anchor)),
            .mark(.define(NoteAnchor(quote: "caffeine", block: 1, offset: 19))),
            .mark(.ask(anchor, question: "How much less?")),
            .mark(.note(anchor, text: "Check the source.")),
            .mark(.capture(text: "less caffeine")),
            .mark(.open(id: id)),
            .mark(.copy(id: id)),
            .mark(.continue(id: id)),
            .mark(.followup(id: id, question: "And green tea?"))
        ])
    }

    func testEachReaderPageMessageSampleDecodes() throws {
        let messages: [ReaderPageMessage] = try samples("reader-messages.json").map { try WebPageBridge.decode($0) }
        let anchor = NoteAnchor(quote: "twice a day", block: 0, offset: 15)
        let id = try XCTUnwrap(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        XCTAssertEqual(messages, [
            .ready,
            .key("t"),
            .position(block: 3, progress: 0.42),
            .link(try XCTUnwrap(URL(string: "https://example.com/tides"))),
            .mark(.highlight(anchor, color: "yellow")),
            .mark(.explain(anchor)),
            .mark(.define(NoteAnchor(quote: "tide", block: 0, offset: 4))),
            .mark(.ask(anchor, question: "Why twice?")),
            .mark(.note(anchor, text: "Check the almanac.")),
            .mark(.capture(text: "twice a day")),
            .mark(.open(id: id)),
            .mark(.copy(id: id)),
            .mark(.continue(id: id)),
            .mark(.followup(id: id, question: "And the moon?"))
        ])
    }

    func testAnUnknownActionDoesNotDecode() {
        XCTAssertThrowsError(try WebPageBridge.decode(["action": "rename"]) as EditorMessage)
    }

    func testACallPassesEachArgumentAsJSON() throws {
        let title: String? = nil
        XCTAssertEqual(try WebPageBridge.script("header", ["May 1 · Saved", title]), #"window.piper.header("May 1 · Saved", null)"#)
        XCTAssertEqual(try WebPageBridge.script("scroll", [40.0]), "window.piper.scroll(40)")
    }
}
