import CSQLite
import CapturesDatabase
import XCTest

final class DatabaseTests: XCTestCase {

    // MARK: - Properties

    private var url: URL!

    // MARK: - Setup

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("database-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: url) }

    // MARK: - Tests

    func testEveryTableWorksWithoutALoad() throws {
        let database = try Database(url: url)
        let record = ClipboardRecord(id: UUID(), text: "copied", copiedAt: Date(timeIntervalSince1970: 1), source: nil)
        try database.saveClipboard([record], removing: [])
        XCTAssertEqual(try database.loadClipboard(), [record])
        try database.savePage(url: "https://example.com", text: "page")
        XCTAssertEqual(try database.loadPage(url: "https://example.com"), "page")
        XCTAssertEqual(try database.loadSessions(), [])
    }

    func testAnErrorNamesItsTable() throws {
        let database = try Database(url: url)
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle, "DROP TABLE sessions; DROP TABLE clipboard", nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)

        XCTAssertThrowsError(try database.loadSessions()) { error in
            XCTAssertTrue(error.localizedDescription.hasPrefix("Cannot save or read sessions:"), error.localizedDescription)
        }
        XCTAssertThrowsError(try database.loadClipboard()) { error in
            XCTAssertTrue(error.localizedDescription.hasPrefix("Cannot save or read clipboard:"), error.localizedDescription)
        }
    }

    func testSessionsSaveLoadDeleteAndTrim() throws {
        let database = try Database(url: url)
        let ids = (0..<3).map { _ in UUID() }
        for (index, id) in ids.enumerated() {
            try database.saveSession(id: id, folder: "/w", updatedAt: Date(timeIntervalSince1970: Double(index)), data: Data([UInt8(index)]))
        }
        try database.saveSession(id: ids[0], folder: "/w", updatedAt: Date(timeIntervalSince1970: 10), data: Data([9]))
        XCTAssertEqual(try database.loadSessions(), [Data([9]), Data([2]), Data([1])])

        try database.deleteSession(id: ids[2])
        XCTAssertEqual(try database.loadSessions(), [Data([9]), Data([1])])

        try database.keepNewestSessions(1)
        XCTAssertEqual(try Database(url: url).loadSessions(), [Data([9])])
    }
}
