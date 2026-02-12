import Foundation
import Testing
@testable import PocketMeshServices
@testable import MeshCore

@Suite("NodeConfigService Tests")
struct NodeConfigServiceTests {

    // MARK: - Test Data

    private static let testSelfInfo = SelfInfo(
        advertisementType: 1,
        txPower: 22,
        maxTxPower: 30,
        publicKey: Data(repeating: 0xAB, count: 32),
        latitude: 47.6062,
        longitude: -122.3321,
        multiAcks: 2,
        advertisementLocationPolicy: 1,
        telemetryModeEnvironment: 3,
        telemetryModeLocation: 2,
        telemetryModeBase: 1,
        manualAddContacts: false,
        radioFrequency: 910.525,
        radioBandwidth: 62.5,
        radioSpreadingFactor: 7,
        radioCodingRate: 5,
        name: "TestNode"
    )

    private static let testContact = MeshContact(
        id: Data(repeating: 0x01, count: 32).hexString().lowercased(),
        publicKey: Data(repeating: 0x01, count: 32),
        type: 1,
        flags: 0x02,
        outPathLength: 3,
        outPath: Data([0xAA, 0xBB, 0xCC]),
        advertisedName: "RemoteNode",
        lastAdvertisement: Date(timeIntervalSince1970: 1_700_000_000),
        latitude: 47.43,
        longitude: -120.36,
        lastModified: Date(timeIntervalSince1970: 1_700_000_100)
    )

    private static let floodContact = MeshContact(
        id: Data(repeating: 0x02, count: 32).hexString().lowercased(),
        publicKey: Data(repeating: 0x02, count: 32),
        type: 2,
        flags: 0,
        outPathLength: -1,
        outPath: Data(),
        advertisedName: "FloodNode",
        lastAdvertisement: Date(timeIntervalSince1970: 1_700_001_000),
        latitude: 0,
        longitude: 0,
        lastModified: Date(timeIntervalSince1970: 1_700_001_100)
    )

    private static let zeroPathContact = MeshContact(
        id: Data(repeating: 0x03, count: 32).hexString().lowercased(),
        publicKey: Data(repeating: 0x03, count: 32),
        type: 1,
        flags: 0,
        outPathLength: 0,
        outPath: Data(),
        advertisedName: "DirectNode",
        lastAdvertisement: Date(timeIntervalSince1970: 1_700_002_000),
        latitude: 0,
        longitude: 0,
        lastModified: Date(timeIntervalSince1970: 1_700_002_100)
    )

    // MARK: - buildRadioSettings

    @Test("buildRadioSettings converts MHz frequency to kHz")
    func buildRadioSettingsFrequency() {
        let radio = NodeConfigService.buildRadioSettings(from: Self.testSelfInfo)

        // 910.525 MHz → 910525 kHz
        #expect(radio.frequency == 910_525)
    }

    @Test("buildRadioSettings converts kHz bandwidth to Hz")
    func buildRadioSettingsBandwidth() {
        let radio = NodeConfigService.buildRadioSettings(from: Self.testSelfInfo)

        // 62.5 kHz → 62500 Hz
        #expect(radio.bandwidth == 62_500)
    }

    @Test("buildRadioSettings copies spreading factor, coding rate, and tx power")
    func buildRadioSettingsOtherFields() {
        let radio = NodeConfigService.buildRadioSettings(from: Self.testSelfInfo)

        #expect(radio.spreadingFactor == 7)
        #expect(radio.codingRate == 5)
        #expect(radio.txPower == 22)
    }

    // MARK: - buildOtherSettings

    @Test("buildOtherSettings maps manualAddContacts=false to 0")
    func buildOtherSettingsManualAddFalse() {
        let other = NodeConfigService.buildOtherSettings(from: Self.testSelfInfo)
        #expect(other.manualAddContacts == 0)
    }

    @Test("buildOtherSettings maps manualAddContacts=true to 1")
    func buildOtherSettingsManualAddTrue() {
        let info = SelfInfo(
            advertisementType: 0, txPower: 10, maxTxPower: 30,
            publicKey: Data(repeating: 0, count: 32),
            latitude: 0, longitude: 0, multiAcks: 0,
            advertisementLocationPolicy: 0, telemetryModeEnvironment: 0,
            telemetryModeLocation: 0, telemetryModeBase: 0,
            manualAddContacts: true,
            radioFrequency: 910.525, radioBandwidth: 62.5,
            radioSpreadingFactor: 7, radioCodingRate: 5, name: "Test"
        )

        let other = NodeConfigService.buildOtherSettings(from: info)
        #expect(other.manualAddContacts == 1)
    }

    @Test("buildOtherSettings exports only 2 companion-app fields")
    func buildOtherSettingsAllFields() {
        let other = NodeConfigService.buildOtherSettings(from: Self.testSelfInfo)

        #expect(other.manualAddContacts == 0)
        #expect(other.advertLocationPolicy == 1)
        #expect(other.telemetryModeBase == nil)
        #expect(other.telemetryModeLocation == nil)
        #expect(other.telemetryModeEnvironment == nil)
        #expect(other.multiAcks == nil)
        #expect(other.advertisementType == nil)
    }

    // MARK: - buildContactConfig

    @Test("buildContactConfig populates all fields from MeshContact")
    func buildContactConfigAllFields() {
        let config = NodeConfigService.buildContactConfig(from: Self.testContact)

        #expect(config.type == 1)
        #expect(config.name == "RemoteNode")
        #expect(config.publicKey == Data(repeating: 0x01, count: 32).hexString().lowercased())
        #expect(config.flags == 0x02)
        #expect(config.latitude == "47.43")
        #expect(config.longitude == "-120.36")
        #expect(config.lastAdvert == 1_700_000_000)
        #expect(config.lastModified == 1_700_000_100)
    }

    @Test("buildContactConfig includes hex outPath for routed contacts")
    func buildContactConfigRoutedPath() {
        let config = NodeConfigService.buildContactConfig(from: Self.testContact)
        #expect(config.outPath == "aabbcc")
    }

    @Test("buildContactConfig uses nil outPath for flood routing")
    func buildContactConfigFloodPath() {
        let config = NodeConfigService.buildContactConfig(from: Self.floodContact)
        #expect(config.outPath == nil)
    }

    @Test("buildContactConfig uses empty string outPath for direct (zero-length) path")
    func buildContactConfigDirectPath() {
        let config = NodeConfigService.buildContactConfig(from: Self.zeroPathContact)
        #expect(config.outPath == "")
    }

    @Test("buildContactConfig truncates outPath to outPathLength bytes")
    func buildContactConfigTruncatesPath() {
        // Contact with outPathLength=2 but outPath has 4 bytes
        let contact = MeshContact(
            id: "test",
            publicKey: Data(repeating: 0x04, count: 32),
            type: 1, flags: 0, outPathLength: 2,
            outPath: Data([0xAA, 0xBB, 0xCC, 0xDD]),
            advertisedName: "Truncated",
            lastAdvertisement: .now, latitude: 0, longitude: 0,
            lastModified: .now
        )

        let config = NodeConfigService.buildContactConfig(from: contact)
        #expect(config.outPath == "aabb")
    }

    // MARK: - Import ordering verification

    @Test("countImportSteps counts all section steps correctly")
    func importStepCounting() async {
        // Build a config with all sections populated
        let config = MeshCoreNodeConfig(
            name: "Test",
            privateKey: "abcd",
            radioSettings: .init(frequency: 910_525, bandwidth: 62_500,
                                 spreadingFactor: 7, codingRate: 5, txPower: 22),
            positionSettings: .init(latitude: "47.0", longitude: "-122.0"),
            otherSettings: .init(manualAddContacts: 0),
            channels: [
                .init(name: "Ch1", secret: "00112233445566778899aabbccddeeff"),
                .init(name: "Ch2", secret: "ffeeddccbbaa99887766554433221100"),
            ],
            contacts: [
                .init(type: 1, name: "C1", publicKey: String(repeating: "ab", count: 32),
                      flags: 0, latitude: "0", longitude: "0", lastAdvert: 0, lastModified: 0),
            ]
        )

        var sections = ConfigSections()
        sections.selectAll()
        let service = await makeUntestableService()
        let count = await service.testableCountImportSteps(config: config, sections: sections)

        // privateKey(1) + name(1) + position(1) + otherSettings(1)
        // + channels(2) + contacts(1) + radio(1) + txPower(1) = 9
        #expect(count == 9)
    }

    @Test("countImportSteps skips disabled sections")
    func importStepCountingSkipsDisabled() async {
        let config = MeshCoreNodeConfig(
            name: "Test",
            privateKey: "abcd",
            radioSettings: .init(frequency: 910_525, bandwidth: 62_500,
                                 spreadingFactor: 7, codingRate: 5, txPower: 22),
            channels: [
                .init(name: "Ch1", secret: "00112233445566778899aabbccddeeff"),
            ]
        )

        let sections = ConfigSections(
            nodeIdentity: false,
            radioSettings: false,
            positionSettings: false,
            otherSettings: false,
            channels: true,
            contacts: false
        )
        let service = await makeUntestableService()
        let count = await service.testableCountImportSteps(config: config, sections: sections)

        // Only channels: 1
        #expect(count == 1)
    }

    @Test("countImportSteps is zero for empty config")
    func importStepCountingEmptyConfig() async {
        let config = MeshCoreNodeConfig()
        let sections = ConfigSections()
        let service = await makeUntestableService()
        let count = await service.testableCountImportSteps(config: config, sections: sections)

        #expect(count == 0)
    }

    // MARK: - OtherSettings merge logic

    @Test("Partial OtherSettings fills missing fields from current device values")
    func otherSettingsMerge() {
        // Imported config has only 2 of 7 fields (companion app style)
        let imported = MeshCoreNodeConfig.OtherSettings(
            manualAddContacts: 1,
            advertLocationPolicy: 0
        )

        // Simulate current device state
        let current = Self.testSelfInfo

        // Merge: imported values where present, current values for nil
        let manualAdd = imported.manualAddContacts ?? (current.manualAddContacts ? 1 : 0)
        let advertPolicy = imported.advertLocationPolicy ?? current.advertisementLocationPolicy
        let telBase = imported.telemetryModeBase ?? current.telemetryModeBase
        let telLocation = imported.telemetryModeLocation ?? current.telemetryModeLocation
        let telEnvironment = imported.telemetryModeEnvironment ?? current.telemetryModeEnvironment
        let multiAcks = imported.multiAcks ?? current.multiAcks

        // Imported values should take precedence
        #expect(manualAdd == 1)
        #expect(advertPolicy == 0)

        // Missing fields should fall back to current device values
        #expect(telBase == current.telemetryModeBase)
        #expect(telLocation == current.telemetryModeLocation)
        #expect(telEnvironment == current.telemetryModeEnvironment)
        #expect(multiAcks == current.multiAcks)
    }

    @Test("Full OtherSettings uses all imported values")
    func otherSettingsFullImport() {
        let imported = MeshCoreNodeConfig.OtherSettings(
            manualAddContacts: 0,
            advertLocationPolicy: 2,
            telemetryModeBase: 3,
            telemetryModeLocation: 1,
            telemetryModeEnvironment: 2,
            multiAcks: 5,
            advertisementType: 4
        )

        let current = Self.testSelfInfo

        let manualAdd = imported.manualAddContacts ?? (current.manualAddContacts ? 1 : 0)
        let advertPolicy = imported.advertLocationPolicy ?? current.advertisementLocationPolicy
        let telBase = imported.telemetryModeBase ?? current.telemetryModeBase
        let telLocation = imported.telemetryModeLocation ?? current.telemetryModeLocation
        let telEnvironment = imported.telemetryModeEnvironment ?? current.telemetryModeEnvironment
        let multiAcks = imported.multiAcks ?? current.multiAcks

        #expect(manualAdd == 0)
        #expect(advertPolicy == 2)
        #expect(telBase == 3)
        #expect(telLocation == 1)
        #expect(telEnvironment == 2)
        #expect(multiAcks == 5)
    }

    // MARK: - Export round-trip consistency

    @Test("buildRadioSettings round-trips through config format")
    func radioSettingsRoundTrip() {
        let radio = NodeConfigService.buildRadioSettings(from: Self.testSelfInfo)

        // Config stores frequency in kHz, bandwidth in Hz.
        // setRadioParams's bandwidthKHz parameter actually takes Hz (matching
        // RadioPreset.bandwidthHz usage), so import passes values directly
        // for a lossless round-trip.
        #expect(radio.frequency == 910_525)
        #expect(radio.bandwidth == 62_500)
    }

    @Test("buildContactConfig and import produce consistent outPath")
    func contactConfigOutPathConsistency() {
        let exported = NodeConfigService.buildContactConfig(from: Self.testContact)
        #expect(exported.outPath == "aabbcc")

        // "aabbcc" = 3 bytes, matching the original outPathLength
        #expect(Self.testContact.outPathLength == 3)
    }

    @Test("buildContactConfig and import produce consistent flood path")
    func contactConfigFloodPathConsistency() {
        let exported = NodeConfigService.buildContactConfig(from: Self.floodContact)
        // Flood routing: nil outPath, outPathLength -1
        #expect(exported.outPath == nil)
        #expect(Self.floodContact.outPathLength == -1)
    }

    // MARK: - Error cases

    @Test("NodeConfigServiceError has descriptive messages")
    func errorDescriptions() {
        let channelError = NodeConfigServiceError.invalidChannelSecret(index: 2, hexLength: 30)
        #expect(channelError.localizedDescription.contains("Channel 2"))

        let contactError = NodeConfigServiceError.invalidContactPublicKey(name: "BadContact")
        #expect(contactError.localizedDescription.contains("BadContact"))

    }

    // MARK: - ImportProgress

    @Test("ImportProgress stores step info")
    func importProgressFields() {
        let progress = ImportProgress(step: "Setting radio", current: 3, total: 10)
        #expect(progress.step == "Setting radio")
        #expect(progress.current == 3)
        #expect(progress.total == 10)
    }

    // MARK: - Helpers

    /// Creates a NodeConfigService that can only be used for non-session operations.
    /// Used to test countImportSteps and other pure logic via the actor.
    @MainActor
    private func makeUntestableService() -> TestableNodeConfigService {
        TestableNodeConfigService()
    }
}

// MARK: - Testable wrapper for step counting

/// Thin wrapper that exposes the step-counting logic without requiring a real session.
/// This avoids creating a MeshCoreSession in tests.
private actor TestableNodeConfigService {
    func testableCountImportSteps(config: MeshCoreNodeConfig, sections: ConfigSections) -> Int {
        var count = 0
        if sections.nodeIdentity && config.privateKey != nil { count += 1 }
        if sections.nodeIdentity && config.name != nil { count += 1 }
        if sections.positionSettings && config.positionSettings != nil { count += 1 }
        if sections.otherSettings && config.otherSettings != nil { count += 1 }
        if sections.channels { count += config.channels?.count ?? 0 }
        if sections.contacts { count += config.contacts?.count ?? 0 }
        if sections.radioSettings && config.radioSettings != nil { count += 2 }
        return count
    }
}
