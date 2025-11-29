import XCTest
@testable import PocketMesh
@testable import PocketMeshKit

@MainActor
final class ConfigurationProtocolTests: BaseTestCase {
    // MARK: - Radio Parameter Commands

    func testSetRadioParameters() async throws {
        // Test CMD_SET_RADIO_PARAMS (11)
        try await meshProtocol.setRadioParameters(
            frequency: 915_000_000,
            bandwidth: 125_000,
            spreadingFactor: 7,
            codingRate: 5
        )

        // Should complete without error
    }

    func testSetRadioParametersWithDifferentFrequencies() async throws {
        // Test different frequency bands
        let frequencies: [UInt32] = [
            868_000_000, // EU band
            915_000_000, // US band
            923_000_000  // Asia band
        ]

        for frequency in frequencies {
            try await meshProtocol.setRadioParameters(
                frequency: frequency,
                bandwidth: 125_000,
                spreadingFactor: 7,
                codingRate: 5
            )
        }
    }

    func testSetRadioParametersWithDifferentBandwidths() async throws {
        // Test different bandwidth values
        let bandwidths: [UInt32] = [
            125_000,
            250_000,
            500_000
        ]

        for bandwidth in bandwidths {
            try await meshProtocol.setRadioParameters(
                frequency: 915_000_000,
                bandwidth: bandwidth,
                spreadingFactor: 7,
                codingRate: 5
            )
        }
    }

    func testSetRadioTxPower() async throws {
        // Test CMD_SET_RADIO_TX_POWER (12)
        try await meshProtocol.setRadioTxPower(20)

        // Should complete without error
    }

    func testSetRadioTxPowerRange() async throws {
        // Test different TX power levels (typically 2-20 dBm)
        let powerLevels: [Int8] = [2, 10, 15, 20]

        for power in powerLevels {
            try await meshProtocol.setRadioTxPower(power)
        }
    }

    // MARK: - Time Commands

    func testSetDeviceTime() async throws {
        // Test CMD_SET_DEVICE_TIME (6)
        let now = Date()
        try await meshProtocol.setDeviceTime(now)

        // Should complete without error
    }

    func testGetDeviceTime() async throws {
        // Test CMD_GET_DEVICE_TIME (5)
        let deviceTime = try await meshProtocol.getDeviceTime()

        XCTAssertNotNil(deviceTime, "Device time should be returned")
    }

    func testSetAndGetDeviceTime() async throws {
        // Test setting and getting time in sequence
        let now = Date()
        try await meshProtocol.setDeviceTime(now)

        let deviceTime = try await meshProtocol.getDeviceTime()

        // Verify time is close to what we set (within 5 seconds tolerance)
        XCTAssertEqual(
            deviceTime.timeIntervalSince1970,
            now.timeIntervalSince1970,
            accuracy: 5.0,
            "Device time should match set time within 5 seconds"
        )
    }

    // MARK: - Battery and Storage

    func testGetBatteryAndStorage() async throws {
        // Test CMD_GET_BATT_AND_STORAGE (20)
        let status = try await meshProtocol.getBatteryAndStorage()

        XCTAssertGreaterThan(status.batteryVoltage, 0, "Battery voltage should be > 0")
        XCTAssertGreaterThanOrEqual(
            status.storageTotalKB,
            status.storageUsedKB,
            "Storage total should be >= storage used"
        )
    }

    func testBatteryAndStorageDataValidity() async throws {
        // Verify returned data is within reasonable ranges
        let status = try await meshProtocol.getBatteryAndStorage()

        // Battery voltage typically 2.0V - 4.2V for LiPo
        XCTAssertGreaterThanOrEqual(status.batteryVoltage, 2.0)
        XCTAssertLessThanOrEqual(status.batteryVoltage, 5.0)

        // Storage should be positive values
        XCTAssertGreaterThan(status.storageTotalKB, 0)
        XCTAssertGreaterThanOrEqual(status.storageUsedKB, 0)
    }

    // MARK: - Custom Variables

    func testGetCustomVariables() async throws {
        // Test CMD_GET_CUSTOM_VARS (40)
        let vars = try await meshProtocol.getCustomVariables()
        XCTAssertNotNil(vars, "Custom variables should be returned")
    }

    func testSetCustomVariable() async throws {
        // Test CMD_SET_CUSTOM_VAR (41)
        try await meshProtocol.setCustomVariable(key: "test_key", value: "test_value")

        // Should complete without error
    }

    func testSetAndGetCustomVariable() async throws {
        // Test setting and retrieving custom variable
        try await meshProtocol.setCustomVariable(key: "my_key", value: "my_value")

        let vars = try await meshProtocol.getCustomVariables()

        // TODO: Verify specific key-value pair once mock supports it
        // For now, just verify we can get variables back
        XCTAssertNotNil(vars)
    }

    func testSetMultipleCustomVariables() async throws {
        // Test setting multiple custom variables
        let variables = [
            ("key1", "value1"),
            ("key2", "value2"),
            ("key3", "value3")
        ]

        for (key, value) in variables {
            try await meshProtocol.setCustomVariable(key: key, value: value)
        }

        // All should be set successfully
    }

    // MARK: - Tuning Parameters

    func testSetTuningParams() async throws {
        // Test CMD_SET_TUNING_PARAMS (21)
        // Tuning params typically include timing and retry settings

        // TODO: Implement once MeshCoreProtocol exposes setTuningParams
        // For now, skip this test
        throw XCTSkip("Tuning parameters command not yet exposed in protocol")
    }

    // MARK: - Reboot Command

    func testRebootCommand() async throws {
        // Test CMD_REBOOT (19)
        // Note: Reboot command will disconnect the device

        // For safety, skip actual reboot in tests
        // Real hardware would disconnect and reconnect

        throw XCTSkip("Reboot command not tested to avoid disrupting mock")
    }

    // MARK: - Device Query (already tested in ProtocolComplianceTests, but verify here too)

    func testDeviceQueryReturnsConfiguration() async throws {
        // Verify device query returns configuration info
        let deviceInfo = try await meshProtocol.deviceQuery()

        XCTAssertFalse(deviceInfo.firmwareVersion.isEmpty)
        XCTAssertGreaterThan(deviceInfo.maxContacts, 0)
        XCTAssertGreaterThan(deviceInfo.maxGroupChannels, 0)
    }

    // MARK: - Error Handling

    func testSetRadioParametersWithInvalidFrequency() async throws {
        // Test with frequency outside valid range
        do {
            try await meshProtocol.setRadioParameters(
                frequency: 0, // Invalid
                bandwidth: 125_000,
                spreadingFactor: 7,
                codingRate: 5
            )
            XCTFail("Expected error for invalid frequency")
        } catch {
            // Expected - invalid frequency should cause error
        }
    }

    func testSetRadioTxPowerWithInvalidPower() async throws {
        // Test with TX power outside valid range
        do {
            try await meshProtocol.setRadioTxPower(100) // Too high
            XCTFail("Expected error for invalid TX power")
        } catch {
            // Expected - invalid power should cause error
        }
    }

    func testSetCustomVariableWithEmptyKey() async throws {
        // Test with empty key
        do {
            try await meshProtocol.setCustomVariable(key: "", value: "value")
            XCTFail("Expected error for empty key")
        } catch {
            // Expected - empty key should cause error
        }
    }
}
