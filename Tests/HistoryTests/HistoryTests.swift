import CSQLite
import XCTest
@testable import History

final class HistoryTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Catalog

    func testCatalogFindsEachChromiumProfileWithItsName() throws {
        let arc = folder.appendingPathComponent("Application Support/Arc/User Data")
        try makeDatabase(at: arc.appendingPathComponent("Default/History"), "CREATE TABLE t (a)")
        try makeDatabase(at: arc.appendingPathComponent("Profile 2/History"), "CREATE TABLE t (a)")
        try FileManager.default.createDirectory(at: arc.appendingPathComponent("Guest Profile"), withIntermediateDirectories: true)
        try Data(#"{"profile":{"info_cache":{"Profile 2":{"name":"Work"}}}}"#.utf8).write(to: arc.appendingPathComponent("Local State"))

        let sources = BrowserCatalog.sources(library: folder)

        XCTAssertEqual(sources.map(\.profile), ["Default", "Work"])
        XCTAssertEqual(Set(sources.map(\.name)), ["Arc"])
        XCTAssertFalse(sources.contains(where: \.needsAccess))
    }

    func testCatalogFindsFirefoxAndSafari() throws {
        try makeDatabase(at: folder.appendingPathComponent("Application Support/zen/Profiles/abc.Default/places.sqlite"), "CREATE TABLE t (a)")
        try makeDatabase(at: folder.appendingPathComponent("Safari/History.db"), "CREATE TABLE t (a)")

        let sources = BrowserCatalog.sources(library: folder)

        XCTAssertEqual(sources.map(\.name), ["Zen", "Safari"])
        XCTAssertEqual(sources.map(\.profile), ["Default", nil])
    }

    func testCatalogIsEmptyWithNoBrowser() {
        XCTAssertTrue(BrowserCatalog.sources(library: folder).isEmpty)
    }

    // MARK: - History

    func testEachFormatGivesTheSameDate() throws {
        let now = 1_790_000_000.0
        let chromium = folder.appendingPathComponent("chromium")
        try makeDatabase(at: chromium, """
        CREATE TABLE urls (id INTEGER, url TEXT, title TEXT);
        CREATE TABLE visits (url INTEGER, visit_time INTEGER);
        INSERT INTO urls VALUES (1, 'https://a.example/', 'A');
        INSERT INTO visits VALUES (1, \(Int64((now + 11_644_473_600) * 1_000_000)));
        INSERT INTO visits VALUES (1, 1000);
        """)
        let firefox = folder.appendingPathComponent("firefox")
        try makeDatabase(at: firefox, """
        CREATE TABLE moz_places (id INTEGER, url TEXT, title TEXT);
        CREATE TABLE moz_historyvisits (place INTEGER, visit_date INTEGER);
        INSERT INTO moz_places VALUES (1, 'https://a.example/', 'A');
        INSERT INTO moz_historyvisits VALUES (1, \(Int64(now * 1_000_000)));
        """)
        let safari = folder.appendingPathComponent("safari")
        try makeDatabase(at: safari, """
        CREATE TABLE history_items (id INTEGER, url TEXT);
        CREATE TABLE history_visits (history_item INTEGER, title TEXT, visit_time REAL);
        INSERT INTO history_items VALUES (1, 'https://a.example/');
        INSERT INTO history_visits VALUES (1, 'A', \(now - 978_307_200));
        """)
        let since = Date(timeIntervalSince1970: now - 86_400)

        for (url, format) in [(chromium, HistorySourceFormat.chromium), (firefox, .firefox), (safari, .safari)] {
            let source = HistorySource(id: url.path, name: "x", profile: nil, database: url, format: format)
            let visits = try HistoryReader.read(source, since: since)
            XCTAssertEqual(visits, [Visit(url: "https://a.example/", title: "A", date: Date(timeIntervalSince1970: now))], format.rawValue)
        }
    }

    func testReadingLeavesTheOriginalFileUnchanged() throws {
        let url = folder.appendingPathComponent("history")
        try makeDatabase(at: url, """
        CREATE TABLE urls (id INTEGER, url TEXT, title TEXT);
        CREATE TABLE visits (url INTEGER, visit_time INTEGER);
        """)
        let before = try Data(contentsOf: url)
        _ = try HistoryReader.read(HistorySource(id: "x", name: "x", profile: nil, database: url, format: .chromium), since: .distantPast)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    // MARK: - Blocked sites

    func testBlockCoversSubdomainsAtADomainBoundary() {
        let list = BlockedSites.normalized(["https://www.Example.com/x", "*.bank.test", "# note", ""])
        XCTAssertEqual(list, ["example.com", "bank.test"])
        XCTAssertTrue(BlockedSites.isBlocked("a.example.com", list: list))
        XCTAssertTrue(BlockedSites.isBlocked("my.bank.test", list: list))
        XCTAssertFalse(BlockedSites.isBlocked("notexample.com", list: list))
    }

    func testPrivateHostsAreAlwaysBlocked() {
        for host in ["localhost", "127.0.0.1", "10.1.2.3", "192.168.1.1", "172.20.0.1", "169.254.1.1", "server", "nas.local", "git.internal"] {
            XCTAssertTrue(BlockedSites.isBlocked(host, list: []), host)
        }
        XCTAssertFalse(BlockedSites.isBlocked("172.32.0.1", list: []))
        XCTAssertFalse(BlockedSites.allows("file:///etc/hosts", list: []))
        XCTAssertFalse(BlockedSites.allows("javascript:alert(1)", list: []))
    }

    // MARK: - Digest

    func testDigestRanksKeepsSingleVisitsAndDropsBlockedSites() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var visits = (0..<10).map { Visit(url: "https://www.top.example/secret/\($0)", title: "T\($0)", date: now) }
        visits += (0..<2).map { _ in Visit(url: "https://low.example/", title: "L", date: now.addingTimeInterval(-86_400 * 10)) }
        visits += (0..<20).map { _ in Visit(url: "https://mybank.example/", title: "B", date: now) }
        visits.append(Visit(url: "https://once.example/", title: "O", date: now))
        visits.append(Visit(url: "http://192.168.1.1/", title: "R", date: now))

        let digest = HistoryDigest(visits: visits, blocked: ["mybank.example"], now: now)

        XCTAssertEqual(digest.sites.map(\.host), ["top.example", "once.example", "low.example"])
        XCTAssertEqual(digest.totalSites, 3)
        XCTAssertEqual(digest.sites[0].visits, 10)
        XCTAssertEqual(digest.sites[2].pages, 1)
        XCTAssertGreaterThan(digest.score(of: "once.example"), 0)
    }

    func testDigestKeepsThirtySitesAndTheFullCount() {
        let now = Date()
        let visits = (0..<40).flatMap { index in
            (0..<2).map { _ in Visit(url: "https://s\(index).example/", title: nil, date: now) }
        }
        let digest = HistoryDigest(visits: visits, blocked: [], now: now)
        XCTAssertEqual(digest.sites.count, 30)
        XCTAssertEqual(digest.totalSites, 40)
    }

    func testDigestPutsMoreVisitsAndNewerVisitsFirst() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let hour: TimeInterval = 3_600
        var visits = (0..<5).map { _ in Visit(url: "https://many.example/", title: nil, date: now.addingTimeInterval(-hour)) }
        visits += (0..<2).map { _ in Visit(url: "https://few.example/", title: nil, date: now.addingTimeInterval(-hour)) }
        visits += (0..<2).map { _ in Visit(url: "https://new.example/", title: nil, date: now) }
        visits += (0..<2).map { _ in Visit(url: "https://old.example/", title: nil, date: now.addingTimeInterval(-48 * hour)) }

        let digest = HistoryDigest(visits: visits, blocked: [], now: now)

        XCTAssertEqual(digest.sites.map(\.host), ["many.example", "new.example", "few.example", "old.example"])
    }

    // MARK: - Decay

    func testDecayPutsANewStoryAboveAnOldStoryWithMorePoints() {
        XCTAssertLessThan(Decay.score(points: 299, hours: 20), Decay.score(points: 99, hours: 2))
        XCTAssertEqual(Decay.score(points: 4, hours: -5), Decay.score(points: 4, hours: 0))
    }

    // MARK: - Helpers

    private func makeDatabase(at url: URL, _ sql: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        defer { sqlite3_close(handle) }
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK, String(cString: sqlite3_errmsg(handle)))
    }
}
