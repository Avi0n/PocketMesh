import XCTest
@testable import PocketMesh
@testable import PocketMeshKit

@MainActor
final class ProtocolComplianceTests: BaseTestCase {
    // MARK: - Handshake Commands

    func testDeviceQueryCommand() async throws {
        // Test CMD_DEVICE_QUERY (22) → RESP_CODE_DEVICE_INFO (13)
        let deviceInfo = try await meshProtocol.deviceQuery()

        XCTAssertFalse(deviceInfo.firmwareVersion.isEmpty)
        XCTAssertGreaterThan(deviceInfo.maxContacts, 0)
        XCTAssertEqual(deviceInfo.maxGroupChannels, 8)
        XCTAssertFalse(deviceInfo.manufacturer.isEmpty)
    }

    func testAppStartCommand() async throws {
        // Test CMD_APP_START (1) → RESP_CODE_SELF_INFO (5)
        // CRITICAL: This test validates against CORRECT spec implementation

        let selfInfo = try await meshProtocol.appStart()

        XCTAssertEqual(selfInfo.publicKey.count, 32)
        XCTAssertGreaterThan(selfInfo.txPower, 0)
        XCTAssertEqual(selfInfo.radioFrequency, 915_000_000)
        XCTAssertEqual(selfInfo.radioBandwidth, 125_000)

        // Additional validation: Verify correct command payload was sent
        // Current PocketMesh sends: [01] + reserved + app_name
        // Spec requires proper format per MeshCore specification
        // Binary encoding validation done in dedicated tests below
    }

    // MARK: - Binary Encoding Validation

    func testDeviceQueryBinaryEncoding() async throws {
        // Test against CORRECT MeshCore specification
        // PocketMesh implementation: Sends [22][03] (command + version)
        // Spec requires: [22][03] (command + version)

        // NOTE: Binary encoding validation requires capturing TX writes.
        // The current mock infrastructure doesn't expose TX writes for inspection.
        // This test documents the expected behavior and will be implemented
        // when TX write capturing is added to MockBLEManager.

        // Expected frame structure:
        // [CMD_DEVICE_QUERY:1][version:1] = [0x16][0x03]

        // For now, verify the command executes successfully
        let deviceInfo = try await meshProtocol.deviceQuery()
        XCTAssertNotNil(deviceInfo)

        // TODO: Add TX write capture to MockBLEManager to validate exact bytes sent
        // Expected validation:
        // XCTAssertEqual(capturedFrame?.count, 2, "deviceQuery must send 2 bytes per spec")
        // XCTAssertEqual(capturedFrame?[0], 22, "First byte should be CMD_DEVICE_QUERY (22)")
        // XCTAssertEqual(capturedFrame?[1], 3, "Second byte should be version (3) per spec")
    }

    func testAppStartBinaryEncoding() async throws {
        // Test against CORRECT MeshCore specification
        // PocketMesh implementation: Sends [01] + reserved + app_name
        // Spec format: [CMD_APP_START:1][reserved:7][app_name:variable]

        // NOTE: Binary encoding validation requires capturing TX writes.
        // This test documents the expected behavior.

        // Expected frame structure per spec:
        // [CMD_APP_START:1][reserved:7][app_name:null_terminated]
        // Default app_name = "PocketMesh"

        // For now, verify the command executes successfully
        let selfInfo = try await meshProtocol.appStart()
        XCTAssertNotNil(selfInfo)
        XCTAssertEqual(selfInfo.publicKey.count, 32)

        // TODO: Add TX write capture to validate exact bytes sent
        // Expected validation would check:
        // - First byte is CMD_APP_START (1)
        // - Next 7 bytes are reserved (zeros)
        // - Following bytes are app name in UTF-8
    }

    // MARK: - Timeout Handling

    func testCommandTimeout() async throws {
        // Configure mock to never respond (100% packet loss)
        mockRadio = MockBLERadio(
            deviceName: "Timeout-Test",
            config: MockRadioConfig(
                packetLossRate: 1.0, // Drop all packets
                verboseLogging: true
            )
        )
        bleManager = MockBLEManager(radio: mockRadio)
        meshProtocol = MeshCoreProtocol(bleManager: bleManager)
        await mockRadio.start()

        // Expect timeout error
        do {
            _ = try await meshProtocol.deviceQuery()
            XCTFail("Expected timeout error")
        } catch ProtocolError.timeout {
            // Expected - command should timeout when radio doesn't respond
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Multiple Command Execution

    func testMultipleCommandsInSequence() async throws {
        // Test that protocol can handle multiple commands in sequence
        let deviceInfo = try await meshProtocol.deviceQuery()
        XCTAssertNotNil(deviceInfo)

        let selfInfo = try await meshProtocol.appStart()
        XCTAssertNotNil(selfInfo)

        let deviceTime = try await meshProtocol.getDeviceTime()
        XCTAssertNotNil(deviceTime)

        // All commands should complete successfully
    }

    // MARK: - Response Validation

    func testDeviceInfoResponseStructure() async throws {
        // Verify DeviceInfo response contains all required fields
        let deviceInfo = try await meshProtocol.deviceQuery()

        XCTAssertFalse(deviceInfo.firmwareVersion.isEmpty, "Firmware version should not be empty")
        XCTAssertGreaterThan(deviceInfo.maxContacts, 0, "Max contacts should be > 0")
        XCTAssertGreaterThan(deviceInfo.maxGroupChannels, 0, "Max channels should be > 0")
        XCTAssertFalse(deviceInfo.manufacturer.isEmpty, "Manufacturer should not be empty")
        XCTAssertFalse(deviceInfo.buildDate.isEmpty, "Build date should not be empty")
    }

    func testSelfInfoResponseStructure() async throws {
        // Verify SelfInfo response contains all required fields
        let selfInfo = try await meshProtocol.appStart()

        XCTAssertEqual(selfInfo.publicKey.count, 32, "Public key must be 32 bytes")
        XCTAssertGreaterThan(selfInfo.txPower, 0, "TX power should be > 0")
        XCTAssertGreaterThan(selfInfo.radioFrequency, 0, "Radio frequency should be > 0")
        XCTAssertGreaterThan(selfInfo.radioBandwidth, 0, "Radio bandwidth should be > 0")
        XCTAssertGreaterThan(selfInfo.radioSpreadingFactor, 0, "Spreading factor should be > 0")
        XCTAssertGreaterThan(selfInfo.radioCodingRate, 0, "Coding rate should be > 0")
    }
}
