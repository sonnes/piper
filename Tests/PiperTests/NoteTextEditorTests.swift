import AppKit
import SwiftUI
import XCTest
@testable import Piper

@MainActor
final class NoteTextEditorTests: XCTestCase {
    /// The system setting for smart quotes must not reach a note, because a note can hold code.
    func testNoteEditorKeepsQuotesAndDashesAsTyped() throws {
        UserDefaults.standard.set(true, forKey: "NSAutomaticQuoteSubstitutionEnabled")
        UserDefaults.standard.set(true, forKey: "NSAutomaticDashSubstitutionEnabled")
        defer {
            UserDefaults.standard.removeObject(forKey: "NSAutomaticQuoteSubstitutionEnabled")
            UserDefaults.standard.removeObject(forKey: "NSAutomaticDashSubstitutionEnabled")
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: NoteTextEditor(text: .constant("let s = \"a\""), font: .systemFont(ofSize: 13)))
        window.layoutIfNeeded()
        let editor = try XCTUnwrap(Self.textView(in: try XCTUnwrap(window.contentView)))
        XCTAssertEqual(editor.string, "let s = \"a\"")
        XCTAssertFalse(editor.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(editor.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(editor.isAutomaticTextReplacementEnabled)
    }

    private static func textView(in view: NSView) -> NSTextView? {
        (view as? NSTextView) ?? view.subviews.lazy.compactMap { textView(in: $0) }.first
    }
}

@MainActor
final class CaptureEditorCommandTests: XCTestCase {

    /// The session composer once kept the view from its first appearance, so
    /// Return sent to that session. The coordinator must call the newest handler.
    func testCommandsReachTheNewestHandler() {
        var calls: [String] = []
        func editor(_ name: String) -> CaptureEditor {
            CaptureEditor(text: .constant(""), focused: .constant(true), placeholder: "",
                          command: { _ in calls.append(name); return true })
        }
        let coordinator = editor("first").makeCoordinator()
        coordinator.parent = editor("second")

        XCTAssertTrue(coordinator.textView(NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(calls, ["second"])
        XCTAssertFalse(CaptureEditor(text: .constant(""), focused: .constant(false), placeholder: "")
            .makeCoordinator().textView(NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
    }
}
