import Foundation

/// One visit to one page.
public struct Visit: Equatable, Sendable {
    public let url: String
    public let title: String?
    public let date: Date

    public init(url: String, title: String?, date: Date) {
        self.url = url
        self.title = title
        self.date = date
    }
}

/// Reads visits from the history database of a browser.
public enum HistoryReader {

    public static func read(_ source: HistorySource, since: Date) throws -> [Visit] {
        guard let database = source.database else { return [] }
        return try DatabaseCopy.rows(of: database, sql: sql(for: source.format), since: since).compactMap { row in
            guard let url = row[0], let seconds = row[2].flatMap(Double.init) else { return nil }
            return Visit(url: url, title: row[1], date: Date(timeIntervalSince1970: seconds))
        }
    }

    /// Each format counts time from a different start. Each query gives seconds from 1970.
    private static func sql(for format: HistorySourceFormat) -> String {
        switch format {
        case .chromium:
            return """
            SELECT u.url, u.title, v.visit_time / 1000000 - 11644473600 AS seen
            FROM visits v JOIN urls u ON v.url = u.id WHERE seen >= :since
            """
        case .firefox:
            return """
            SELECT p.url, p.title, v.visit_date / 1000000 AS seen
            FROM moz_historyvisits v JOIN moz_places p ON v.place = p.id WHERE seen >= :since
            """
        case .safari:
            return """
            SELECT i.url, v.title, v.visit_time + 978307200 AS seen
            FROM history_visits v JOIN history_items i ON v.history_item = i.id WHERE seen >= :since
            """
        }
    }
}
