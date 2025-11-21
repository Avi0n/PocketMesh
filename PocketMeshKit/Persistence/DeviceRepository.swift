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
            existing.radioFrequency = selfInfo.radioFrequency
            existing.radioBandwidth = selfInfo.radioBandwidth
            existing.radioSpreadingFactor = selfInfo.radioSpreadingFactor
            existing.radioCodingRate = selfInfo.radioCodingRate
            existing.txPower = selfInfo.txPower
            existing.latitude = selfInfo.latitude
            existing.longitude = selfInfo.longitude
            return existing
        } else {
            // Create new
            let device = Device(
                publicKey: selfInfo.publicKey,
                name: name,
                firmwareVersion: firmwareVersion,
                radioFrequency: selfInfo.radioFrequency,
                radioBandwidth: selfInfo.radioBandwidth,
                radioSpreadingFactor: selfInfo.radioSpreadingFactor,
                radioCodingRate: selfInfo.radioCodingRate,
                txPower: selfInfo.txPower,
            )
            device.latitude = selfInfo.latitude
            device.longitude = selfInfo.longitude
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
