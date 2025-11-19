import Foundation

extension MeshCoreProtocol {

    /// CMD_SET_RADIO_PARAMS (11): Set radio parameters
    public func setRadioParameters(
        frequency: UInt32,
        bandwidth: UInt32,
        spreadingFactor: UInt8,
        codingRate: UInt8
    ) async throws {
        var payload = Data()

        // All uint32 little-endian, except SF and CR (uint8)
        withUnsafeBytes(of: frequency.littleEndian) { payload.append(contentsOf: $0) }
        withUnsafeBytes(of: bandwidth.littleEndian) { payload.append(contentsOf: $0) }
        payload.append(spreadingFactor)
        payload.append(codingRate)

        let frame = ProtocolFrame(code: CommandCode.setRadioParams.rawValue, payload: payload)
        _ = try await sendCommand(frame, expectingResponse: ResponseCode.ok.rawValue)
    }

    /// CMD_SET_RADIO_TX_POWER (12): Set TX power in dBm
    public func setRadioTxPower(_ power: Int8) async throws {
        var payload = Data()
        payload.append(UInt8(bitPattern: power))

        let frame = ProtocolFrame(code: CommandCode.setRadioTxPower.rawValue, payload: payload)
        _ = try await sendCommand(frame, expectingResponse: ResponseCode.ok.rawValue)
    }

    /// CMD_GET_BATT_AND_STORAGE (20): Get battery and storage stats
    public func getBatteryAndStorage() async throws -> BatteryAndStorage {
        let frame = ProtocolFrame(code: CommandCode.getBatteryAndStorage.rawValue)
        let response = try await sendCommand(frame, expectingResponse: ResponseCode.batteryAndStorage.rawValue)
        return try BatteryAndStorage.decode(from: response.payload)
    }
}

public struct BatteryAndStorage: Sendable {
    public let batteryMillivolts: UInt16
    public let storageUsedKB: UInt32
    public let storageTotalKB: UInt32

    public static func decode(from data: Data) throws -> BatteryAndStorage {
        guard data.count >= 10 else {
            throw ProtocolError.invalidPayload
        }

        let batteryMv = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt16.self) }
        let usedKB = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 2, as: UInt32.self) }
        let totalKB = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 6, as: UInt32.self) }

        return BatteryAndStorage(
            batteryMillivolts: batteryMv,
            storageUsedKB: usedKB,
            storageTotalKB: totalKB
        )
    }

    public var batteryVoltage: Double {
        Double(batteryMillivolts) / 1000.0
    }

    public var storagePercentUsed: Double {
        guard storageTotalKB > 0 else { return 0 }
        return (Double(storageUsedKB) / Double(storageTotalKB)) * 100
    }
}
