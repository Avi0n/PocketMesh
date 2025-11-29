import Foundation
import SwiftData

@MainActor
public final class DeviceRepository {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func getActiveDevice() throws -> Device? {
        let descriptor = FetchDescriptor<Device>(
            predicate: #Predicate { $0.isActive == true },
        )
        let devices = try modelContext.fetch(descriptor)
        return devices.first
    }

    public func getDevice(byPublicKey publicKey: Data) throws -> Device? {
        let descriptor = FetchDescriptor<Device>(
            predicate: #Predicate { $0.publicKey == publicKey },
        )
        let devices = try modelContext.fetch(descriptor)
        return devices.first
    }

    public func createOrUpdateDevice(from selfInfo: SelfInfo, name: String, firmwareVersion: String) throws -> Device {
        if let existing = try getDevice(byPublicKey: selfInfo.publicKey) {
            // Update existing
            existing.name = name
            existing.firmwareVersion = firmwareVersion
            existing.lastConnected = Date()
            existing.frequency = selfInfo.frequency
            existing.bandwidth = selfInfo.bandwidth
            existing.spreadingFactor = selfInfo.spreadingFactor
            existing.codingRate = selfInfo.codingRate
            existing.txPower = selfInfo.txPower
            existing.latitude = Double(selfInfo.latitude) / 1_000_000.0
            existing.longitude = Double(selfInfo.longitude) / 1_000_000.0
            return existing
        } else {
            // Create new
            let device = Device(
                publicKey: selfInfo.publicKey,
                name: name,
                firmwareVersion: firmwareVersion,
                frequency: selfInfo.frequency,
                bandwidth: selfInfo.bandwidth,
                spreadingFactor: selfInfo.spreadingFactor,
                codingRate: selfInfo.codingRate,
                txPower: selfInfo.txPower,
            )
            device.latitude = Double(selfInfo.latitude) / 1_000_000.0
            device.longitude = Double(selfInfo.longitude) / 1_000_000.0
            modelContext.insert(device)
            return device
        }
    }

    public func setActiveDevice(_ device: Device) throws {
        // Deactivate all other devices
        let descriptor = FetchDescriptor<Device>()
        let allDevices = try modelContext.fetch(descriptor)
        allDevices.forEach { $0.isActive = false }

        // Activate selected device
        device.isActive = true
        try modelContext.save()
    }
}
