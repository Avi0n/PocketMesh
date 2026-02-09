import Foundation
import MeshCore
import os

// MARK: - Settings Service Errors

public enum SettingsServiceError: Error, LocalizedError, Sendable {
    case notConnected
    case sendFailed
    case invalidResponse
    case sessionError(MeshCoreError)
    case verificationFailed(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Device not connected"
        case .sendFailed: return "Failed to send command"
        case .invalidResponse: return "Invalid response from device"
        case .sessionError(let error): return "Session error: \(error.localizedDescription)"
        case .verificationFailed(let expected, let actual):
            return "Setting was not saved. Expected '\(expected)' but device reports '\(actual)'."
        }
    }

    /// Whether this error suggests a connection issue that might be resolved by retrying
    public var isRetryable: Bool {
        switch self {
        case .sendFailed, .notConnected:
            return true
        case .sessionError(let error):
            if case .timeout = error { return true }
            return false
        default:
            return false
        }
    }
}

// MARK: - Radio Preset

/// Geographic regions for radio preset filtering
public enum RadioRegion: String, CaseIterable, Sendable {
    case northAmerica = "North America"
    case europe = "Europe"
    case oceania = "Oceania"
    case asia = "Asia"

    /// Regions that should be shown for a given locale
    public static func regionsForLocale(_ locale: Locale = .current) -> [RadioRegion] {
        guard let regionCode = locale.region?.identifier else {
            return RadioRegion.allCases
        }

        switch regionCode {
        case "US", "CA":
            return [.northAmerica, .europe, .oceania, .asia]
        case "AU", "NZ":
            return [.oceania, .northAmerica, .europe, .asia]
        case "GB", "DE", "FR", "IT", "ES", "PT", "CH", "CZ", "IE", "NL", "BE", "AT":
            return [.europe, .northAmerica, .oceania, .asia]
        case "VN", "TH", "MY", "SG", "PH", "ID":
            return [.asia, .oceania, .europe, .northAmerica]
        default:
            return RadioRegion.allCases
        }
    }

    /// Short code for display in compact UI elements
    public var shortCode: String {
        switch self {
        case .northAmerica: return "NA"
        case .europe: return "EU"
        case .oceania: return "AU"
        case .asia: return "AS"
        }
    }
}

/// Radio configuration preset for common regional settings
public struct RadioPreset: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let region: RadioRegion
    public let frequencyMHz: Double
    public let bandwidthKHz: Double
    public let spreadingFactor: UInt8
    public let codingRate: UInt8

    /// Frequency in kHz for protocol encoding
    public var frequencyKHz: UInt32 {
        UInt32(frequencyMHz * 1000)
    }

    /// Bandwidth in Hz for protocol encoding
    public var bandwidthHz: UInt32 {
        UInt32(bandwidthKHz * 1000)
    }

    public init(
        id: String,
        name: String,
        region: RadioRegion,
        frequencyMHz: Double,
        bandwidthKHz: Double,
        spreadingFactor: UInt8,
        codingRate: UInt8
    ) {
        self.id = id
        self.name = name
        self.region = region
        self.frequencyMHz = frequencyMHz
        self.bandwidthKHz = bandwidthKHz
        self.spreadingFactor = spreadingFactor
        self.codingRate = codingRate
    }
}

/// Static collection of all available radio presets
public enum RadioPresets {
    public static let all: [RadioPreset] = [
        // Oceania
        RadioPreset(id: "au-915", name: "Australia", region: .oceania,
                    frequencyMHz: 915.800, bandwidthKHz: 250, spreadingFactor: 10, codingRate: 5),
        RadioPreset(id: "au-narrow", name: "Australia (Narrow)", region: .oceania,
                    frequencyMHz: 916.575, bandwidthKHz: 62.5, spreadingFactor: 7, codingRate: 8),
        RadioPreset(id: "au-sa-wa", name: "Australia SA, WA", region: .oceania,
                    frequencyMHz: 923.125, bandwidthKHz: 62.5, spreadingFactor: 8, codingRate: 8),
        RadioPreset(id: "au-qld", name: "Australia QLD", region: .oceania,
                    frequencyMHz: 923.125, bandwidthKHz: 62.5, spreadingFactor: 8, codingRate: 5),
        RadioPreset(id: "nz-lr", name: "New Zealand", region: .oceania,
                    frequencyMHz: 917.375, bandwidthKHz: 250, spreadingFactor: 11, codingRate: 5),
        RadioPreset(id: "nz-narrow", name: "New Zealand (Narrow)", region: .oceania,
                    frequencyMHz: 917.375, bandwidthKHz: 62.5, spreadingFactor: 7, codingRate: 5),

        // Europe
        RadioPreset(id: "eu-narrow", name: "EU/UK (Narrow)", region: .europe,
                    frequencyMHz: 869.618, bandwidthKHz: 62.5, spreadingFactor: 8, codingRate: 8),
        RadioPreset(id: "eu-lr", name: "EU/UK (Long Range)", region: .europe,
                    frequencyMHz: 869.525, bandwidthKHz: 250, spreadingFactor: 11, codingRate: 5),
        RadioPreset(id: "eu-mr", name: "EU/UK (Medium Range)", region: .europe,
                    frequencyMHz: 869.525, bandwidthKHz: 250, spreadingFactor: 10, codingRate: 5),
        RadioPreset(id: "cz-narrow", name: "Czech Republic (Narrow)", region: .europe,
                    frequencyMHz: 869.525, bandwidthKHz: 62.5, spreadingFactor: 7, codingRate: 5),
        RadioPreset(id: "eu-433-lr", name: "EU 433MHz (Long Range)", region: .europe,
                    frequencyMHz: 433.650, bandwidthKHz: 250, spreadingFactor: 11, codingRate: 5),
        RadioPreset(id: "pt-433", name: "Portugal 433", region: .europe,
                    frequencyMHz: 433.375, bandwidthKHz: 62.5, spreadingFactor: 9, codingRate: 6),
        RadioPreset(id: "pt-868", name: "Portugal 868", region: .europe,
                    frequencyMHz: 869.618, bandwidthKHz: 62.5, spreadingFactor: 7, codingRate: 6),
        RadioPreset(id: "ch", name: "Switzerland", region: .europe,
                    frequencyMHz: 869.618, bandwidthKHz: 62.5, spreadingFactor: 8, codingRate: 8),

        // North America
        RadioPreset(id: "us-ca", name: "USA/Canada", region: .northAmerica,
                    frequencyMHz: 910.525, bandwidthKHz: 62.5, spreadingFactor: 7, codingRate: 5),
        RadioPreset(id: "wcmesh", name: "WCMesh (SoCal)", region: .northAmerica,
                    frequencyMHz: 927.875, bandwidthKHz: 62.5, spreadingFactor: 7, codingRate: 5),

        // Asia
        RadioPreset(id: "vn", name: "Vietnam", region: .asia,
                    frequencyMHz: 920.250, bandwidthKHz: 250, spreadingFactor: 11, codingRate: 5),
    ]

    /// Get presets filtered and sorted by user's locale
    public static func presetsForLocale(_ locale: Locale = .current) -> [RadioPreset] {
        let preferredRegions = RadioRegion.regionsForLocale(locale)

        return all.sorted { a, b in
            let aIndex = preferredRegions.firstIndex(of: a.region) ?? preferredRegions.count
            let bIndex = preferredRegions.firstIndex(of: b.region) ?? preferredRegions.count
            if aIndex != bIndex {
                return aIndex < bIndex
            }
            return a.name < b.name
        }
    }

    /// Find preset matching current device settings (approximate match)
    public static func matchingPreset(
        frequencyKHz: UInt32,
        bandwidthKHz: UInt32,
        spreadingFactor: UInt8,
        codingRate: UInt8
    ) -> RadioPreset? {
        let freqMHz = Double(frequencyKHz) / 1000.0
        let bwKHz = Double(bandwidthKHz) / 1000.0

        return all.first { preset in
            abs(preset.frequencyMHz - freqMHz) < 0.1 &&
            abs(preset.bandwidthKHz - bwKHz) < 1.0 &&
            preset.spreadingFactor == spreadingFactor &&
            preset.codingRate == codingRate
        }
    }
}

// MARK: - Telemetry Modes

/// Packed telemetry mode configuration
public struct TelemetryModes: Sendable, Equatable {
    public var base: UInt8
    public var location: UInt8
    public var environment: UInt8

    public init(base: UInt8 = 0, location: UInt8 = 0, environment: UInt8 = 0) {
        self.base = base & 0b11
        self.location = location & 0b11
        self.environment = environment & 0b11
    }

    /// Packed value for protocol encoding
    public var packed: UInt8 {
        (environment << 4) | (location << 2) | base
    }

    public init(packed: UInt8) {
        self.base = packed & 0b11
        self.location = (packed >> 2) & 0b11
        self.environment = (packed >> 4) & 0b11
    }
}

// MARK: - Settings Service

/// Service for managing device settings via MeshCore session.
/// Handles radio configuration, node settings, Bluetooth settings, and device info.
public actor SettingsService {
    private let session: MeshCoreSession
    private let logger = PersistentLogger(subsystem: "com.pocketmesh", category: "SettingsService")

    /// Callback invoked when device settings are successfully changed.
    /// Used to update ConnectionManager.connectedDevice for UI refresh.
    private var onDeviceUpdated: (@Sendable (MeshCore.SelfInfo) async -> Void)?

    /// Callback invoked when auto-add config is successfully changed.
    /// Used to update ConnectionManager.connectedDevice.autoAddConfig for UI refresh.
    private var onAutoAddConfigUpdated: (@Sendable (UInt8) async -> Void)?

    public init(session: MeshCoreSession) {
        self.session = session
    }

    /// Sets the callback for device updates after settings changes.
    public func setDeviceUpdateCallback(
        _ callback: @escaping @Sendable (MeshCore.SelfInfo) async -> Void
    ) {
        onDeviceUpdated = callback
    }

    /// Sets the callback for auto-add config updates.
    public func setAutoAddConfigCallback(
        _ callback: @escaping @Sendable (UInt8) async -> Void
    ) {
        onAutoAddConfigUpdated = callback
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
        do {
            try await session.setRadio(
                frequency: Double(frequencyKHz) / 1000.0,
                bandwidth: Double(bandwidthKHz) / 1000.0,
                spreadingFactor: spreadingFactor,
                codingRate: codingRate
            )
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }

    /// Set transmit power
    public func setTxPower(_ power: UInt8) async throws {
        do {
            try await session.setTxPower(Int(power))
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }

    // MARK: - Node Settings

    /// Set the publicly visible node name
    public func setNodeName(_ name: String) async throws {
        let truncated = name.utf8Prefix(maxBytes: ProtocolLimits.maxUsableNameBytes)
        do {
            try await session.setName(truncated)
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }

    /// Set node location (latitude/longitude in degrees)
    public func setLocation(latitude: Double, longitude: Double) async throws {
        do {
            try await session.setCoordinates(latitude: latitude, longitude: longitude)
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }

    // MARK: - Bluetooth Settings

    /// Set BLE PIN (0 = disabled/random, 100000-999999 = fixed PIN)
    public func setBlePin(_ pin: UInt32) async throws {
        do {
            try await session.setDevicePin(pin)
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }

    // MARK: - Other Settings

    /// Set other device parameters (contacts, telemetry, location policy)
    public func setOtherParams(
        autoAddContacts: Bool,
        telemetryModes: TelemetryModes,
        shareLocationPublicly: Bool,
        multiAcks: UInt8
    ) async throws {
        do {
            try await session.setOtherParams(
                manualAddContacts: !autoAddContacts,
                telemetryModeEnvironment: telemetryModes.environment,
                telemetryModeLocation: telemetryModes.location,
                telemetryModeBase: telemetryModes.base,
                advertisementLocationPolicy: shareLocationPublicly ? 1 : 0,
                multiAcks: multiAcks
            )
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }

    // MARK: - Factory Reset

    /// Perform factory reset on device
    public func factoryReset() async throws {
        do {
            try await session.factoryReset()
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }

    /// Reboot the device
    public func reboot() async throws {
        do {
            try await session.reboot()
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }

    // MARK: - Device Info

    /// Fetch battery and storage information from device
    /// - Returns: BatteryInfo with current values
    /// - Throws: SettingsServiceError if not connected or communication fails
    public func getBattery() async throws -> BatteryInfo {
        do {
            return try await session.getBattery()
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }


    /// Query device capabilities
    public func queryDevice() async throws -> DeviceCapabilities {
        do {
            return try await session.queryDevice()
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }

    /// Get self info by sending appStart
    public func getSelfInfo() async throws -> MeshCore.SelfInfo {
        do {
            return try await session.sendAppStart()
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }

    // MARK: - Verified Settings Methods

    /// Set node name with verification
    /// Returns the verified self info for UI update
    public func setNodeNameVerified(_ name: String) async throws -> MeshCore.SelfInfo {
        let truncated = name.utf8Prefix(maxBytes: ProtocolLimits.maxUsableNameBytes)
        try await setNodeName(truncated)

        let selfInfo = try await getSelfInfo()

        guard selfInfo.name == truncated else {
            throw SettingsServiceError.verificationFailed(
                expected: truncated,
                actual: selfInfo.name
            )
        }

        await onDeviceUpdated?(selfInfo)
        return selfInfo
    }

    /// Set location with verification
    public func setLocationVerified(latitude: Double, longitude: Double) async throws -> MeshCore.SelfInfo {
        // Calculate the scaled values we're actually sending
        let scaledLatSent = Int32(latitude * 1_000_000)
        let scaledLonSent = Int32(longitude * 1_000_000)

        try await setLocation(latitude: latitude, longitude: longitude)

        // Read back and compare at scaled integer level for precise diagnostics
        let selfInfo = try await getSelfInfo()
        let scaledLatReceived = Int32(selfInfo.latitude * 1_000_000)
        let scaledLonReceived = Int32(selfInfo.longitude * 1_000_000)

        let latDiff = abs(scaledLatSent - scaledLatReceived)
        let lonDiff = abs(scaledLonSent - scaledLonReceived)

        // Tolerance of 2 scaled units (~0.2m) handles floating-point conversion
        let tolerance: Int32 = 2

        guard latDiff <= tolerance && lonDiff <= tolerance else {
            logger.error("[Location] Verification failed - sent: (\(scaledLatSent), \(scaledLonSent)), received: (\(scaledLatReceived), \(scaledLonReceived)), diff: (lat=\(latDiff), lon=\(lonDiff))")

            let expectedLat = Double(scaledLatSent) / 1_000_000
            let expectedLon = Double(scaledLonSent) / 1_000_000
            throw SettingsServiceError.verificationFailed(
                expected: "(\(expectedLat), \(expectedLon))",
                actual: "(\(selfInfo.latitude), \(selfInfo.longitude))"
            )
        }

        await onDeviceUpdated?(selfInfo)
        return selfInfo
    }

    /// Set radio parameters with verification
    public func setRadioParamsVerified(
        frequencyKHz: UInt32,
        bandwidthKHz: UInt32,
        spreadingFactor: UInt8,
        codingRate: UInt8
    ) async throws -> MeshCore.SelfInfo {
        logger.info("[Radio] Sending params: freq=\(frequencyKHz)kHz, bw=\(bandwidthKHz)Hz, sf=\(spreadingFactor), cr=\(codingRate)")

        try await setRadioParams(
            frequencyKHz: frequencyKHz,
            bandwidthKHz: bandwidthKHz,
            spreadingFactor: spreadingFactor,
            codingRate: codingRate
        )

        let selfInfo = try await getSelfInfo()

        let expectedFreqMHz = Double(frequencyKHz) / 1000.0
        let expectedBwMHz = Double(bandwidthKHz) / 1000.0

        guard abs(selfInfo.radioFrequency - expectedFreqMHz) < 0.001 &&
              abs(selfInfo.radioBandwidth - expectedBwMHz) < 0.001 &&
              selfInfo.radioSpreadingFactor == spreadingFactor &&
              selfInfo.radioCodingRate == codingRate else {
            logger.warning("[Radio] Verification failed - expected: freq=\(expectedFreqMHz)MHz, bw=\(expectedBwMHz)kHz, sf=\(spreadingFactor), cr=\(codingRate); device reports: freq=\(selfInfo.radioFrequency)MHz, bw=\(selfInfo.radioBandwidth)kHz, sf=\(selfInfo.radioSpreadingFactor), cr=\(selfInfo.radioCodingRate)")
            throw SettingsServiceError.verificationFailed(
                expected: "freq=\(frequencyKHz), bw=\(bandwidthKHz), sf=\(spreadingFactor), cr=\(codingRate)",
                actual: "freq=\(selfInfo.radioFrequency), bw=\(selfInfo.radioBandwidth), sf=\(selfInfo.radioSpreadingFactor), cr=\(selfInfo.radioCodingRate)"
            )
        }

        logger.info("[Radio] Params verified successfully")
        await onDeviceUpdated?(selfInfo)
        return selfInfo
    }

    /// Apply radio preset with verification
    public func applyRadioPresetVerified(_ preset: RadioPreset) async throws -> MeshCore.SelfInfo {
        logger.info("[Radio] Applying preset: \(preset.name) (\(preset.id))")
        return try await setRadioParamsVerified(
            frequencyKHz: preset.frequencyKHz,
            bandwidthKHz: preset.bandwidthHz,
            spreadingFactor: preset.spreadingFactor,
            codingRate: preset.codingRate
        )
    }

    /// Set TX power with verification
    public func setTxPowerVerified(_ power: UInt8) async throws -> MeshCore.SelfInfo {
        logger.info("[Radio] Sending TX power: \(power)dBm")

        try await setTxPower(power)

        let selfInfo = try await getSelfInfo()

        guard selfInfo.txPower == power else {
            logger.warning("[Radio] TX power verification failed - expected: \(power)dBm, device reports: \(selfInfo.txPower)dBm")
            throw SettingsServiceError.verificationFailed(
                expected: "\(power)",
                actual: "\(selfInfo.txPower)"
            )
        }

        logger.info("[Radio] TX power verified: \(power)dBm")
        await onDeviceUpdated?(selfInfo)
        return selfInfo
    }

    /// Set other params with verification
    public func setOtherParamsVerified(
        autoAddContacts: Bool,
        telemetryModes: TelemetryModes,
        shareLocationPublicly: Bool,
        multiAcks: UInt8
    ) async throws -> MeshCore.SelfInfo {
        try await setOtherParams(
            autoAddContacts: autoAddContacts,
            telemetryModes: telemetryModes,
            shareLocationPublicly: shareLocationPublicly,
            multiAcks: multiAcks
        )

        let selfInfo = try await getSelfInfo()

        // manualAddContacts is inverted (false = auto-add enabled)
        guard selfInfo.manualAddContacts != autoAddContacts else {
            throw SettingsServiceError.verificationFailed(
                expected: "autoAdd=\(autoAddContacts)",
                actual: "autoAdd=\(!selfInfo.manualAddContacts)"
            )
        }

        await onDeviceUpdated?(selfInfo)
        return selfInfo
    }

    // MARK: - Auto-Add Config

    /// Get auto-add configuration from device
    public func getAutoAddConfig() async throws -> UInt8 {
        do {
            return try await session.getAutoAddConfig()
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }

    /// Refresh auto-add config from device (for initial load)
    /// Fetches current value and triggers callback to update connected device
    public func refreshAutoAddConfig() async throws {
        let config = try await getAutoAddConfig()
        await onAutoAddConfigUpdated?(config)
    }

    /// Refresh device info from the device and notify observers.
    /// Use this instead of `setLocationVerified` when the device already has correct coordinates (e.g. from its own GPS).
    public func refreshDeviceInfo() async throws {
        let selfInfo = try await getSelfInfo()
        await onDeviceUpdated?(selfInfo)
    }

    /// Set auto-add configuration on device
    public func setAutoAddConfig(_ config: UInt8) async throws {
        do {
            try await session.setAutoAddConfig(config)
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }

    /// Set auto-add configuration with verification
    public func setAutoAddConfigVerified(_ config: UInt8) async throws -> UInt8 {
        try await setAutoAddConfig(config)

        let actualConfig = try await getAutoAddConfig()

        guard actualConfig == config else {
            throw SettingsServiceError.verificationFailed(
                expected: "config=\(config)",
                actual: "config=\(actualConfig)"
            )
        }

        await onAutoAddConfigUpdated?(actualConfig)
        return actualConfig
    }

    // MARK: - Stats

    /// Get core statistics
    public func getStatsCore() async throws -> CoreStats {
        do {
            return try await session.getStatsCore()
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }

    /// Get radio statistics
    public func getStatsRadio() async throws -> RadioStats {
        do {
            return try await session.getStatsRadio()
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }

    /// Get packet statistics
    public func getStatsPackets() async throws -> PacketStats {
        do {
            return try await session.getStatsPackets()
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }

    // MARK: - Custom Variables

    /// Get custom variables from device
    public func getCustomVars() async throws -> [String: String] {
        do {
            return try await session.getCustomVars()
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }

    /// Set a custom variable on device
    public func setCustomVar(key: String, value: String) async throws {
        do {
            try await session.setCustomVar(key: key, value: value)
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }

    // MARK: - Private Key Management

    /// Export private key from device
    public func exportPrivateKey() async throws -> Data {
        do {
            return try await session.exportPrivateKey()
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }

    /// Import private key to device
    public func importPrivateKey(_ key: Data) async throws {
        do {
            try await session.importPrivateKey(key)
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }

    // MARK: - Signing

    /// Sign data using device's private key
    public func sign(_ data: Data) async throws -> Data {
        do {
            return try await session.sign(data)
        } catch let error as MeshCoreError {
            throw SettingsServiceError.sessionError(error)
        }
    }
}
