import XCTest
import SwiftData
@testable import PocketMesh
@testable import PocketMeshKit

/// Tests TelemetryService integration with MockBLERadio against CORRECT MeshCore specification
///
/// IMPORTANT: These tests validate against the CORRECT MeshCore specification as implemented
/// in the official Python client, not the current (incorrect) PocketMesh implementation.
/// Tests will FAIL until PocketMesh is fixed to match the specification.
@MainActor
final class TelemetryServiceTests: BaseTestCase {

    var telemetryService: TelemetryService!
    var testDevice: Device!

    override func setUp() async throws {
        try await super.setUp()

        // Create test device
        testDevice = try TestDataFactory.createTestDevice()

        // Save to SwiftData context
        modelContext.insert(testDevice)
        try modelContext.save()

        // Initialize TelemetryService with mock BLE manager
        telemetryService = TelemetryService(
            bleManager: mockBLEManager,
            modelContext: modelContext
        )
    }

    override func tearDown() async throws {
        telemetryService = nil
        testDevice = nil
        try await super.tearDown()
    }

    // MARK: - Telemetry Collection Tests

    func testCollectBasicTelemetry_Success() async throws {
        // Test collecting basic telemetry data from MeshCore device

        // Given
        await telemetryService.startTelemetryCollection()

        // When
        let telemetryData = try await telemetryService.collectBasicTelemetry()

        // Then
        XCTAssertNotNil(telemetryData)
        XCTAssertNotNil(telemetryData.deviceInfo)
        XCTAssertNotNil(telemetryData.batteryLevel)
        XCTAssertNotNil(telemetryData.signalStrength)
        XCTAssertNotNil(telemetryData.uptime)

        // Validate device info matches MeshCore specification
        XCTAssertEqual(telemetryData.deviceInfo.model, "MeshCore")
        XCTAssertNotNil(telemetryData.deviceInfo.firmwareVersion)
        XCTAssertNotNil(telemetryData.deviceInfo.serialNumber)

        // Validate battery level is within expected range
        XCTAssertGreaterThanOrEqual(telemetryData.batteryLevel, 0.0)
        XCTAssertLessThanOrEqual(telemetryData.batteryLevel, 100.0)

        await telemetryService.stopTelemetryCollection()
    }

    func testCollectAdvancedTelemetry_Success() async throws {
        // Test collecting advanced telemetry data

        // Given
        await telemetryService.startTelemetryCollection()

        // When
        let telemetryData = try await telemetryService.collectAdvancedTelemetry()

        // Then
        XCTAssertNotNil(telemetryData)
        XCTAssertNotNil(telemetryData.deviceInfo)
        XCTAssertNotNil(telemetryData.batteryLevel)
        XCTAssertNotNil(telemetryData.signalStrength)
        XCTAssertNotNil(telemetryData.uptime)
        XCTAssertNotNil(telemetryData.memoryUsage)
        XCTAssertNotNil(telemetryData.temperature)
        XCTAssertNotNil(telemetryData.radioStats)

        // Validate memory usage is reasonable
        XCTAssertGreaterThan(telemetryData.memoryUsage, 0)

        // Validate temperature is within reasonable range
        XCTAssertGreaterThan(telemetryData.temperature, -20.0) // Above -20°C
        XCTAssertLessThan(telemetryData.temperature, 80.0) // Below 80°C

        // Validate radio statistics
        XCTAssertNotNil(telemetryData.radioStats.packetsSent)
        XCTAssertNotNil(telemetryData.radioStats.packetsReceived)
        XCTAssertNotNil(telemetryData.radioStats.packetsLost)
        XCTAssertNotNil(telemetryData.radioStats.connectionUptime)

        await telemetryService.stopTelemetryCollection()
    }

    func testTelemetryCollection_MeshCoreProtocolCompliance() async throws {
        // Test that telemetry collection follows MeshCore specification
        // Should use correct command codes and response handling

        // Given
        await telemetryService.startTelemetryCollection()

        // TODO: Validate that telemetry collection uses correct MeshCore commands:
        // - Should use binary request protocol (0x32) with TELEMETRY_REQUEST
        // - Should handle binary responses correctly
        // - Should respect telemetry data format specifications

        // When
        let telemetryData = try await telemetryService.collectBasicTelemetry()

        // Then
        // TODO: Validate protocol compliance in telemetry collection
        XCTAssertNotNil(telemetryData)

        await telemetryService.stopTelemetryCollection()
        XCTFail("TODO: Implement MeshCore binary protocol compliance validation for telemetry collection")
    }

    // MARK: - Telemetry Subscription Tests

    func testStartTelemetrySubscription_Success() async throws {
        // Test starting real-time telemetry subscription

        // Given
        let expectation = XCTestExpectation(description: "Telemetry update received")
        var receivedTelemetry: TelemetryService.TelemetryData?

        telemetryService.onTelemetryUpdate = { telemetry in
            receivedTelemetry = telemetry
            expectation.fulfill()
        }

        // When
        try await telemetryService.startTelemetrySubscription(interval: 1.0)

        // Then
        await fulfillment(of: [expectation], timeout: 3.0)
        XCTAssertNotNil(receivedTelemetry)

        await telemetryService.stopTelemetrySubscription()
    }

    func testStopTelemetrySubscription_Success() async throws {
        // Test stopping telemetry subscription

        // Given
        var updateCount = 0
        telemetryService.onTelemetryUpdate = { _ in
            updateCount += 1
        }

        try await telemetryService.startTelemetrySubscription(interval: 0.5)
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // When
        await telemetryService.stopTelemetrySubscription()
        let updatesAfterStop = updateCount
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Then
        XCTAssertEqual(updateCount, updatesAfterStop) // No more updates after stopping
    }

    func testTelemetrySubscription_CustomInterval() async throws {
        // Test telemetry subscription with custom interval

        // Given
        var updateCount = 0
        telemetryService.onTelemetryUpdate = { _ in
            updateCount += 1
        }

        let customInterval: TimeInterval = 0.5 // 500ms

        // When
        try await telemetryService.startTelemetrySubscription(interval: customInterval)
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        await telemetryService.stopTelemetrySubscription()

        // Then
        // Should receive approximately 4 updates in 2 seconds (allowing for timing)
        XCTAssertGreaterThanOrEqual(updateCount, 3)
        XCTAssertLessThanOrEqual(updateCount, 5)
    }

    // MARK: - Telemetry History Tests

    func testSaveTelemetryHistory() async throws {
        // Test saving telemetry data to history

        // Given
        let telemetryData = TelemetryService.TelemetryData(
            deviceInfo: TelemetryService.DeviceInfo(
                model: "MeshCore",
                firmwareVersion: "1.0.0",
                serialNumber: "MC123456789"
            ),
            batteryLevel: 85.5,
            signalStrength: -45.0,
            uptime: 3600,
            timestamp: Date()
        )

        // When
        try await telemetryService.saveTelemetryData(telemetryData)

        // Then
        let fetchDescriptor = FetchDescriptor<TelemetryService.TelemetryRecord>()
        let records = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(records.count, 1)

        let savedRecord = records.first!
        XCTAssertEqual(savedRecord.batteryLevel, telemetryData.batteryLevel)
        XCTAssertEqual(savedRecord.signalStrength, telemetryData.signalStrength)
        XCTAssertEqual(savedRecord.uptime, telemetryData.uptime)
        XCTAssertEqual(savedRecord.deviceModel, telemetryData.deviceInfo.model)
    }

    func testGetTelemetryHistory() async throws {
        // Test retrieving telemetry history

        // Given
        let telemetryData1 = TelemetryService.TelemetryData(
            deviceInfo: TelemetryService.DeviceInfo(model: "MeshCore", firmwareVersion: "1.0.0", serialNumber: "MC001"),
            batteryLevel: 90.0,
            signalStrength: -40.0,
            uptime: 1800,
            timestamp: Date(timeIntervalSinceNow: -3600) // 1 hour ago
        )

        let telemetryData2 = TelemetryService.TelemetryData(
            deviceInfo: TelemetryService.DeviceInfo(model: "MeshCore", firmwareVersion: "1.0.0", serialNumber: "MC001"),
            batteryLevel: 85.0,
            signalStrength: -45.0,
            uptime: 5400,
            timestamp: Date() // Now
        )

        try await telemetryService.saveTelemetryData(telemetryData1)
        try await telemetryService.saveTelemetryData(telemetryData2)

        // When
        let history = try await telemetryService.getTelemetryHistory(
            from: Date(timeIntervalSinceNow: -7200), // 2 hours ago
            to: Date()
        )

        // Then
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].batteryLevel, 90.0) // Earlier record
        XCTAssertEqual(history[1].batteryLevel, 85.0) // Later record
    }

    func testTelemetryHistory_Filtering() async throws {
        // Test telemetry history filtering by time range

        // Given
        let oldTelemetry = TelemetryService.TelemetryData(
            deviceInfo: TelemetryService.DeviceInfo(model: "MeshCore", firmwareVersion: "1.0.0", serialNumber: "MC001"),
            batteryLevel: 95.0,
            signalStrength: -35.0,
            uptime: 900,
            timestamp: Date(timeIntervalSinceNow: -86400) // 24 hours ago
        )

        let recentTelemetry = TelemetryService.TelemetryData(
            deviceInfo: TelemetryService.DeviceInfo(model: "MeshCore", firmwareVersion: "1.0.0", serialNumber: "MC001"),
            batteryLevel: 80.0,
            signalStrength: -50.0,
            uptime: 7200,
            timestamp: Date() // Now
        )

        try await telemetryService.saveTelemetryData(oldTelemetry)
        try await telemetryService.saveTelemetryData(recentTelemetry)

        // When - Get only recent history (last 12 hours)
        let recentHistory = try await telemetryService.getTelemetryHistory(
            from: Date(timeIntervalSinceNow: -43200), // 12 hours ago
            to: Date()
        )

        // Then
        XCTAssertEqual(recentHistory.count, 1)
        XCTAssertEqual(recentHistory[0].batteryLevel, 80.0) // Only recent record
    }

    // MARK: - Telemetry Analytics Tests

    func testCalculateTelemetryStatistics() async throws {
        // Test calculating telemetry statistics from history

        // Given
        let telemetryRecords = [
            TelemetryService.TelemetryData(
                deviceInfo: TelemetryService.DeviceInfo(model: "MeshCore", firmwareVersion: "1.0.0", serialNumber: "MC001"),
                batteryLevel: 100.0,
                signalStrength: -30.0,
                uptime: 0,
                timestamp: Date()
            ),
            TelemetryService.TelemetryData(
                deviceInfo: TelemetryService.DeviceInfo(model: "MeshCore", firmwareVersion: "1.0.0", serialNumber: "MC001"),
                batteryLevel: 75.0,
                signalStrength: -45.0,
                uptime: 1800,
                timestamp: Date()
            ),
            TelemetryService.TelemetryData(
                deviceInfo: TelemetryService.DeviceInfo(model: "MeshCore", firmwareVersion: "1.0.0", serialNumber: "MC001"),
                batteryLevel: 50.0,
                signalStrength: -60.0,
                uptime: 3600,
                timestamp: Date()
            )
        ]

        for record in telemetryRecords {
            try await telemetryService.saveTelemetryData(record)
        }

        // When
        let statistics = try await telemetryService.calculateStatistics(
            from: Date(timeIntervalSinceNow: -3600),
            to: Date()
        )

        // Then
        XCTAssertNotNil(statistics)

        // Validate battery statistics
        XCTAssertEqual(statistics.batteryStats.average, 75.0) // (100+75+50)/3
        XCTAssertEqual(statistics.batteryStats.minimum, 50.0)
        XCTAssertEqual(statistics.batteryStats.maximum, 100.0)

        // Validate signal statistics
        XCTAssertEqual(statistics.signalStats.average, -45.0) // (-30-45-60)/3
        XCTAssertEqual(statistics.signalStats.minimum, -60.0)
        XCTAssertEqual(statistics.signalStats.maximum, -30.0)

        // Validate uptime statistics
        XCTAssertEqual(statistics.uptimeStats.minimum, 0)
        XCTAssertEqual(statistics.uptimeStats.maximum, 3600)
    }

    func testTelemetryTrendAnalysis() async throws {
        // Test telemetry trend analysis

        // Given
        let baselineTelemetry = TelemetryService.TelemetryData(
            deviceInfo: TelemetryService.DeviceInfo(model: "MeshCore", firmwareVersion: "1.0.0", serialNumber: "MC001"),
            batteryLevel: 100.0,
            signalStrength: -40.0,
            uptime: 0,
            timestamp: Date(timeIntervalSinceNow: -3600) // 1 hour ago
        )

        let currentTelemetry = TelemetryService.TelemetryData(
            deviceInfo: TelemetryService.DeviceInfo(model: "MeshCore", firmwareVersion: "1.0.0", serialNumber: "MC001"),
            batteryLevel: 90.0,
            signalStrength: -45.0,
            uptime: 3600,
            timestamp: Date() // Now
        )

        try await telemetryService.saveTelemetryData(baselineTelemetry)
        try await telemetryService.saveTelemetryData(currentTelemetry)

        // When
        let trends = try await telemetryService.analyzeTrends(
            from: Date(timeIntervalSinceNow: -7200), // 2 hours ago
            to: Date()
        )

        // Then
        XCTAssertNotNil(trends)

        // Validate battery trend (should be declining)
        XCTAssertEqual(trends.batteryTrend.direction, .declining)
        XCTAssertEqual(trends.batteryTrend.changeRate, -10.0) // -10% over 1 hour

        // Validate signal trend (should be declining)
        XCTAssertEqual(trends.signalTrend.direction, .declining)
        XCTAssertEqual(trends.signalTrend.changeRate, -5.0) // -5dBm over 1 hour
    }

    // MARK: - Telemetry Alerts Tests

    func testLowBatteryAlert() async throws {
        // Test low battery alert generation

        // Given
        let lowBatteryTelemetry = TelemetryService.TelemetryData(
            deviceInfo: TelemetryService.DeviceInfo(model: "MeshCore", firmwareVersion: "1.0.0", serialNumber: "MC001"),
            batteryLevel: 15.0, // Below threshold
            signalStrength: -45.0,
            uptime: 7200,
            timestamp: Date()
        )

        var receivedAlert: TelemetryService.TelemetryAlert?
        telemetryService.onAlert = { alert in
            receivedAlert = alert
        }

        await telemetryService.startTelemetryCollection()

        // When
        try await telemetryService.processTelemetryData(lowBatteryTelemetry)

        // Then
        XCTAssertNotNil(receivedAlert)
        XCTAssertEqual(receivedAlert?.type, .lowBattery)
        XCTAssertEqual(receivedAlert?.severity, .warning)
        XCTAssertNotNil(receivedAlert?.message)

        await telemetryService.stopTelemetryCollection()
    }

    func testSignalStrengthAlert() async throws {
        // Test weak signal alert generation

        // Given
        let weakSignalTelemetry = TelemetryService.TelemetryData(
            deviceInfo: TelemetryService.DeviceInfo(model: "MeshCore", firmwareVersion: "1.0.0", serialNumber: "MC001"),
            batteryLevel: 80.0,
            signalStrength: -85.0, // Weak signal
            uptime: 7200,
            timestamp: Date()
        )

        var receivedAlert: TelemetryService.TelemetryAlert?
        telemetryService.onAlert = { alert in
            receivedAlert = alert
        }

        await telemetryService.startTelemetryCollection()

        // When
        try await telemetryService.processTelemetryData(weakSignalTelemetry)

        // Then
        XCTAssertNotNil(receivedAlert)
        XCTAssertEqual(receivedAlert?.type, .weakSignal)
        XCTAssertEqual(receivedAlert?.severity, .warning)

        await telemetryService.stopTelemetryCollection()
    }

    func testTemperatureAlert() async throws {
        // Test high temperature alert generation

        // Given
        let highTempTelemetry = TelemetryService.TelemetryData(
            deviceInfo: TelemetryService.DeviceInfo(model: "MeshCore", firmwareVersion: "1.0.0", serialNumber: "MC001"),
            batteryLevel: 80.0,
            signalStrength: -45.0,
            uptime: 7200,
            temperature: 75.0, // High temperature
            timestamp: Date()
        )

        var receivedAlert: TelemetryService.TelemetryAlert?
        telemetryService.onAlert = { alert in
            receivedAlert = alert
        }

        await telemetryService.startTelemetryCollection()

        // When
        try await telemetryService.processTelemetryData(highTempTelemetry)

        // Then
        XCTAssertNotNil(receivedAlert)
        XCTAssertEqual(receivedAlert?.type, .highTemperature)
        XCTAssertEqual(receivedAlert?.severity, .warning)

        await telemetryService.stopTelemetryCollection()
    }

    // MARK: - Error Handling Tests

    func testTelemetryCollection_DeviceDisconnected() async throws {
        // Test telemetry collection error handling when device is disconnected

        // Given
        await telemetryService.startTelemetryCollection()

        // Simulate device disconnection
        // TODO: Configure MockBLEManager to simulate disconnection

        // When
        do {
            let _ = try await telemetryService.collectBasicTelemetry()
            XCTFail("Telemetry collection should fail when device is disconnected")
        } catch {
            // Expected - should throw device disconnected error
            XCTAssertTrue(error.localizedDescription.contains("device") || error.localizedDescription.contains("connected"))
        }

        await telemetryService.stopTelemetryCollection()
        XCTFail("TODO: Implement device disconnection simulation for telemetry collection")
    }

    func testTelemetrySubscription_ErrorRecovery() async throws {
        // Test telemetry subscription error recovery

        // Given
        var updateCount = 0
        telemetryService.onTelemetryUpdate = { _ in
            updateCount += 1
        }

        try await telemetryService.startTelemetrySubscription(interval: 0.5)

        // Simulate temporary error during subscription
        // TODO: Configure MockBLEManager to simulate intermittent errors

        // When
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        // Then
        // TODO: Validate that subscription recovers from temporary errors
        XCTAssertGreaterThan(updateCount, 0) // Should have some successful updates

        await telemetryService.stopTelemetrySubscription()
        XCTFail("TODO: Implement error simulation and recovery validation for telemetry subscription")
    }

    // MARK: - Performance Tests

    func testTelemetryCollectionPerformance() async throws {
        // Test telemetry collection performance

        // Given
        await telemetryService.startTelemetryCollection()

        let iterationCount = 50
        let startTime = Date()

        // When
        for _ in 0..<iterationCount {
            let _ = try await telemetryService.collectBasicTelemetry()
        }

        let duration = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertLessThan(duration, 10.0) // Should complete within 10 seconds
        XCTAssertLessThan(duration / Double(iterationCount), 0.2) // Average < 200ms per collection

        await telemetryService.stopTelemetryCollection()
    }

    func testTelemetryHistoryPerformance_LargeDataset() async throws {
        // Test telemetry history performance with large datasets

        // Given
        let recordCount = 1000
        let startTime = Date()

        // Create large telemetry dataset
        for i in 0..<recordCount {
            let telemetryData = TelemetryService.TelemetryData(
                deviceInfo: TelemetryService.DeviceInfo(
                    model: "MeshCore",
                    firmwareVersion: "1.0.0",
                    serialNumber: "MC001"
                ),
                batteryLevel: Double(100 - (i % 100)),
                signalStrength: -30.0 - Double(i % 50),
                uptime: Double(i * 60), // 1 minute per record
                timestamp: Date(timeIntervalSinceNow: -Double(recordCount - i) * 60)
            )

            try await telemetryService.saveTelemetryData(telemetryData)
        }

        let creationDuration = Date().timeIntervalSince(startTime)
        let queryStartTime = Date()

        // When
        let history = try await telemetryService.getTelemetryHistory(
            from: Date(timeIntervalSinceNow: -Double(recordCount) * 60),
            to: Date()
        )

        let queryDuration = Date().timeIntervalSince(queryStartTime)

        // Then
        XCTAssertEqual(history.count, recordCount)
        XCTAssertLessThan(creationDuration, 30.0) // Should create 1000 records quickly
        XCTAssertLessThan(queryDuration, 5.0) // Should query quickly
    }

    // MARK: - Binary Protocol Tests

    func testTelemetryBinaryProtocolSupport() async throws {
        // Test that telemetry service supports binary protocol requests
        // MeshCore specification requires binary protocol for telemetry requests

        // Given
        await telemetryService.startTelemetryCollection()

        // TODO: Validate that telemetry service uses binary protocol:
        // 1. Sends TELEMETRY_REQUEST (0x02) via binary command (0x32)
        // 2. Handles binary response packets correctly
        // 3. Implements proper request/response correlation

        // When
        let telemetryData = try await telemetryService.collectAdvancedTelemetry()

        // Then
        XCTAssertNotNil(telemetryData)

        await telemetryService.stopTelemetryCollection()
        XCTFail("TODO: Implement binary protocol support validation for telemetry service")
    }
}