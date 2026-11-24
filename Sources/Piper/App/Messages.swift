import AppKit
import Captures
import Observation
import PiperCore

/// One line for the reader, with an optional button.
struct Message {

    /// The button of a message, such as Undo.
    struct Action {
        let title: String
        let perform: () -> Void
    }

    let text: String
    let action: Action?
    let isError: Bool
}

/// The one channel for the messages of the app. The toast shows each message.
///
/// Models and stores throw errors and return what they made. The caller picks
/// the words and gives them here.
@MainActor @Observable
final class Messages {
    private(set) var last: Message?

    /// Shows a message. The app sets it to the toast. Messages posted before
    /// the app sets it wait, and show in order when it is set.
    @ObservationIgnored var present: ((Message) -> Void)? {
        didSet { flush() }
    }

    @ObservationIgnored private var waiting: [Message] = []

    func show(_ text: String, undo: (() -> Void)? = nil) {
        show(text, action: undo.map { Message.Action(title: "Undo", perform: $0) })
    }

    func show(_ text: String, action: Message.Action?) {
        post(Message(text: text, action: action, isError: false))
    }

    /// Puts the text on the clipboard and shows "Copied", or reports that the clipboard did not take it.
    func copy(_ text: String, to pasteboard: NSPasteboard = .general) {
        if Clipboard.copy(text, to: pasteboard) {
            show("Copied")
        } else {
            report(PiperError("Cannot write to the clipboard."))
        }
    }

    func report(_ error: Error) {
        post(Message(text: error.localizedDescription, action: nil, isError: true))
    }

    private func post(_ message: Message) {
        last = message
        if let present {
            present(message)
        } else {
            waiting.append(message)
        }
    }

    private func flush() {
        guard let present else { return }
        let messages = waiting
        waiting = []
        messages.forEach(present)
    }
}
