import Foundation
import Testing
@testable import MeshCore

@Suite("Granular Configuration Tests", .serialized)
struct GranularConfigTests {

    // MARK: - Telemetry Mode Base

    @Test("setTelemetryModeBase preserves other settings")
    func setTelemetryModeBasePreservesOtherSettings() async throws {
        let (session, transport) = try await makeStartedSessionWithKnownConfig()
        await transport.clearSentData()

        // Action: set only telemetry mode base
        async let setTask: () = session.setTelemetryModeBase(0)
        try await Task.sleep(for: .milliseconds(50))

        // Simulate OK for setOtherParams
        await transport.simulateOK()
        try await Task.sleep(for: .milliseconds(50))

        // Simulate selfInfo for the refresh
        await transport.simulateReceive(makeSelfInfoResponse())
        try await setTask

        // Verify: setOtherParams command was sent
        let sentData = await transport.sentData
        #expect(sentData.count >= 1, "Expected at least one command sent")

        let setParamsCommand = sentData.first { $0.first == CommandCode.setOtherParams.rawValue }
        #expect(setParamsCommand != nil, "Expected setOtherParams command")

        if let cmd = setParamsCommand {
            // Byte 1: manualAddContacts (should be preserved as false = 0)
            #expect(cmd[1] == 0, "manualAddContacts should be preserved")

            // Byte 2: telemetry mode (env << 4) | (loc << 2) | base
            // With env=1, loc=1, base=0 (new value): (1 << 4) | (1 << 2) | 0 = 0x14
            #expect(cmd[2] == 0x14, "telemetry mode byte should have base=0, preserving loc=1, env=1")

            // Byte 3: advertisementLocationPolicy (should be preserved as 0)
            #expect(cmd[3] == 0, "advertisementLocationPolicy should be preserved")

            // Byte 4: multiAcks (should be preserved as 1)
            #expect(cmd[4] == 1, "multiAcks should be preserved")
        }
    }

    // MARK: - Telemetry Mode Location

    @Test("setTelemetryModeLocation preserves other settings")
    func setTelemetryModeLocationPreservesOtherSettings() async throws {
        let (session, transport) = try await makeStartedSessionWithKnownConfig()
        await transport.clearSentData()

        async let setTask: () = session.setTelemetryModeLocation(3)
        try await Task.sleep(for: .milliseconds(50))

        await transport.simulateOK()
        try await Task.sleep(for: .milliseconds(50))
        await transport.simulateReceive(makeSelfInfoResponse())
        try await setTask

        let sentData = await transport.sentData
        let setParamsCommand = sentData.first { $0.first == CommandCode.setOtherParams.rawValue }
        #expect(setParamsCommand != nil, "Expected setOtherParams command")

        if let cmd = setParamsCommand {
            // With env=1, loc=3 (new), base=1: (1 << 4) | (3 << 2) | 1 = 0x1D
            #expect(cmd[2] == 0x1D, "telemetry mode byte should have loc=3")
        }
    }

    // MARK: - Telemetry Mode Environment

    @Test("setTelemetryModeEnvironment preserves other settings")
    func setTelemetryModeEnvironmentPreservesOtherSettings() async throws {
        let (session, transport) = try await makeStartedSessionWithKnownConfig()
        await transport.clearSentData()

        async let setTask: () = session.setTelemetryModeEnvironment(2)
        try await Task.sleep(for: .milliseconds(50))

        await transport.simulateOK()
        try await Task.sleep(for: .milliseconds(50))
        await transport.simulateReceive(makeSelfInfoResponse())
        try await setTask

        let sentData = await transport.sentData
        let setParamsCommand = sentData.first { $0.first == CommandCode.setOtherParams.rawValue }
        #expect(setParamsCommand != nil, "Expected setOtherParams command")

        if let cmd = setParamsCommand {
            // With env=2 (new), loc=1, base=1: (2 << 4) | (1 << 2) | 1 = 0x25
            #expect(cmd[2] == 0x25, "telemetry mode byte should have env=2")
        }
    }

    // MARK: - Manual Add Contacts

    @Test("setManualAddContacts preserves other settings")
    func setManualAddContactsPreservesOtherSettings() async throws {
        let (session, transport) = try await makeStartedSessionWithKnownConfig()
        await transport.clearSentData()

        async let setTask: () = session.setManualAddContacts(true)
        try await Task.sleep(for: .milliseconds(50))

        await transport.simulateOK()
        try await Task.sleep(for: .milliseconds(50))
        await transport.simulateReceive(makeSelfInfoResponse())
        try await setTask

        let sentData = await transport.sentData
        let setParamsCommand = sentData.first { $0.first == CommandCode.setOtherParams.rawValue }
        #expect(setParamsCommand != nil, "Expected setOtherParams command")

        if let cmd = setParamsCommand {
            #expect(cmd[1] == 1, "manualAddContacts should be true (1)")
            // Telemetry should be preserved: (1 << 4) | (1 << 2) | 1 = 0x15
            #expect(cmd[2] == 0x15, "telemetry mode should be preserved")
        }
    }

    // MARK: - Multi-Acks

    @Test("setMultiAcks preserves other settings")
    func setMultiAcksPreservesOtherSettings() async throws {
        let (session, transport) = try await makeStartedSessionWithKnownConfig()
        await transport.clearSentData()

        async let setTask: () = session.setMultiAcks(5)
        try await Task.sleep(for: .milliseconds(50))

        await transport.simulateOK()
        try await Task.sleep(for: .milliseconds(50))
        await transport.simulateReceive(makeSelfInfoResponse())
        try await setTask

        let sentData = await transport.sentData
        let setParamsCommand = sentData.first { $0.first == CommandCode.setOtherParams.rawValue }
        #expect(setParamsCommand != nil, "Expected setOtherParams command")

        if let cmd = setParamsCommand {
            #expect(cmd[4] == 5, "multiAcks should be 5")
            // Other settings should be preserved
            #expect(cmd[1] == 0, "manualAddContacts should be preserved")
            #expect(cmd[2] == 0x15, "telemetry mode should be preserved")
        }
    }

    // MARK: - Advertisement Location Policy

    @Test("setAdvertisementLocationPolicy preserves other settings")
    func setAdvertisementLocationPolicyPreservesOtherSettings() async throws {
        let (session, transport) = try await makeStartedSessionWithKnownConfig()
        await transport.clearSentData()

        async let setTask: () = session.setAdvertisementLocationPolicy(2)
        try await Task.sleep(for: .milliseconds(50))

        await transport.simulateOK()
        try await Task.sleep(for: .milliseconds(50))
        await transport.simulateReceive(makeSelfInfoResponse())
        try await setTask

        let sentData = await transport.sentData
        let setParamsCommand = sentData.first { $0.first == CommandCode.setOtherParams.rawValue }
        #expect(setParamsCommand != nil, "Expected setOtherParams command")

        if let cmd = setParamsCommand {
            #expect(cmd[3] == 2, "advertisementLocationPolicy should be 2")
            // Other settings should be preserved
            #expect(cmd[1] == 0, "manualAddContacts should be preserved")
            #expect(cmd[4] == 1, "multiAcks should be preserved")
        }
    }

    // MARK: - Mode Clamping

    @Test("setTelemetryModeBase clamps to 2-bit value")
    func setTelemetryModeBaseClampsToBits() async throws {
        let (session, transport) = try await makeStartedSessionWithKnownConfig()
        await transport.clearSentData()

        // Set mode to 0xFF, should be clamped to 0x03 (2 bits)
        async let setTask: () = session.setTelemetryModeBase(0xFF)
        try await Task.sleep(for: .milliseconds(50))

        await transport.simulateOK()
        try await Task.sleep(for: .milliseconds(50))
        await transport.simulateReceive(makeSelfInfoResponse())
        try await setTask

        let sentData = await transport.sentData
        let setParamsCommand = sentData.first { $0.first == CommandCode.setOtherParams.rawValue }

        if let cmd = setParamsCommand {
            // With env=1, loc=1, base=3 (clamped from 0xFF): (1 << 4) | (1 << 2) | 3 = 0x17
            #expect(cmd[2] == 0x17, "telemetry mode byte should have base=3 (clamped from 0xFF)")
        }
    }

    // MARK: - OtherParamsConfig

    @Test("OtherParamsConfig initializes from SelfInfo correctly")
    func otherParamsConfigInitFromSelfInfo() {
        let selfInfo = SelfInfo(
            advertisementType: 0,
            txPower: 20,
            maxTxPower: 30,
            publicKey: Data(repeating: 0xAB, count: 32),
            latitude: 0,
            longitude: 0,
            multiAcks: 3,
            advertisementLocationPolicy: 2,
            telemetryModeEnvironment: 1,
            telemetryModeLocation: 2,
            telemetryModeBase: 1,
            manualAddContacts: true,
            radioFrequency: 915.0,
            radioBandwidth: 125.0,
            radioSpreadingFactor: 10,
            radioCodingRate: 5,
            name: "Test"
        )

        let config = OtherParamsConfig(from: selfInfo)

        #expect(config.manualAddContacts == true)
        #expect(config.telemetryModeBase == 1)
        #expect(config.telemetryModeLocation == 2)
        #expect(config.telemetryModeEnvironment == 1)
        #expect(config.advertisementLocationPolicy == 2)
        #expect(config.multiAcks == 3)
    }

    @Test("OtherParamsConfig default initialization")
    func otherParamsConfigDefaultInit() {
        let config = OtherParamsConfig()

        #expect(config.manualAddContacts == false)
        #expect(config.telemetryModeBase == 0)
        #expect(config.telemetryModeLocation == 0)
        #expect(config.telemetryModeEnvironment == 0)
        #expect(config.advertisementLocationPolicy == 0)
        #expect(config.multiAcks == 0)
    }

    // MARK: - Helpers

    /// Creates a started session with a known configuration from selfInfo.
    /// The fixture has: manualAddContacts=false, telemetryModeBase=1,
    /// telemetryModeLocation=1, telemetryModeEnvironment=1,
    /// advertisementLocationPolicy=0, multiAcks=1
    private func makeStartedSessionWithKnownConfig() async throws -> (MeshCoreSession, MockTransport) {
        let transport = MockTransport()
        let session = MeshCoreSession(transport: transport)

        async let startTask: () = session.start()
        try await Task.sleep(for: .milliseconds(50))
        await transport.simulateReceive(makeSelfInfoResponse())
        try await startTask
        await transport.clearSentData()

        return (session, transport)
    }

    /// Creates a selfInfo response with known configuration values.
    /// telemetryMode byte 0x15 = (env=1 << 4) | (loc=1 << 2) | (base=1) = 0x15
    private func makeSelfInfoResponse() -> Data {
        var data = Data(capacity: 70)

        // Response code
        data.append(ResponseCode.selfInfo.rawValue)

        // Advertisement type: 0x01
        data.append(0x01)

        // TX power: 20 dBm
        data.append(20)

        // Max TX power: 30 dBm
        data.append(30)

        // Public key (32 bytes)
        data.append(contentsOf: [UInt8](repeating: 0xCD, count: 32))

        // Latitude: 37.7749
        data.append(contentsOf: withUnsafeBytes(of: Int32(37774900).littleEndian) { Array($0) })

        // Longitude: -122.4194
        data.append(contentsOf: withUnsafeBytes(of: Int32(-122419400).littleEndian) { Array($0) })

        // Multi-acks: 1
        data.append(0x01)

        // Advertisement location policy: 0
        data.append(0x00)

        // Telemetry mode: 0x15 (env=1, loc=1, base=1)
        data.append(0x15)

        // Manual add: false
        data.append(0x00)

        // Radio frequency: 915000 kHz = 915.0 MHz (little-endian)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(915000000).littleEndian) { Array($0) })

        // Radio bandwidth: 125000 Hz = 125 kHz (little-endian)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(125000000).littleEndian) { Array($0) })

        // Spreading factor: 10
        data.append(10)

        // Coding rate: 5
        data.append(5)

        // Name: "MyNode"
        data.append("MyNode".data(using: .utf8)!)

        return data
    }
}
