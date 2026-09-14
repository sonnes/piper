import Foundation
import Observation

/// The text of one note while an editor holds it open.
@MainActor @Observable
public final class CaptureEditSession: Identifiable {

    // MARK: - Properties

    public let id = UUID()
    public var note: Note
    public var text: String
    public var hasChanges: Bool { text != note.text }

    // MARK: - Initialization

    public init(note: Note) {
        self.note = note
        text = note.text
    }
}
