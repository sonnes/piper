import Foundation
import PiperCore
import XCTest

final class SiteTests: XCTestCase {
    func testKeyIsTheLowercaseHostWithoutWWW() {
        XCTAssertEqual(Site(URL(string: "https://WWW.Example.com/a")!)?.key, "example.com")
        XCTAssertEqual(Site(host: "WWW.Example.com").key, "example.com")
        XCTAssertEqual(Site(host: "blog.example.com").key, "blog.example.com")
        XCTAssertEqual(Site(host: "wwwexample.com").key, "wwwexample.com")
        XCTAssertNil(Site(URL(string: "file:///tmp/file")!))
    }

    func testOnlyHTTPLinksWithAHostAreWeb() {
        for value in ["https:path", "http:///", "file:///tmp/file", "javascript:alert(1)", "ftp://example.com"] {
            XCTAssertFalse(URL(string: value)!.isWeb, value)
        }
        XCTAssertTrue(URL(string: "HTTPS://example.com")!.isWeb)
    }
}
