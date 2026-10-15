import Foundation

/// The link captures that Reading shows, in three groups.
public struct ReadingList: Equatable {

    // MARK: - Properties

    public static let highlightTag = "highlight"
    public static let questionTag = "question"
    public static let summaryTag = "summary"
    /// How long a finished article stays in Finished before it goes to Archived.
    public static let finishedDays = 7

    /// The articles that the reader started, the newest activity first.
    public let inProgress: [Note]
    /// The articles that the reader did not open, the newest first.
    public let upNext: [Note]
    /// The articles that the reader finished in the last week, the newest first.
    public let finished: [Note]

    /// The number of articles in the three groups.
    public var count: Int { inProgress.count + upNext.count + finished.count }

    // MARK: - Initialization

    public init(notes: [Note], now: Date = Date()) {
        let children = Dictionary(grouping: notes.filter { $0.parent != nil }, by: { $0.parent! })
        let articles = notes.filter { !$0.isDone && $0.isArticle }
        let since = now.addingTimeInterval(-Double(Self.finishedDays) * 86_400)
        var inProgress: [(Note, Date)] = []
        var upNext: [Note] = []
        var finished: [Note] = []
        for article in articles {
            let marks = children[article.id] ?? []
            if let done = article.reading?.finishedAt {
                if done >= since { finished.append(article) }
            } else if article.reading?.openedAt != nil || !marks.isEmpty {
                let activity = ([article.createdAt, article.reading?.openedAt] + marks.map(\.modifiedAt)).compactMap { $0 }.max()!
                inProgress.append((article, activity))
            } else {
                upNext.append(article)
            }
        }
        self.inProgress = inProgress.sorted { $0.1 > $1.1 }.map(\.0)
        self.upNext = upNext.sorted { $0.createdAt > $1.createdAt }
        self.finished = finished.sorted { ($0.reading?.finishedAt ?? .distantPast) > ($1.reading?.finishedAt ?? .distantPast) }
    }

    // MARK: - Child Notes

    /// The highlights of an article, oldest first.
    public static func highlights(in children: [Note]) -> [Note] {
        children.filter { $0.tags.contains(highlightTag) }
    }

    /// The highlights with a note of the reader.
    public static func comments(in children: [Note]) -> [Note] {
        highlights(in: children).filter { !HighlightText.comment(of: $0.text, quote: $0.anchor?.quote).isEmpty }
    }

    public static func questions(in children: [Note]) -> [Note] {
        children.filter { $0.tags.contains(questionTag) }
    }

    public static func summary(in children: [Note]) -> Note? {
        children.first { $0.tags.contains(summaryTag) }
    }

    /// "2 highlights · 1 note · 1 question", without the parts that are zero.
    public static func counts(of children: [Note]) -> String {
        let parts: [(Int, String)] = [
            (highlights(in: children).count, "highlight"),
            (comments(in: children).count, "note"),
            (questions(in: children).count, "question")
        ]
        return parts.filter { $0.0 > 0 }
            .map { count, name in "\(count) \(name)" + (count == 1 ? "" : "s") }
            .joined(separator: " · ")
    }
}

/// The Markdown file that Save as File writes for an article.
public enum ArticleMarkdown {

    /// The parts of the article notes that go into the file.
    public struct Parts: Equatable {
        public var highlights: Bool
        public var summary: Bool
        public var answers: Bool

        public init(highlights: Bool = true, summary: Bool = true, answers: Bool = false) {
            self.highlights = highlights
            self.summary = summary
            self.answers = answers
        }
    }

    /// The whole file: front matter with the source, the title, the summary,
    /// the highlights with the notes of the reader, and the Claude answers.
    public static func file(title: String, url: URL, children: [Note], parts: Parts, date: Date) -> String {
        let line = title.split(whereSeparator: \.isNewline).joined(separator: " ")
        let quoted = line.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let heading = line.replacingOccurrences(of: "\\", with: "\\\\")
        var text = "---\nsource: \(url.absoluteString)\ntitle: \"\(quoted)\"\nread: \(day(date))\n---\n\n# \(heading)\n"
        if parts.summary, let summary = ReadingList.summary(in: children)?.text.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            text += "\n" + summary + "\n"
        }
        let highlights = ReadingList.highlights(in: children)
        if parts.highlights, !highlights.isEmpty {
            text += "\n## Highlights\n" + highlights.map(block).joined()
        }
        let questions = ReadingList.questions(in: children).filter { NoteThread($0.text).turns.contains { !$0.answer.isEmpty } }
        if parts.answers, !questions.isEmpty {
            text += "\n## Questions\n"
            for question in questions {
                let thread = NoteThread(question.text)
                text += "\n### \(thread.title)\n"
                for turn in thread.turns {
                    if let asked = turn.question { text += "\n**\(asked)**\n" }
                    if !turn.answer.isEmpty { text += "\n" + turn.answer + "\n" }
                }
            }
        }
        return text
    }

    /// The text that Update File adds to the end of a saved file: the
    /// highlights that are new or changed after the save.
    public static func update(children: [Note], after saved: Date, date: Date) -> String? {
        let fresh = ReadingList.highlights(in: children).filter { $0.modifiedAt > saved }
        guard !fresh.isEmpty else { return nil }
        return "\n## Added \(day(date))\n" + fresh.map(block).joined()
    }

    /// A file name from the title, such as `how-the-log-works.md`.
    public static func fileName(for title: String) -> String {
        let words = title.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        let slug = String(words).split(separator: " ").prefix(8).joined(separator: "-")
        return (slug.isEmpty ? "article" : slug) + ".md"
    }

    private static func block(_ highlight: Note) -> String {
        let quote = highlight.anchor?.quote ?? (highlight.text.components(separatedBy: "\n\n").first ?? highlight.text)
        let comment = HighlightText.comment(of: highlight.text, quote: highlight.anchor?.quote)
        var text = "\n" + quote.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n") + "\n"
        if !comment.isEmpty { text += "\n" + comment + "\n" }
        return text
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
