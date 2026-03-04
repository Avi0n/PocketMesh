import Foundation
import Testing
@testable import MeshCore
@testable import PocketMeshServices

@Suite("Error Localization Tests")
struct ErrorLocalizationTests {

    // MARK: - MeshCoreError Tests

    @Test("MeshCoreError.timeout produces human-readable description")
    func meshCoreTimeout() {
        let error: MeshCoreError = .timeout
        #expect(error.localizedDescription == "The operation timed out. Please try again.")
    }

    @Test("MeshCoreError.deviceError maps known firmware codes", arguments: [
        (UInt8(0x01), "Command not supported by device firmware."),
        (UInt8(0x02), "Item not found on device."),
        (UInt8(0x03), "Device storage is full."),
        (UInt8(0x04), "Device is in an invalid state for this operation."),
        (UInt8(0x05), "Device file system error."),
        (UInt8(0x06), "Invalid parameter sent to device."),
    ])
    func meshCoreDeviceErrorKnownCodes(code: UInt8, expected: String) {
        let error: MeshCoreError = .deviceError(code: code)
        #expect(error.localizedDescription == expected, "Code \(code) should produce: \(expected)")
    }

    @Test("MeshCoreError.deviceError falls back for unknown codes")
    func meshCoreDeviceErrorUnknownCode() {
        let error: MeshCoreError = .deviceError(code: 10)
        #expect(error.localizedDescription == "Device error (code 10).")
    }

    @Test("MeshCoreError.deviceError handles code zero")
    func meshCoreDeviceErrorCodeZero() {
        let error: MeshCoreError = .deviceError(code: 0)
        #expect(error.localizedDescription == "Device error (code 0).")
    }

    @Test("MeshCoreError bluetooth errors produce readable descriptions")
    func meshCoreBluetoothErrors() {
        #expect(MeshCoreError.bluetoothUnavailable.localizedDescription == "Bluetooth is not available on this device.")
        #expect(MeshCoreError.bluetoothUnauthorized.localizedDescription == "Bluetooth permission is required. Please enable it in Settings.")
        #expect(MeshCoreError.bluetoothPoweredOff.localizedDescription == "Bluetooth is turned off. Please enable Bluetooth to connect.")
    }

    @Test("MeshCoreError.connectionLost includes underlying error when present")
    func meshCoreConnectionLostWithUnderlying() {
        let underlying = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "link dropped"])
        let error: MeshCoreError = .connectionLost(underlying: underlying)
        #expect(error.localizedDescription.contains("Connection to device was lost"))
        #expect(error.localizedDescription.contains("link dropped"))
    }

    @Test("MeshCoreError.connectionLost without underlying error")
    func meshCoreConnectionLostWithoutUnderlying() {
        let error: MeshCoreError = .connectionLost(underlying: nil)
        #expect(error.localizedDescription == "Connection to device was lost.")
    }

    @Test("MeshCoreError.featureDisabled produces readable description")
    func meshCoreFeatureDisabled() {
        #expect(MeshCoreError.featureDisabled.localizedDescription == "This feature is disabled on the device.")
    }

    @Test("MeshCoreError.sessionNotStarted produces readable description")
    func meshCoreSessionNotStarted() {
        #expect(MeshCoreError.sessionNotStarted.localizedDescription == "Session has not been started.")
    }

    // MARK: - ProtocolError Tests

    @Test("ProtocolError cases produce non-empty, readable descriptions", arguments: [
        ProtocolError.unsupportedCommand, .notFound, .tableFull,
        .badState, .fileIOError, .illegalArgument,
    ])
    func protocolErrorDescriptions(protocolError: ProtocolError) {
        let description = protocolError.localizedDescription
        #expect(!description.isEmpty, "ProtocolError.\(protocolError) should have a description")
        #expect(!description.contains("ProtocolError"), "Should not contain raw type name")
    }

    // MARK: - Service Error Session Pass-Through Tests

    @Test("MessageServiceError.sessionError passes through MeshCoreError description")
    func messageServiceSessionPassThrough() {
        let meshError: MeshCoreError = .deviceError(code: 0x03)
        let serviceError: MessageServiceError = .sessionError(meshError)
        #expect(serviceError.localizedDescription == "Device storage is full.")
    }

    @Test("ChannelServiceError.sessionError passes through MeshCoreError description")
    func channelServiceSessionPassThrough() {
        let meshError: MeshCoreError = .timeout
        let serviceError: ChannelServiceError = .sessionError(meshError)
        #expect(serviceError.localizedDescription == "The operation timed out. Please try again.")
    }

    @Test("SettingsServiceError.sessionError passes through without prefix")
    func settingsServiceSessionPassThrough() {
        let meshError: MeshCoreError = .notConnected
        let serviceError: SettingsServiceError = .sessionError(meshError)
        #expect(!serviceError.localizedDescription.contains("Session error:"))
        #expect(serviceError.localizedDescription == "Not connected to device.")
    }

    @Test("RemoteNodeError.sessionError passes through without prefix")
    func remoteNodeSessionPassThrough() {
        let meshError: MeshCoreError = .bluetoothPoweredOff
        let serviceError: RemoteNodeError = .sessionError(meshError)
        #expect(!serviceError.localizedDescription.contains("Session error:"))
        #expect(serviceError.localizedDescription == "Bluetooth is turned off. Please enable Bluetooth to connect.")
    }

    // MARK: - Service Error Spot Checks

    @Test("AdvertisementError.notConnected produces readable description")
    func advertisementNotConnected() {
        #expect(AdvertisementError.notConnected.localizedDescription == "Not connected to device.")
    }

    @Test("RoomServerError.permissionDenied produces readable description")
    func roomServerPermissionDenied() {
        #expect(RoomServerError.permissionDenied.localizedDescription == "Permission denied.")
    }

    @Test("BinaryProtocolError.timeout produces readable description")
    func binaryProtocolTimeout() {
        #expect(BinaryProtocolError.timeout.localizedDescription == "Request timed out.")
    }

    @Test("SyncCoordinatorError.alreadySyncing produces readable description")
    func syncCoordinatorAlreadySyncing() {
        #expect(SyncCoordinatorError.alreadySyncing.localizedDescription == "A sync is already in progress.")
    }

    @Test("PersistenceStoreError.contactNotFound produces readable description")
    func persistenceStoreContactNotFound() {
        #expect(PersistenceStoreError.contactNotFound.localizedDescription == "Contact not found.")
    }
}
