import Foundation
import Testing
@testable import MeshCore
@testable import PocketMeshServices

@Suite("DeviceDTO Client Repeat Tests")
struct DeviceDTOClientRepeatTests {

    // MARK: - Test Data

    private static let testSelfInfo = SelfInfo(
        advertisementType: 1,
        txPower: 20,
        maxTxPower: 30,
        publicKey: Data(repeating: 0xAB, count: 32),
        latitude: 37.7749,
        longitude: -122.4194,
        multiAcks: 2,
        advertisementLocationPolicy: 1,
        telemetryModeEnvironment: 0,
        telemetryModeLocation: 0,
        telemetryModeBase: 2,
        manualAddContacts: false,
        radioFrequency: 906.875,
        radioBandwidth: 250.0,
        radioSpreadingFactor: 11,
        radioCodingRate: 8,
        name: "UpdatedNode"
    )

    private func makeDevice(
        firmwareVersion: UInt8 = 9,
        frequency: UInt32 = 915_000,
        bandwidth: UInt32 = 250_000,
        spreadingFactor: UInt8 = 8,
        codingRate: UInt8 = 5,
        clientRepeat: Bool = false,
        preRepeatFrequency: UInt32? = nil,
        preRepeatBandwidth: UInt32? = nil,
        preRepeatSpreadingFactor: UInt8? = nil,
        preRepeatCodingRate: UInt8? = nil
    ) -> DeviceDTO {
        DeviceDTO(from: Device(
            publicKey: Data(repeating: 0x01, count: 32),
            nodeName: "TestDevice",
            firmwareVersion: firmwareVersion,
            firmwareVersionString: "v1.13.0",
            manufacturerName: "TestMfg",
            buildDate: "01 Jan 2025",
            maxContacts: 100,
            maxChannels: 8,
            frequency: frequency,
            bandwidth: bandwidth,
            spreadingFactor: spreadingFactor,
            codingRate: codingRate,
            txPower: 20,
            maxTxPower: 20,
            latitude: 0,
            longitude: 0,
            blePin: 0,
            clientRepeat: clientRepeat,
            preRepeatFrequency: preRepeatFrequency,
            preRepeatBandwidth: preRepeatBandwidth,
            preRepeatSpreadingFactor: preRepeatSpreadingFactor,
            preRepeatCodingRate: preRepeatCodingRate,
            manualAddContacts: false,
            multiAcks: 2,
            telemetryModeBase: 2,
            telemetryModeLoc: 0,
            telemetryModeEnv: 0,
            advertLocationPolicy: 0,
            lastConnected: Date(),
            lastContactSync: 0,
            isActive: true
        ))
    }

    // MARK: - supportsClientRepeat

    @Test("supportsClientRepeat returns true for firmware v9")
    func supportsClientRepeat_v9_returnsTrue() {
        let device = makeDevice(firmwareVersion: 9)
        #expect(device.supportsClientRepeat == true)
    }

    @Test("supportsClientRepeat returns false for firmware v8")
    func supportsClientRepeat_v8_returnsFalse() {
        let device = makeDevice(firmwareVersion: 8)
        #expect(device.supportsClientRepeat == false)
    }

    @Test("supportsClientRepeat returns true for firmware v10")
    func supportsClientRepeat_v10_returnsTrue() {
        let device = makeDevice(firmwareVersion: 10)
        #expect(device.supportsClientRepeat == true)
    }

    // MARK: - withClientRepeat

    @Test("withClientRepeat updates value from false to true")
    func withClientRepeat_updatesValue() {
        let device = makeDevice(clientRepeat: false, preRepeatFrequency: 906_875)
        let updated = device.withClientRepeat(true)

        #expect(updated.clientRepeat == true)
        // Other fields unchanged
        #expect(updated.nodeName == device.nodeName)
        #expect(updated.frequency == device.frequency)
        #expect(updated.preRepeatFrequency == 906_875)
    }

    @Test("withClientRepeat updates value from true to false")
    func withClientRepeat_disables() {
        let device = makeDevice(clientRepeat: true)
        let updated = device.withClientRepeat(false)

        #expect(updated.clientRepeat == false)
    }

    // MARK: - savingPreRepeatSettings

    @Test("savingPreRepeatSettings copies current radio params")
    func savingPreRepeatSettings_copiesCurrentRadioParams() {
        let device = makeDevice(
            frequency: 915_000,
            bandwidth: 250_000,
            spreadingFactor: 8,
            codingRate: 5
        )
        let saved = device.savingPreRepeatSettings()

        #expect(saved.preRepeatFrequency == 915_000)
        #expect(saved.preRepeatBandwidth == 250_000)
        #expect(saved.preRepeatSpreadingFactor == 8)
        #expect(saved.preRepeatCodingRate == 5)
    }

    @Test("savingPreRepeatSettings preserves other fields")
    func savingPreRepeatSettings_preservesOtherFields() {
        let device = makeDevice(clientRepeat: true)
        let saved = device.savingPreRepeatSettings()

        #expect(saved.clientRepeat == true)
        #expect(saved.nodeName == device.nodeName)
        #expect(saved.firmwareVersion == device.firmwareVersion)
    }

    // MARK: - clearingPreRepeatSettings

    @Test("clearingPreRepeatSettings sets all preRepeat fields to nil")
    func clearingPreRepeatSettings_setsAllToNil() {
        let device = makeDevice(
            preRepeatFrequency: 915_000,
            preRepeatBandwidth: 250_000,
            preRepeatSpreadingFactor: 8,
            preRepeatCodingRate: 5
        )
        let cleared = device.clearingPreRepeatSettings()

        #expect(cleared.preRepeatFrequency == nil)
        #expect(cleared.preRepeatBandwidth == nil)
        #expect(cleared.preRepeatSpreadingFactor == nil)
        #expect(cleared.preRepeatCodingRate == nil)
        #expect(cleared.hasPreRepeatSettings == false)
    }

    // MARK: - hasPreRepeatSettings

    @Test("hasPreRepeatSettings requires all four fields")
    func hasPreRepeatSettings_requiresAllFourFields() {
        // Only frequency set
        let partial = makeDevice(preRepeatFrequency: 915_000)
        #expect(partial.hasPreRepeatSettings == false)

        // All four set
        let complete = makeDevice(
            preRepeatFrequency: 915_000,
            preRepeatBandwidth: 250_000,
            preRepeatSpreadingFactor: 8,
            preRepeatCodingRate: 5
        )
        #expect(complete.hasPreRepeatSettings == true)
    }

    @Test("hasPreRepeatSettings returns false when all nil")
    func hasPreRepeatSettings_allNil() {
        let device = makeDevice()
        #expect(device.hasPreRepeatSettings == false)
    }

    // MARK: - updating(from: SelfInfo) carries forward client repeat fields

    @Test("updating(from: SelfInfo) carries forward clientRepeat")
    func updatingFromSelfInfo_carriesForwardClientRepeat() {
        let device = makeDevice(clientRepeat: true)
        let updated = device.updating(from: Self.testSelfInfo)

        #expect(updated.clientRepeat == true)
    }

    @Test("updating(from: SelfInfo) carries forward preRepeat settings")
    func updatingFromSelfInfo_carriesForwardPreRepeatSettings() {
        let device = makeDevice(
            preRepeatFrequency: 915_000,
            preRepeatBandwidth: 250_000,
            preRepeatSpreadingFactor: 8,
            preRepeatCodingRate: 5
        )
        let updated = device.updating(from: Self.testSelfInfo)

        #expect(updated.preRepeatFrequency == 915_000)
        #expect(updated.preRepeatBandwidth == 250_000)
        #expect(updated.preRepeatSpreadingFactor == 8)
        #expect(updated.preRepeatCodingRate == 5)
        #expect(updated.hasPreRepeatSettings == true)
    }

    @Test("updating(from: SelfInfo) updates radio params from SelfInfo")
    func updatingFromSelfInfo_updatesRadioParams() {
        let device = makeDevice(
            frequency: 915_000,
            bandwidth: 250_000,
            spreadingFactor: 8,
            codingRate: 5
        )
        let updated = device.updating(from: Self.testSelfInfo)

        // SelfInfo has radioFrequency: 906.875 MHz -> 906875 kHz
        #expect(updated.frequency == 906_875)
        // SelfInfo has radioBandwidth: 250.0 kHz -> 250000 kHz
        #expect(updated.bandwidth == 250_000)
        #expect(updated.spreadingFactor == 11)
        #expect(updated.codingRate == 8)
        #expect(updated.nodeName == "UpdatedNode")
    }
}
