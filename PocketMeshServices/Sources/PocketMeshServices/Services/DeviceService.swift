import Foundation
import MeshCore
import OSLog

// MARK: - Device Service Errors

public enum DeviceServiceError: Error, LocalizedError, Sendable {
    case deviceNotFound
    case persistenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "Device not found"
        case .persistenceFailed(let reason):
            return "Failed to save device settings: \(reason)"
        }
    }
}

// MARK: - Device Service

/// Service for managing device-level data and settings persistence.
/// Handles local device configuration that doesn't require MeshCore communication.
public actor DeviceService {
    private let dataStore: PersistenceStore
    private let logger = PersistentLogger(subsystem: "com.pocketmesh.services", category: "DeviceService")

    /// Callback invoked when device data is successfully updated.
    /// Used to refresh ConnectionManager.connectedDevice for UI updates.
    private var onDeviceUpdated: (@Sendable (DeviceDTO) async -> Void)?

    public init(dataStore: PersistenceStore) {
        self.dataStore = dataStore
    }

    /// Sets the callback for device updates.
    public func setDeviceUpdateCallback(
        _ callback: @escaping @Sendable (DeviceDTO) async -> Void
    ) {
        onDeviceUpdated = callback
    }

    // MARK: - OCV Settings

    /// Update OCV settings for the connected device.
    ///
    /// - Parameters:
    ///   - deviceID: The UUID of the device to update
    ///   - preset: The OCV preset name (e.g., "liIon", "liPo", "custom")
    ///   - customArray: Custom OCV array as comma-separated string (required if preset is "custom")
    /// - Throws: DeviceServiceError if device not found or persistence fails
    public func updateOCVSettings(
        deviceID: UUID,
        preset: String,
        customArray: String?
    ) async throws {
        logger.info("Updating OCV settings for device \(deviceID): preset=\(preset)")

        // Fetch current device
        guard var device = try await dataStore.fetchDevice(id: deviceID) else {
            logger.error("Device not found: \(deviceID)")
            throw DeviceServiceError.deviceNotFound
        }

        // Update OCV fields
        device = DeviceDTO(
            id: device.id,
            publicKey: device.publicKey,
            nodeName: device.nodeName,
            firmwareVersion: device.firmwareVersion,
            firmwareVersionString: device.firmwareVersionString,
            manufacturerName: device.manufacturerName,
            buildDate: device.buildDate,
            maxContacts: device.maxContacts,
            maxChannels: device.maxChannels,
            frequency: device.frequency,
            bandwidth: device.bandwidth,
            spreadingFactor: device.spreadingFactor,
            codingRate: device.codingRate,
            txPower: device.txPower,
            maxTxPower: device.maxTxPower,
            latitude: device.latitude,
            longitude: device.longitude,
            blePin: device.blePin,
            manualAddContacts: device.manualAddContacts,
            multiAcks: device.multiAcks,
            telemetryModeBase: device.telemetryModeBase,
            telemetryModeLoc: device.telemetryModeLoc,
            telemetryModeEnv: device.telemetryModeEnv,
            advertLocationPolicy: device.advertLocationPolicy,
            lastConnected: device.lastConnected,
            lastContactSync: device.lastContactSync,
            isActive: device.isActive,
            ocvPreset: preset,
            customOCVArrayString: customArray
        )

        // Save to persistence
        do {
            try await dataStore.saveDevice(device)
            logger.info("OCV settings saved successfully")
        } catch {
            logger.error("Failed to save OCV settings: \(error.localizedDescription)")
            throw DeviceServiceError.persistenceFailed(error.localizedDescription)
        }

        // Notify callback for UI refresh
        await onDeviceUpdated?(device)
    }
}
