import XCTest

public enum AsyncTestHelpers {
    /// Wait for a condition to be true within timeout
    public static func waitForCondition(
        timeout: TimeInterval = 5.0,
        pollingInterval: TimeInterval = 0.1,
        condition: @escaping @Sendable () async -> Bool,
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
        }

        throw XCTestError(.timeoutWhileWaiting)
    }
}
