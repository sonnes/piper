import Captures
import XCTest
@testable import Piper

/// Reads the samples of `web/test/fixtures`. The Vitest file
/// `web/test/bridge.test.ts` checks the editor samples against the types of
/// `web/src/bridge.ts`, and `web/test/anchors.test.ts` checks the anchor
/// samples in the editor.
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
            .link(kind: .url, target: "https://example.com/tea"),
            .link(kind: .wiki, target: "Matcha#Shade"),
            .image(path: "Tea.md", type: "image/png", data: "iVBORw0KGgo="),
            .lossy(path: "Tea.md", reasons: ["link titles"]),
            .error(message: "TypeError: null is not an object"),
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

    func testEachEditorCallEncodesAsItsSample() throws {
        struct Calls: Encodable {
            let open: EditorOpenRequest
            let themes: [EditorTheme]
            let notes: [ReaderPageNote]
        }
        let fonts: [WikiReadingFont] = [.mono, .serif, .sans]
        let appearances: [WikiReadingAppearance] = [.system, .light, .dark]
        let themes = WikiReadingTheme.allCases.indices.map { index in
            EditorTheme(theme: WikiReadingTheme.allCases[index], font: fonts[index], size: 16 + 2 * Double(index),
                        appearance: appearances[index])
        }
        func note(_ id: String, kind: String, color: String = "yellow", block: Int = 0, offset: Int = 5, comment: String = "",
                  origin: String, turns: [ReaderPageNote.Turn] = [], pending: Bool = false, failure: String? = nil,
                  agent: String = "", tools: String = "") -> ReaderPageNote {
            ReaderPageNote(id: id + "-8B86-D011-B42D-00C04FC964FF", kind: kind, color: color, block: block, offset: offset,
                           length: 13, quote: "less caffeine", comment: comment, origin: origin, label: "Ask", turns: turns,
                           pending: pending, failure: failure, agent: agent, tools: tools)
        }
        let calls = Calls(
            open: EditorOpenRequest(
                path: "Tea/Green tea.md", text: "---\ntitle: Green tea\n---\nLess caffeine than [[Matcha]].\n", mode: "rich",
                wikiTargets: [EditorOpenRequest.WikiTarget(path: "Tea/Matcha.md", target: "Tea/Matcha", title: "Matcha")],
                header: "May 1, 2026 · 1 min read · Saved", title: "Green tea"),
            themes: themes,
            notes: [
                note("6F9619FF", kind: "highlight", origin: "Safari · 9:41 AM"),
                note("7F9619FF", kind: "note", color: "green", comment: "Check the source.", origin: "9:42 AM"),
                note("8F9619FF", kind: "question", block: -1, offset: 0, origin: "9:43 AM",
                     turns: [ReaderPageNote.Turn(question: "How much less?", answer: "About half."),
                             ReaderPageNote.Turn(question: nil, answer: "It depends on the leaf.")],
                     pending: true, failure: "The agent stopped.", agent: "Haiku · Claude Code", tools: "Read · WebSearch")
            ])
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(calls)) as? NSDictionary
        let data = try Data(contentsOf: fixtures.appendingPathComponent("editor-calls.json"))
        let sample = try JSONSerialization.jsonObject(with: data) as? NSDictionary
        XCTAssertEqual(encoded, sample)
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

    func testEachAnchorSampleCountsTheSameBlocks() throws {
        struct Sample: Decodable {
            let name: String
            let markdown: String
            let quote: String
            let occurrence: Int
            let anchor: NoteAnchor
        }
        let data = try Data(contentsOf: fixtures.appendingPathComponent("anchors.json"))
        for sample in try JSONDecoder().decode([Sample].self, from: data) {
            let blocks = WikiMarkdown.textBlocks(sample.markdown).map(\.text)
            var copies: [NoteAnchor] = []
            for (index, text) in blocks.enumerated() {
                var rest = NSRange(location: 0, length: (text as NSString).length)
                while case let found = (text as NSString).range(of: sample.quote, range: rest), found.location != NSNotFound {
                    copies.append(NoteAnchor(quote: sample.quote, block: index, offset: found.location))
                    rest = NSRange(location: NSMaxRange(found), length: rest.length - (NSMaxRange(found) - rest.location))
                }
            }
            XCTAssertEqual(copies.indices.contains(sample.occurrence) ? copies[sample.occurrence] : nil, sample.anchor, sample.name)
            XCTAssertEqual(sample.anchor.locate(in: blocks), sample.anchor, sample.name)
        }
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
