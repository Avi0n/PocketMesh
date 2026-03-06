import Foundation
import Testing
@testable import PocketMeshServices

@Suite("ConnectionManager Pairing Tests")
@MainActor
struct ConnectionManagerPairingTests {

    // MARK: - State Guard Tests

    @Test("unfavoritedNodeCount throws when not connected")
    func unfavoritedNodeCountThrowsWhenDisconnected() async throws {
        let (manager, _) = try ConnectionManager.createForTesting()

        try await #expect {
            _ = try await manager.unfavoritedNodeCount()
        } throws: { error in
            guard let e = error as? ConnectionError, case .notConnected = e else { return false }
            return true
        }
    }

    @Test("removeUnfavoritedNodes throws when not connected")
    func removeUnfavoritedNodesThrowsWhenDisconnected() async throws {
        let (manager, _) = try ConnectionManager.createForTesting()

        try await #expect {
            _ = try await manager.removeUnfavoritedNodes()
        } throws: { error in
            guard let e = error as? ConnectionError, case .notConnected = e else { return false }
            return true
        }
    }

    @Test("removeStaleNodes throws when not connected")
    func removeStaleNodesThrowsWhenDisconnected() async throws {
        let (manager, _) = try ConnectionManager.createForTesting()

        try await #expect {
            _ = try await manager.removeStaleNodes(olderThanDays: 30)
        } throws: { error in
            guard let e = error as? ConnectionError, case .notConnected = e else { return false }
            return true
        }
    }

    // MARK: - Device Update Tests

    @Test("updateDevice(with:) updates connectedDevice")
    func updateDeviceWithDTO() throws {
        let (manager, _) = try ConnectionManager.createForTesting()
        let device = DeviceDTO.testDevice(nodeName: "NewDevice")

        manager.updateDevice(with: device)

        #expect(manager.connectedDevice?.nodeName == "NewDevice")
        #expect(manager.connectedDevice?.id == device.id)
    }

    @Test("updateAutoAddConfig updates config when connected")
    func updateAutoAddConfigWhenConnected() throws {
        let (manager, _) = try ConnectionManager.createForTesting()
        let device = DeviceDTO.testDevice()
        manager.updateDevice(with: device)

        manager.updateAutoAddConfig(AutoAddConfig(bitmask: 5, maxHops: 3))

        #expect(manager.connectedDevice?.autoAddConfig == 5)
        #expect(manager.connectedDevice?.autoAddMaxHops == 3)
    }

    @Test("updateAutoAddConfig does nothing when not connected")
    func updateAutoAddConfigWhenDisconnected() throws {
        let (manager, _) = try ConnectionManager.createForTesting()

        manager.updateAutoAddConfig(AutoAddConfig(bitmask: 5, maxHops: 3))

        #expect(manager.connectedDevice == nil)
    }

    @Test("updateClientRepeat updates repeat flag when connected")
    func updateClientRepeatWhenConnected() throws {
        let (manager, _) = try ConnectionManager.createForTesting()
        let device = DeviceDTO.testDevice()
        manager.updateDevice(with: device)

        manager.updateClientRepeat(true)

        #expect(manager.connectedDevice?.clientRepeat == true)
    }

    @Test("updatePathHashMode updates hash mode when connected")
    func updatePathHashModeWhenConnected() throws {
        let (manager, _) = try ConnectionManager.createForTesting()
        let device = DeviceDTO.testDevice()
        manager.updateDevice(with: device)

        manager.updatePathHashMode(2)

        #expect(manager.connectedDevice?.pathHashMode == 2)
    }

    // MARK: - Pre-Repeat Settings Tests

    @Test("savePreRepeatSettings changes connectedDevice")
    func savePreRepeatSettingsChangesDevice() throws {
        let (manager, _) = try ConnectionManager.createForTesting()
        let device = DeviceDTO.testDevice(
            frequency: 915_000,
            bandwidth: 250_000,
            spreadingFactor: 10,
            codingRate: 5,
            txPower: 20
        )
        manager.updateDevice(with: device)
        let original = manager.connectedDevice

        manager.savePreRepeatSettings()

        #expect(manager.connectedDevice != original)
        #expect(manager.connectedDevice != nil)
    }

    @Test("clearPreRepeatSettings clears saved settings")
    func clearPreRepeatSettingsClears() throws {
        let (manager, _) = try ConnectionManager.createForTesting()
        let device = DeviceDTO.testDevice()
        manager.updateDevice(with: device)

        manager.savePreRepeatSettings()
        let afterSave = manager.connectedDevice

        manager.clearPreRepeatSettings()
        let afterClear = manager.connectedDevice

        #expect(afterSave != afterClear)
    }

    // MARK: - Data Operations

    @Test("fetchSavedDevices returns empty array when no devices saved")
    func fetchSavedDevicesEmpty() async throws {
        let (manager, _) = try ConnectionManager.createForTesting()

        let devices = try await manager.fetchSavedDevices()

        #expect(devices.isEmpty)
    }

    @Test("deleteDevice completes without error for non-existent device")
    func deleteDeviceNonExistent() async throws {
        let (manager, _) = try ConnectionManager.createForTesting()

        try await manager.deleteDevice(id: UUID())
    }
}
