import XCTest
import Captures

final class InboxStreamTests: XCTestCase {

    private let now = ISO8601DateFormatter().date(from: "2026-10-14T12:00:00Z")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func note(_ text: String, hoursAgo: Double, section: String = "Inbox", reading: Reading? = nil, parent: UUID? = nil) -> Note {
        Note(text: text, section: section, createdAt: now.addingTimeInterval(-hoursAgo * 3_600), parent: parent, reading: reading)
    }

    private var notes: [Note] {
        let started = note("https://a.dev/started", hoursAgo: 1, reading: Reading(title: "Started", openedAt: now))
        return [
            started,
            note("https://a.dev/new", hoursAgo: 2),
            note("A note from today", hoursAgo: 3, section: "Research"),
            note("A note from yesterday", hoursAgo: 20),
            note("A note from this week", hoursAgo: 24 * 4),
            note("An old note", hoursAgo: 24 * 30, section: "Research"),
            note("https://a.dev/done", hoursAgo: 5, reading: Reading(finishedAt: now)),
            note("A quote", hoursAgo: 1, parent: started.id)
        ]
    }

    func testAllStartsWithContinueReadingThenDays() {
        let stream = InboxStream(notes: notes, section: nil, filter: .all, now: now, calendar: calendar)
        XCTAssertEqual(stream.groups.map(\.title), ["Continue Reading", "Today", "Yesterday", "This Week", "Earlier"])
        XCTAssertEqual(stream.groups[0].notes.map(\.text), ["https://a.dev/started"])
        XCTAssertEqual(stream.groups[1].notes.map(\.text), ["https://a.dev/new", "A note from today", "https://a.dev/done"])
        XCTAssertFalse(stream.notes.contains { $0.parent != nil })
        // Reading counts Continue, Up Next, and Finished This Week, as its list shows them.
        XCTAssertEqual(stream.counts, [.all: 7, .notes: 4, .reading: 3])
        let reading = InboxStream(notes: notes, section: nil, filter: .reading, now: now, calendar: calendar)
        XCTAssertEqual(stream.counts[.reading], reading.notes.count)
    }

    func testNotesLeaveOutLinks() {
        let stream = InboxStream(notes: notes, section: nil, filter: .notes, now: now, calendar: calendar)
        XCTAssertEqual(stream.notes.map(\.text), ["A note from today", "A note from yesterday", "A note from this week", "An old note"])
    }

    func testReadingGroupsLinks() {
        let stream = InboxStream(notes: notes, section: nil, filter: .reading, now: now, calendar: calendar)
        XCTAssertEqual(stream.groups.map(\.title), ["Continue", "Up Next", "Finished This Week"])
        XCTAssertEqual(stream.groups.map(\.kind), [.started, .upNext, .finished])
    }

    func testASectionAndAQueryNarrowTheStream() {
        let section = InboxStream(notes: notes, section: "Research", filter: .all, now: now, calendar: calendar)
        XCTAssertEqual(section.notes.map(\.text), ["A note from today", "An old note"])
        let search = InboxStream(notes: notes, section: nil, filter: .all, query: "quote", now: now, calendar: calendar)
        XCTAssertEqual(search.groups.map(\.title), ["Today"])
        XCTAssertEqual(search.notes.map(\.text), ["https://a.dev/started"])
    }

    func testArchivedGroupsByMonthOfCompletion() {
        let october = now
        let september = now.addingTimeInterval(-30 * 86_400)
        let notes = [
            Note(text: "Done in October", section: "Inbox", isDone: true, modifiedAt: october),
            Note(text: "Done in September", section: "Work", isDone: true, modifiedAt: september),
            Note(text: "Also October", section: "Inbox", isDone: true, modifiedAt: october.addingTimeInterval(-3_600)),
            Note(text: "Open", section: "Inbox")
        ]
        let groups = InboxStream.archive(notes: notes, calendar: calendar)
        XCTAssertEqual(groups.map(\.notes.count), [2, 1])
        XCTAssertEqual(groups.map(\.kind), [.month, .month])
        XCTAssertEqual(groups[0].notes.map(\.text), ["Done in October", "Also October"])
        XCTAssertTrue(groups[0].title.contains("2026"))
        XCTAssertEqual(InboxStream.archive(notes: notes, query: "september", calendar: calendar).flatMap(\.notes).map(\.text), ["Done in September"])
    }
}
