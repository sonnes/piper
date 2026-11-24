import XCTest

/// Checks the condition every 20 ms for up to 10 seconds. A condition that
/// throws counts as false. If the condition never holds, the test fails at the
/// caller and stops.
@MainActor
func waitFor(_ message: String = "The condition did not hold in time", file: StaticString = #filePath, line: UInt = #line,
             until condition: () async throws -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(10)
    while ContinuousClock.now < deadline {
        if (try? await condition()) == true { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    XCTFail(message, file: file, line: line)
    throw XCTSkip(message)
}

extension XCTestCase {
    /// Preferences that only this test reads and writes. They go away when the test ends.
    func temporaryDefaults() -> UserDefaults {
        let suite = "PiperTests." + UUID().uuidString
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }
}
