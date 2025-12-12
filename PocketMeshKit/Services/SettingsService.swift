import Foundation

/// Errors for settings operations
public enum SettingsServiceError: Error, LocalizedError, Sendable {
    case notConnected
    case sendFailed
    case invalidResponse
    case protocolError(ProtocolError)
    case verificationFailed(expected: String, actual: String)
    case connectionError  // Specific error for ResponseCode.error (0x01)

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Device not connected"
        case .sendFailed: return "Failed to send command"
        case .invalidResponse: return "Invalid response from device"
        case .protocolError(let error): return "Protocol error: \(error)"
        case .verificationFailed(let expected, let actual):
            return "Setting was not saved. Expected '\(expected)' but device reports '\(actual)'."
        case .connectionError:
            return "Failed to save setting. Please ensure device is connected and try again."
        }
    }

    /// Whether this error suggests a connection issue that might be resolved by retrying
    public var isRetryable: Bool {
        switch self {
        case .connectionError, .sendFailed, .notConnected:
            return true
        default:
            return false
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

    // MARK: - Device Info

    /// Fetch battery and storage information from device
    /// - Returns: BatteryAndStorage struct with current values
    /// - Throws: SettingsServiceError if not connected or communication fails
    public func getBatteryAndStorage() async throws -> BatteryAndStorage {
        guard await bleTransport.connectionState == .ready else {
            throw SettingsServiceError.notConnected
        }

        let command = FrameCodec.encodeGetBatteryAndStorage()
        guard let response = try await bleTransport.send(command),
              response.first == ResponseCode.batteryAndStorage.rawValue else {
            throw SettingsServiceError.invalidResponse
        }

        do {
            return try FrameCodec.decodeBatteryAndStorage(from: response)
        } catch let error as ProtocolError {
            throw SettingsServiceError.protocolError(error)
        }
    }

    // MARK: - Verified Settings Methods

    /// Read current device state for verification
    /// Returns (DeviceInfo, SelfInfo) tuple
    private func readDeviceInfo() async throws -> (DeviceInfo, SelfInfo) {
        guard await bleTransport.connectionState == .ready else {
            throw SettingsServiceError.notConnected
        }

        // Send device query
        let queryData = FrameCodec.encodeDeviceQuery(protocolVersion: 8)
        guard let queryResponse = try await bleTransport.send(queryData),
              queryResponse.first == ResponseCode.deviceInfo.rawValue else {
            throw SettingsServiceError.invalidResponse
        }
        let deviceInfo = try FrameCodec.decodeDeviceInfo(from: queryResponse)

        // Send app start to get selfInfo
        let appStartData = FrameCodec.encodeAppStart(appName: "PocketMesh")
        guard let selfResponse = try await bleTransport.send(appStartData),
              selfResponse.first == ResponseCode.selfInfo.rawValue else {
            throw SettingsServiceError.invalidResponse
        }
        let selfInfo = try FrameCodec.decodeSelfInfo(from: selfResponse)

        return (deviceInfo, selfInfo)
    }

    /// Set node name with verification
    /// Returns the verified device info for UI update
    public func setNodeNameVerified(_ name: String) async throws -> (DeviceInfo, SelfInfo) {
        // Send the command
        try await setNodeName(name)

        // Read back and verify
        let (deviceInfo, selfInfo) = try await readDeviceInfo()

        guard selfInfo.nodeName == name else {
            throw SettingsServiceError.verificationFailed(
                expected: name,
                actual: selfInfo.nodeName
            )
        }

        return (deviceInfo, selfInfo)
    }

    /// Set location with verification
    public func setLocationVerified(latitude: Double, longitude: Double) async throws -> (DeviceInfo, SelfInfo) {
        try await setLocation(latitude: latitude, longitude: longitude)

        let (deviceInfo, selfInfo) = try await readDeviceInfo()

        // Location is stored as scaled integers, allow small floating point tolerance
        let tolerance = 0.000002  // ~0.2 meters at equator
        guard abs(selfInfo.latitude - latitude) < tolerance &&
              abs(selfInfo.longitude - longitude) < tolerance else {
            throw SettingsServiceError.verificationFailed(
                expected: "(\(latitude), \(longitude))",
                actual: "(\(selfInfo.latitude), \(selfInfo.longitude))"
            )
        }

        return (deviceInfo, selfInfo)
    }

    /// Set radio parameters with verification
    public func setRadioParamsVerified(
        frequencyKHz: UInt32,
        bandwidthKHz: UInt32,
        spreadingFactor: UInt8,
        codingRate: UInt8
    ) async throws -> (DeviceInfo, SelfInfo) {
        try await setRadioParams(
            frequencyKHz: frequencyKHz,
            bandwidthKHz: bandwidthKHz,
            spreadingFactor: spreadingFactor,
            codingRate: codingRate
        )

        let (deviceInfo, selfInfo) = try await readDeviceInfo()

        guard selfInfo.frequency == frequencyKHz &&
              selfInfo.bandwidth == bandwidthKHz &&
              selfInfo.spreadingFactor == spreadingFactor &&
              selfInfo.codingRate == codingRate else {
            throw SettingsServiceError.verificationFailed(
                expected: "freq=\(frequencyKHz), bw=\(bandwidthKHz), sf=\(spreadingFactor), cr=\(codingRate)",
                actual: "freq=\(selfInfo.frequency), bw=\(selfInfo.bandwidth), sf=\(selfInfo.spreadingFactor), cr=\(selfInfo.codingRate)"
            )
        }

        return (deviceInfo, selfInfo)
    }

    /// Apply radio preset with verification
    public func applyRadioPresetVerified(_ preset: RadioPreset) async throws -> (DeviceInfo, SelfInfo) {
        try await setRadioParamsVerified(
            frequencyKHz: preset.frequencyKHz,
            bandwidthKHz: preset.bandwidthHz,
            spreadingFactor: preset.spreadingFactor,
            codingRate: preset.codingRate
        )
    }

    /// Set TX power with verification
    public func setTxPowerVerified(_ power: UInt8) async throws -> (DeviceInfo, SelfInfo) {
        try await setTxPower(power)

        let (deviceInfo, selfInfo) = try await readDeviceInfo()

        guard selfInfo.txPower == power else {
            throw SettingsServiceError.verificationFailed(
                expected: "\(power)",
                actual: "\(selfInfo.txPower)"
            )
        }

        return (deviceInfo, selfInfo)
    }

    /// Set other params with verification
    public func setOtherParamsVerified(
        autoAddContacts: Bool,
        telemetryModes: TelemetryModes,
        shareLocationPublicly: Bool,
        multiAcks: Bool
    ) async throws -> (DeviceInfo, SelfInfo) {
        try await setOtherParams(
            autoAddContacts: autoAddContacts,
            telemetryModes: telemetryModes,
            shareLocationPublicly: shareLocationPublicly,
            multiAcks: multiAcks
        )

        let (deviceInfo, selfInfo) = try await readDeviceInfo()

        // manualAddContacts is inverted (0 = auto-add enabled)
        let expectedManualAdd: UInt8 = autoAddContacts ? 0 : 1
        let expectedPolicy: AdvertLocationPolicy = shareLocationPublicly ? .share : .none
        let expectedMultiAcks: UInt8 = multiAcks ? 1 : 0

        guard selfInfo.manualAddContacts == expectedManualAdd &&
              selfInfo.telemetryModes == telemetryModes.packed &&
              selfInfo.advertLocationPolicy == expectedPolicy &&
              selfInfo.multiAcks == expectedMultiAcks else {
            throw SettingsServiceError.verificationFailed(
                expected: "autoAdd=\(autoAddContacts), telemetry=\(telemetryModes.packed), shareLocation=\(shareLocationPublicly), multiAcks=\(multiAcks)",
                actual: "autoAdd=\(selfInfo.manualAddContacts == 0), telemetry=\(selfInfo.telemetryModes), shareLocation=\(selfInfo.advertLocationPolicy == .share), multiAcks=\(selfInfo.multiAcks > 0)"
            )
        }

        return (deviceInfo, selfInfo)
    }

    // Note: BLE PIN changes are NOT verified because the PIN is only written to RAM
    // until the device reboots. Use setBlePin() directly followed by reboot().

    // MARK: - Helpers

    private func validateOkResponse(_ response: Data) throws {
        if response.first == ResponseCode.error.rawValue {
            if response.count > 1, let error = ProtocolError(rawValue: response[1]) {
                throw SettingsServiceError.protocolError(error)
            }
            // ResponseCode.error without specific code suggests connection/state issue
            throw SettingsServiceError.connectionError
        }

        guard response.first == ResponseCode.ok.rawValue else {
            throw SettingsServiceError.invalidResponse
        }
    }
}
