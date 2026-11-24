import XCTest

extension XCTestCase {

    /// Checks the condition every 20 ms for up to 10 seconds. If it never
    /// holds, the test fails at the caller and stops.
    @MainActor
    func wait(_ message: String = "The condition did not hold in time", file: StaticString = #filePath, line: UInt = #line,
              until condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail(message, file: file, line: line)
        throw WaitTimeout()
    }
}

/// Stops a test after `XCTFail` has recorded a wait that timed out.
private struct WaitTimeout: Error {}
