import Foundation
import Observation

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

    /// Shows a message. The app sets it to the toast.
    @ObservationIgnored var present: (Message) -> Void = { _ in }

    func show(_ text: String, undo: (() -> Void)? = nil) {
        show(text, action: undo.map { Message.Action(title: "Undo", perform: $0) })
    }

    func show(_ text: String, action: Message.Action?) {
        post(Message(text: text, action: action, isError: false))
    }

    func report(_ error: Error) {
        post(Message(text: error.localizedDescription, action: nil, isError: true))
    }

    private func post(_ message: Message) {
        last = message
        present(message)
    }
}
