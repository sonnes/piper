import XCTest
@testable import Vault

final class VaultWatcherTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("VaultWatcherTests-" + UUID().uuidString, isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    // MARK: Helpers

    /// Waits `seconds` on the main run loop.
    ///
    /// A new stream reports the creation of the root folder itself. The tests
    /// wait out that first report, so that a later expectation cannot pass on it.
    private func settle(_ seconds: TimeInterval) {
        let done = expectation(description: "The stream reports the events of the setup.")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 10)
    }

    // MARK: Tests

    func testWatcherCallsTheHandlerOnTheMainQueueAfterAWrite() throws {
        var pending: XCTestExpectation?
        var onMainQueue = false
        let watcher = VaultWatcher(root: root) {
            onMainQueue = Thread.isMainThread
            pending?.fulfill()
            pending = nil
        }
        watcher.start()
        defer { watcher.stop() }
        settle(1.5)

        let changed = expectation(description: "The watcher reports the new file.")
        pending = changed
        onMainQueue = false
        try Data("new\n".utf8).write(to: root.appendingPathComponent("one.md"))
        wait(for: [changed], timeout: 20)
        XCTAssertTrue(onMainQueue)
    }

    func testStopEndsTheHandlerCalls() throws {
        var pending: XCTestExpectation?
        let watcher = VaultWatcher(root: root) { pending?.fulfill() }
        watcher.start()
        settle(1.5)

        watcher.stop()
        let quiet = expectation(description: "The watcher stays quiet after stop().")
        quiet.isInverted = true
        pending = quiet
        try Data("new\n".utf8).write(to: root.appendingPathComponent("two.md"))
        wait(for: [quiet], timeout: 3)
    }

    func testDeinitWithARunningStreamIsSafe() throws {
        autoreleasepool {
            let watcher = VaultWatcher(root: root) {}
            watcher.start()
            watcher.start()
        }
        try Data("new\n".utf8).write(to: root.appendingPathComponent("three.md"))
        settle(2)
    }
}
