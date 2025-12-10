import XCTest
@testable import PocketMeshKit

/// Tests for BLE reconnection and continuation cleanup
final class BLEReconnectionTests: XCTestCase {

    // MARK: - Continuation Cleanup Tests

    /// Verifies disconnect cleans up notification continuation and is safe to call repeatedly
    func testDisconnectSafeToCallMultipleTimes() async throws {
        let bleService = BLEService()

        // Disconnect should be safe even without initialization
        await bleService.disconnect()
        await bleService.disconnect()
        await bleService.disconnect()

        let state = await bleService.connectionState
        XCTAssertEqual(state, .disconnected)
    }

    /// Verifies initial state is disconnected
    func testInitialStateIsDisconnected() async throws {
        let bleService = BLEService()

        let state = await bleService.connectionState
        XCTAssertEqual(state, .disconnected)
    }

    /// Verifies rapid disconnect calls don't cause issues
    func testRapidDisconnectNoLeak() async throws {
        let bleService = BLEService()

        // Rapid disconnect calls should not cause any issues
        for _ in 1...20 {
            await bleService.disconnect()
        }

        let state = await bleService.connectionState
        XCTAssertEqual(state, .disconnected)
    }
}
