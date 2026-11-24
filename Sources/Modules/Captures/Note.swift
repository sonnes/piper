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
    /// The note this note belongs to, such as the link of a highlight.
    public var parent: UUID?
    public var tags: [String] = []
    /// The text in the parent article that this note marks.
    public var anchor: NoteAnchor?
    /// The reading state of a link capture.
    public var reading: Reading?

    /// The section that every store has. It cannot be renamed or deleted.
    public static let inbox = "Inbox"
    /// The source of a note that came from the clipboard.
    public static let clipboardSource = "Clipboard"

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        text: String,
        section: String,
        sources: [String] = [],
        sourceURLs: [String] = [],
        isDone: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        parent: UUID? = nil,
        tags: [String] = [],
        anchor: NoteAnchor? = nil,
        reading: Reading? = nil
    ) {
        self.id = id
        self.text = text
        self.section = section
        self.sources = sources
        self.sourceURLs = sourceURLs
        self.isDone = isDone
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.parent = parent
        self.tags = tags
        self.anchor = anchor
        self.reading = reading
    }

    /// Reads a note. A note saved before parents and tags existed has neither.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        section = try values.decode(String.self, forKey: .section)
        sources = try values.decode([String].self, forKey: .sources)
        sourceURLs = try values.decode([String].self, forKey: .sourceURLs)
        isDone = try values.decode(Bool.self, forKey: .isDone)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        modifiedAt = try values.decode(Date.self, forKey: .modifiedAt)
        parent = try values.decodeIfPresent(UUID.self, forKey: .parent)
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        anchor = try values.decodeIfPresent(NoteAnchor.self, forKey: .anchor)
        reading = try values.decodeIfPresent(Reading.self, forKey: .reading)
    }

    /// True for a link capture that Reading shows: a note that holds only a
    /// web link, or a note that has a reading state.
    public var isArticle: Bool {
        guard parent == nil else { return false }
        if reading != nil { return true }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("."), !trimmed.contains(where: \.isWhitespace) else { return false }
        return CaptureLinks(trimmed).standaloneURL != nil
    }

    public var isKept: Bool { has(.kept) }

    public func has(_ tag: NoteTag) -> Bool { tags.contains(tag.rawValue) }

    /// The child notes of each parent, in the order of the list.
    public static func childrenByParent(_ notes: [Note]) -> [UUID: [Note]] {
        Dictionary(grouping: notes.filter { $0.parent != nil }, by: { $0.parent! })
    }

    public var articleURL: URL? {
        CaptureLinks(text).standaloneURL ?? sourceURLs.first.flatMap(URL.init(string:))
    }

    /// The canonical link of a link capture, which names its article. Nil for any other note.
    public var articleKey: String? {
        isArticle ? articleURL.map(CaptureLinks.canonical) : nil
    }
}

/// The tags that give a note its role. A highlight also has a color tag.
public enum NoteTag: String, Sendable {
    case kept
    /// A child note that marks a quote in its article.
    case highlight
    /// A child note that asks about its article. The margin session answers it.
    case question
    /// A child note that sums up its article.
    case summary
}

/// How far the reader got in the article of a link capture.
public struct Reading: Codable, Equatable, Sendable {

    /// The title of the page, from the browser or from the Reader tab.
    public var title: String?
    /// The reading time of the whole article.
    public var minutes: Int?
    /// The first block on the screen when the reader left the article.
    public var block: Int?
    /// The part of the article above the screen, from 0 to 1.
    public var progress: Double
    public var openedAt: Date?
    public var finishedAt: Date?
    /// The absolute path of the Markdown file that Save as File wrote.
    public var savedFile: String?
    public var savedAt: Date?

    public init(title: String? = nil, minutes: Int? = nil, block: Int? = nil, progress: Double = 0,
                openedAt: Date? = nil, finishedAt: Date? = nil, savedFile: String? = nil, savedAt: Date? = nil) {
        self.title = title
        self.minutes = minutes
        self.block = block
        self.progress = progress
        self.openedAt = openedAt
        self.finishedAt = finishedAt
        self.savedFile = savedFile
        self.savedAt = savedAt
    }

    /// The minutes that the reader has left, rounded up. Nil before the Reader
    /// tab measured the article.
    public var minutesLeft: Int? {
        minutes.map { max(1, Int((Double($0) * (1 - min(max(progress, 0), 1))).rounded(.up))) }
    }
}

/// Everything that the capture database holds.
public struct SavedState: Codable, Equatable {

    public var notes: [Note] = []
    public var sections = [Note.inbox]
    public var activeSection = Note.inbox

    public init(notes: [Note] = [], sections: [String] = [Note.inbox], activeSection: String = Note.inbox) {
        self.notes = notes
        self.sections = sections
        self.activeSection = activeSection
    }
}
