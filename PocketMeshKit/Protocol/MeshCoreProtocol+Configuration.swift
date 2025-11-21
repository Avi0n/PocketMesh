import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "Configuration")

public extension MeshCoreProtocol {
    /// CMD_SET_RADIO_PARAMS (11): Set radio parameters
    func setRadioParameters(
        frequency: UInt32,
        bandwidth: UInt32,
        spreadingFactor: UInt8,
        codingRate: UInt8,
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
    func setRadioTxPower(_ power: Int8) async throws {
        var payload = Data()
        payload.append(UInt8(bitPattern: power))

        let frame = ProtocolFrame(code: CommandCode.setRadioTxPower.rawValue, payload: payload)
        _ = try await sendCommand(frame, expectingResponse: ResponseCode.ok.rawValue)
    }

    /// CMD_GET_BATT_AND_STORAGE (20): Get battery and storage stats
    func getBatteryAndStorage() async throws -> BatteryAndStorage {
        let frame = ProtocolFrame(code: CommandCode.getBatteryAndStorage.rawValue)
        let response = try await sendCommand(frame, expectingResponse: ResponseCode.batteryAndStorage.rawValue)
        return try BatteryAndStorage.decode(from: response.payload)
    }

    // MARK: - Multi-ACK Configuration

    /// CMD_GET_MULTI_ACKS (24): Get current multi-ACK mode status
    func getMultiAcks() async throws -> Bool {
        let frame = ProtocolFrame(code: CommandCode.getMultiAcks.rawValue)
        let response = try await sendCommand(frame, expectingResponse: ResponseCode.multiAcksStatus.rawValue)

        guard response.payload.count >= 1 else {
            throw ProtocolError.invalidPayload
        }

        return response.payload[0] != 0
    }

    // MARK: - Device Time Management

    /// CMD_GET_DEVICE_TIME (5): Get current device time
    func getDeviceTime() async throws -> Date {
        let frame = ProtocolFrame(code: CommandCode.getDeviceTime.rawValue, payload: Data())
        let response = try await sendCommand(frame, expectingResponse: ResponseCode.currentTime.rawValue)

        guard response.payload.count >= 4 else {
            throw ProtocolError.invalidPayload
        }

        let timestamp = response.payload.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self)
        }

        let deviceTime = Date(timeIntervalSince1970: TimeInterval(timestamp))
        logger.info("Device time retrieved: \(deviceTime)")

        return deviceTime
    }

    /// CMD_SET_DEVICE_TIME (6): Synchronize device time
    func setDeviceTime(_ date: Date) async throws {
        var payload = Data()
        let timestamp = UInt32(date.timeIntervalSince1970)
        withUnsafeBytes(of: timestamp.littleEndian) { payload.append(contentsOf: $0) }

        let frame = ProtocolFrame(code: CommandCode.setDeviceTime.rawValue, payload: payload)
        _ = try await sendCommand(frame, expectingResponse: ResponseCode.ok.rawValue)

        logger.info("Device time synchronized to: \(date)")
    }

    /// Convenience: Sync device to current time
    func syncDeviceTime() async throws {
        try await setDeviceTime(Date())
        logger.info("Device time synchronized to current iOS time")
    }

    // MARK: - Custom Variables

    /// CMD_GET_CUSTOM_VARS (40): Retrieve all custom variables from device
    func getCustomVariables() async throws -> CustomVariables {
        let frame = ProtocolFrame(code: CommandCode.getCustomVars.rawValue)
        let response = try await sendCommand(frame, expectingResponse: ResponseCode.customVars.rawValue)

        return try CustomVariables.decode(from: response.payload)
    }

    /// CMD_SET_CUSTOM_VAR (41): Set a custom variable on the device
    /// - Parameters:
    ///   - key: Variable name (UTF-8 string)
    ///   - value: Variable value (UTF-8 string)
    func setCustomVariable(key: String, value: String) async throws {
        // Validate input
        guard !key.isEmpty, key.utf8.count <= 64 else {
            throw ProtocolError.invalidPayload
        }
        guard value.utf8.count <= 256 else {
            throw ProtocolError.invalidPayload
        }

        // Build payload: key + ":" + value (UTF-8 encoded)
        guard let keyData = key.data(using: .utf8),
              let valueData = value.data(using: .utf8),
              let colonData = ":".data(using: .utf8)
        else {
            throw ProtocolError.invalidPayload
        }

        var payload = Data()
        payload.append(keyData)
        payload.append(colonData)
        payload.append(valueData)

        let frame = ProtocolFrame(code: CommandCode.setCustomVar.rawValue, payload: payload)
        _ = try await sendCommand(frame, expectingResponse: ResponseCode.ok.rawValue)

        logger.info("Custom variable set: \(key) = \(value)")
    }

    /// Convenience: Set multiple custom variables
    func setCustomVariables(_ variables: [String: String]) async throws {
        for (key, value) in variables {
            try await setCustomVariable(key: key, value: value)
        }
        logger.info("Set \(variables.count) custom variables")
    }

    /// Convenience: Clear a custom variable by setting it to empty string
    func clearCustomVariable(key: String) async throws {
        try await setCustomVariable(key: key, value: "")
        logger.info("Custom variable cleared: \(key)")
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
            storageTotalKB: totalKB,
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

/// Custom variables container for parsing and managing device custom variables
public struct CustomVariables: Sendable {
    public let variables: [String: String]

    public init(variables: [String: String] = [:]) {
        self.variables = variables
    }

    /// Decode custom variables from response payload
    /// Expected format: key1=value1\0key2=value2\0... (null-terminated pairs)
    static func decode(from data: Data) throws -> CustomVariables {
        guard !data.isEmpty else {
            return CustomVariables()
        }

        var variables: [String: String] = [:]
        var currentPair = Data()

        // Process all bytes, looking for null terminators
        for byte in data {
            if byte == 0 {
                // Null terminator - process the current pair
                if !currentPair.isEmpty {
                    let pairString = String(data: currentPair, encoding: .utf8) ?? ""
                    let parts = pairString.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        let key = String(parts[0])
                        let value = String(parts[1])
                        variables[key] = value
                    }
                    currentPair.removeAll()
                }
            } else {
                currentPair.append(byte)
            }
        }

        // Process the last pair if not null-terminated
        if !currentPair.isEmpty {
            let pairString = String(data: currentPair, encoding: .utf8) ?? ""
            let parts = pairString.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0])
                let value = String(parts[1])
                variables[key] = value
            }
        }

        return CustomVariables(variables: variables)
    }

    /// Get a variable value by key
    public func get(_ key: String) -> String? {
        variables[key]
    }

    /// Get a variable value with default
    public func get(_ key: String, default: String) -> String {
        variables[key] ?? `default`
    }

    /// Check if a variable exists
    public func contains(_ key: String) -> Bool {
        variables.keys.contains(key)
    }

    /// Get all variable keys
    public var keys: [String] {
        Array(variables.keys)
    }

    /// Get all variable values
    public var values: [String] {
        Array(variables.values)
    }

    /// Count of variables
    public var count: Int {
        variables.count
    }

    /// Check if empty
    public var isEmpty: Bool {
        variables.isEmpty
    }
}
