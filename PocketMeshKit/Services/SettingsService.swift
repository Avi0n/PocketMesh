import Foundation

/// Errors for settings operations
public enum SettingsServiceError: Error, LocalizedError, Sendable {
    case notConnected
    case sendFailed
    case invalidResponse
    case protocolError(ProtocolError)

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Device not connected"
        case .sendFailed: return "Failed to send command"
        case .invalidResponse: return "Invalid response from device"
        case .protocolError(let error): return "Protocol error: \(error)"
        }
    }
}

/// Service for managing device settings via BLE
public actor SettingsService {
    private let bleTransport: any BLETransport

    public init(bleTransport: any BLETransport) {
        self.bleTransport = bleTransport
    }

    // MARK: - Radio Settings

    /// Apply a radio preset to the device
    public func applyRadioPreset(_ preset: RadioPreset) async throws {
        try await setRadioParams(
            frequencyKHz: preset.frequencyKHz,
            bandwidthKHz: preset.bandwidthHz,
            spreadingFactor: preset.spreadingFactor,
            codingRate: preset.codingRate
        )
    }

    /// Set radio parameters manually
    public func setRadioParams(
        frequencyKHz: UInt32,
        bandwidthKHz: UInt32,
        spreadingFactor: UInt8,
        codingRate: UInt8
    ) async throws {
        guard await bleTransport.connectionState == .ready else {
            throw SettingsServiceError.notConnected
        }

        let command = FrameCodec.encodeSetRadioParams(
            frequencyKHz: frequencyKHz,
            bandwidthKHz: bandwidthKHz,
            spreadingFactor: spreadingFactor,
            codingRate: codingRate
        )

        guard let response = try await bleTransport.send(command) else {
            throw SettingsServiceError.sendFailed
        }

        try validateOkResponse(response)
    }

    /// Set transmit power
    public func setTxPower(_ power: UInt8) async throws {
        guard await bleTransport.connectionState == .ready else {
            throw SettingsServiceError.notConnected
        }

        let command = FrameCodec.encodeSetRadioTxPower(power)
        guard let response = try await bleTransport.send(command) else {
            throw SettingsServiceError.sendFailed
        }

        try validateOkResponse(response)
    }

    // MARK: - Node Settings

    /// Set the publicly visible node name
    public func setNodeName(_ name: String) async throws {
        guard await bleTransport.connectionState == .ready else {
            throw SettingsServiceError.notConnected
        }

        let command = FrameCodec.encodeSetAdvertName(name)
        guard let response = try await bleTransport.send(command) else {
            throw SettingsServiceError.sendFailed
        }

        try validateOkResponse(response)
    }

    /// Set node location (latitude/longitude in degrees)
    public func setLocation(latitude: Double, longitude: Double) async throws {
        guard await bleTransport.connectionState == .ready else {
            throw SettingsServiceError.notConnected
        }

        // Convert to protocol format (scaled by 1e6)
        let latInt = Int32(latitude * 1_000_000)
        let lonInt = Int32(longitude * 1_000_000)

        let command = FrameCodec.encodeSetAdvertLatLon(latitude: latInt, longitude: lonInt)
        guard let response = try await bleTransport.send(command) else {
            throw SettingsServiceError.sendFailed
        }

        try validateOkResponse(response)
    }

    // MARK: - Bluetooth Settings

    /// Set BLE PIN (0 = disabled/random, 100000-999999 = fixed PIN)
    public func setBlePin(_ pin: UInt32) async throws {
        guard await bleTransport.connectionState == .ready else {
            throw SettingsServiceError.notConnected
        }

        let command = FrameCodec.encodeSetDevicePin(pin)
        guard let response = try await bleTransport.send(command) else {
            throw SettingsServiceError.sendFailed
        }

        try validateOkResponse(response)
    }

    // MARK: - Other Settings

    /// Set other device parameters (contacts, telemetry, location policy)
    public func setOtherParams(
        autoAddContacts: Bool,
        telemetryModes: TelemetryModes,
        shareLocationPublicly: Bool,
        multiAcks: Bool
    ) async throws {
        guard await bleTransport.connectionState == .ready else {
            throw SettingsServiceError.notConnected
        }

        // Note: manualAddContacts is inverted - true means auto-add DISABLED
        let manualAdd: UInt8 = autoAddContacts ? 0 : 1
        let advertPolicy: UInt8 = shareLocationPublicly ? 1 : 0
        let multiAckValue: UInt8 = multiAcks ? 1 : 0

        let command = FrameCodec.encodeSetOtherParams(
            manualAddContacts: manualAdd,
            telemetryModes: telemetryModes.packed,
            advertLocationPolicy: advertPolicy,
            multiAcks: multiAckValue
        )

        guard let response = try await bleTransport.send(command) else {
            throw SettingsServiceError.sendFailed
        }

        try validateOkResponse(response)
    }

    // MARK: - Factory Reset

    /// Perform factory reset on device
    public func factoryReset() async throws {
        guard await bleTransport.connectionState == .ready else {
            throw SettingsServiceError.notConnected
        }

        let command = FrameCodec.encodeFactoryReset()
        guard let response = try await bleTransport.send(command) else {
            throw SettingsServiceError.sendFailed
        }

        try validateOkResponse(response)
    }

    /// Reboot the device
    public func reboot() async throws {
        guard await bleTransport.connectionState == .ready else {
            throw SettingsServiceError.notConnected
        }

        let command = FrameCodec.encodeReboot()
        // Reboot may not respond, so don't require response
        _ = try await bleTransport.send(command)
    }

    // MARK: - Helpers

    private func validateOkResponse(_ response: Data) throws {
        if response.first == ResponseCode.error.rawValue {
            if response.count > 1, let error = ProtocolError(rawValue: response[1]) {
                throw SettingsServiceError.protocolError(error)
            }
            throw SettingsServiceError.invalidResponse
        }

        guard response.first == ResponseCode.ok.rawValue else {
            throw SettingsServiceError.invalidResponse
        }
    }
}
