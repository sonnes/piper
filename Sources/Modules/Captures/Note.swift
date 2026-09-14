import Foundation

/// One captured piece of text and the places it came from.
public struct Note: Identifiable, Equatable, Codable {

    // MARK: - Properties

    public var id = UUID()
    public var text: String
    public var section: String
    public var sources: [String] = []
    public var sourceURLs: [String] = []
    public var isDone = false
    public var createdAt = Date()
    public var modifiedAt = Date()

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        text: String,
        section: String,
        sources: [String] = [],
        sourceURLs: [String] = [],
        isDone: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.section = section
        self.sources = sources
        self.sourceURLs = sourceURLs
        self.isDone = isDone
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

/// Everything that the capture database holds.
public struct SavedState: Codable, Equatable {

    // MARK: - Properties

    public var notes: [Note] = []
    public var sections = ["Inbox"]
    public var activeSection = "Inbox"

    // MARK: - Initialization

    public init(notes: [Note] = [], sections: [String] = ["Inbox"], activeSection: String = "Inbox") {
        self.notes = notes
        self.sections = sections
        self.activeSection = activeSection
    }
}
