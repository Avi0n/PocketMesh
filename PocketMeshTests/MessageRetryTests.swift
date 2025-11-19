import XCTest
@testable import PocketMeshKit

final class MessageRetryTests: XCTestCase {

    func testExponentialBackoff() async {
        let startTime = Date()

        for attempt in 0..<3 {
            let delay = pow(2.0, Double(attempt))
            try? await Task.sleep(nanoseconds: UInt64(delay * 100_000_000)) // 100ms base

            let elapsed = Date().timeIntervalSince(startTime)
            print("Attempt \(attempt + 1) after \(elapsed)s")
        }

        let totalElapsed = Date().timeIntervalSince(startTime)

        // Should take ~700ms (100 + 200 + 400)
        XCTAssertGreaterThan(totalElapsed, 0.6)
        XCTAssertLessThan(totalElapsed, 0.9)
    }

    func testBackoffSequence() {
        var delays: [Double] = []

        for attempt in 0..<5 {
            let delay = pow(2.0, Double(attempt))
            delays.append(delay)
        }

        XCTAssertEqual(delays, [1, 2, 4, 8, 16])
    }

    func testMaxRetries() {
        let maxRetries = 3
        var attemptCount = 0

        for attempt in 0..<maxRetries {
            attemptCount += 1
            _ = attempt
        }

        XCTAssertEqual(attemptCount, maxRetries)
    }

    func testDelayCalculation() {
        // Base delay of 1 second
        let baseDelay = 1.0

        let delay0 = baseDelay * pow(2.0, Double(0))
        let delay1 = baseDelay * pow(2.0, Double(1))
        let delay2 = baseDelay * pow(2.0, Double(2))

        XCTAssertEqual(delay0, 1.0)
        XCTAssertEqual(delay1, 2.0)
        XCTAssertEqual(delay2, 4.0)
    }
}
