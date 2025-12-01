import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.mock", category: "RadioState")

// MARK: - Radio Configuration

/// Radio configuration state for MockBLE (different from protocol RadioConfiguration)
public struct MockRadioConfiguration: Sendable {
    public var frequency: UInt32 = 915000000  // 915MHz in Hz
    public var bandwidth: UInt32 = 125000      // 125kHz in Hz
    public var spreadingFactor: UInt8 = 7      // SF7
    public var codingRate: UInt8 = 5           // 4/5 coding rate (firmware: cr=5 means 4/5)
    public var txPower: Int8 = 20              // 20dBm
    public var batteryLevel: UInt8 = 100       // 100%
    public var storageUsed: UInt32 = 0         // bytes
    public var storageTotal: UInt32 = 1000000  // 1MB

    public init() {}
}

// MARK: - Contact Storage Models

/// MockContact - Internal storage model matching firmware ContactInfo
public struct MockContact: Sendable {
    let publicKey: Data // 32 bytes
    var name: String // Up to 32 chars
    var type: UInt8 // Contact type (0=none, 1=chat, 2=repeater, 3=room)
    var flags: UInt8 // Contact flags
    var outPathLength: UInt8 // Path length
    var outPath: Data? // Up to 64 bytes
    var lastAdvertisement: Date
    var latitude: Double? // Scaled by 1E6 in firmware
    var longitude: Double? // Scaled by 1E6 in firmware
    var lastModified: Date
}

/// Contact iterator state (matches firmware pattern)
public struct ContactIteratorState: Sendable {
    var contacts: [MockContact] = []
    var currentIndex: Int = 0
    var filterSince: Date = .distantPast
    var mostRecentLastMod: Date = .init(timeIntervalSince1970: 0) // Initialize to Unix epoch (timestamp 0)
    var isActive: Bool = false
}

// MARK: - Multi-ACK Support

/// Multi-ACK status for v7+ enhanced acknowledgment
public struct MultiAckStatus: Sendable {
    public let enabled: Bool
    public let activeAcks: [MultiAckEntry]

    public init(enabled: Bool, activeAcks: [MultiAckEntry] = []) {
        self.enabled = enabled
        self.activeAcks = activeAcks
    }
}

/// Multi-ACK entry representing an active acknowledgment
public struct MultiAckEntry: Sendable {
    public let ackCode: UInt32
    public let contactKeyPrefix: Data // 6 bytes
    public let timestamp: Date
    public let timeoutMs: UInt32

    public init(ackCode: UInt32, contactKeyPrefix: Data, timestamp: Date, timeoutMs: UInt32 = 5000) {
        self.ackCode = ackCode
        self.contactKeyPrefix = contactKeyPrefix
        self.timestamp = timestamp
        self.timeoutMs = timeoutMs
    }
}

// MARK: - Trace Data Support

/// Trace data structure for network diagnostics
public struct TraceData: Sendable {
    public let pathNodes: [TracePathNode]
    public let signalStrength: UInt16
    public let noiseLevel: UInt16
    public let packetLossRate: UInt32
    public let roundTripTime: UInt32
    public let throughput: UInt16
    public let queueDepth: UInt16
    public let rawData: Data

    public init(
        pathNodes: [TracePathNode] = [],
        signalStrength: UInt16 = 0,
        noiseLevel: UInt16 = 0,
        packetLossRate: UInt32 = 0,
        roundTripTime: UInt32 = 0,
        throughput: UInt16 = 0,
        queueDepth: UInt16 = 0,
        rawData: Data = Data()
    ) {
        self.pathNodes = pathNodes
        self.signalStrength = signalStrength
        self.noiseLevel = noiseLevel
        self.packetLossRate = packetLossRate
        self.roundTripTime = roundTripTime
        self.throughput = throughput
        self.queueDepth = queueDepth
        self.rawData = rawData
    }
}

/// Path trace node information
public struct TracePathNode: Sendable {
    public let publicKey: Data
    public let rssi: Int8
    public let latencyMs: UInt16

    public init(publicKey: Data, rssi: Int8, latencyMs: UInt16) {
        self.publicKey = publicKey
        self.rssi = rssi
        self.latencyMs = latencyMs
    }
}

/// Thread-safe state actor for mock radio
public actor BLERadioState {
    // Connection state
    private(set) var connectionState: RadioConnectionState = .disconnected
    private(set) var advertisingMode: AdvertisingMode = .connectable
    private(set) var mtu: Int = RadioConstants.defaultMTU

    // Offline queue (matches firmware)
    private var offlineQueue: [OfflineQueueEntry] = []

    // Expected ACK table (matches firmware)
    private var expectedAcks: [ExpectedAckEntry] = []
    private var nextAckIndex: Int = 0

    // Contact storage
    private var contacts: [MockContact] = []
    private var contactIterator: ContactIteratorState = .init()

    // Device info (from CMD_DEVICE_QUERY response) - REUSE EXISTING MODEL
    private(set) var deviceInfo: DeviceInfo

    // Self info (from CMD_APP_START response) - REUSE EXISTING MODEL
    private(set) var selfInfo: SelfInfo

    // Radio configuration
    private var radioConfig: MockRadioConfiguration = MockRadioConfiguration()

    public init(deviceInfo: DeviceInfo, selfInfo: SelfInfo) {
        self.deviceInfo = deviceInfo
        self.selfInfo = selfInfo
    }

    // MARK: - Connection State

    public func setConnectionState(_ state: RadioConnectionState) {
        logger.info("Connection state: \(String(describing: self.connectionState)) → \(String(describing: state))")
        connectionState = state
    }

    public func setMTU(_ mtu: Int) {
        logger.debug("MTU updated: \(self.mtu) → \(mtu)")
        self.mtu = mtu
    }

    // MARK: - Offline Queue

    public func enqueueOfflineFrame(_ frame: RadioFrame) throws {
        // Match firmware behavior: evict oldest channel message if queue full
        if offlineQueue.count >= RadioConstants.offlineQueueSize {
            if let channelMsgIndex = offlineQueue.firstIndex(where: { $0.isChannelMsg() }) {
                logger.warning("Offline queue full, evicting oldest channel message at index \(channelMsgIndex)")
                offlineQueue.remove(at: channelMsgIndex)
            } else {
                logger.error("Offline queue full, no channel messages to evict")
                throw RadioError.queueFull
            }
        }

        let entry = OfflineQueueEntry(frame: frame, timestamp: Date())
        offlineQueue.append(entry)
        logger.debug("Enqueued offline frame, queue length: \(self.offlineQueue.count)")
    }

    public func dequeueOfflineFrame() -> RadioFrame? {
        guard !offlineQueue.isEmpty else { return nil }
        let entry = offlineQueue.removeFirst()
        logger.debug("Dequeued offline frame, queue length: \(self.offlineQueue.count)")
        return entry.frame
    }

    public func offlineQueueLength() -> Int {
        offlineQueue.count
    }

    // MARK: - Expected ACK Tracking

    public func addExpectedAck(_ ackCode: UInt32, contactPublicKey: Data) {
        let entry = ExpectedAckEntry(
            ackCode: ackCode,
            timestamp: Date(),
            contactPublicKey: contactPublicKey,
        )

        // Circular buffer behavior (matches firmware)
        if expectedAcks.count < RadioConstants.expectedAckTableSize {
            expectedAcks.append(entry)
        } else {
            expectedAcks[nextAckIndex] = entry
            nextAckIndex = (nextAckIndex + 1) % RadioConstants.expectedAckTableSize
        }

        logger.debug("Added expected ACK: \(ackCode), table size: \(self.expectedAcks.count)")
    }

    public func checkExpectedAck(_ ackCode: UInt32) -> Data? {
        guard let index = expectedAcks.firstIndex(where: { $0.ackCode == ackCode }) else {
            return nil
        }

        let contactKey = expectedAcks[index].contactPublicKey
        // Clear the entry (matches firmware: expected_ack_table[i].ack = 0)
        expectedAcks.remove(at: index)
        logger.info("Matched expected ACK: \(ackCode)")
        return contactKey
    }

    // MARK: - Contact Storage

    public func addContact(_ contact: MockContact) {
        // Remove existing contact with same public key
        contacts.removeAll { $0.publicKey == contact.publicKey }
        contacts.append(contact)
        let pubKeyHex = contact.publicKey.hexString.prefix(16) // Short prefix for readability
        logger.info("Added contact: \(contact.name) [\(pubKeyHex)]")
    }

    public func removeContact(publicKey: Data) -> Bool {
        let initialCount = contacts.count
        contacts.removeAll { $0.publicKey == publicKey }
        let removed = contacts.count < initialCount
        let pubKeyHex = publicKey.hexString.prefix(16)
        if removed {
            logger.info("Removed contact [\(pubKeyHex)]")
        }
        return removed
    }

    public func getContactCount() -> Int {
        contacts.count
    }

    public func startContactIterator(since: Date = .distantPast) -> ContactIteratorState {
        var iterator = ContactIteratorState()

        // Apply timestamp filter
        iterator.contacts = contacts.filter { $0.lastModified > since }
        iterator.contacts.sort { $0.lastModified < $1.lastModified } // Sort by lastmod ascending (oldest-first)
        // Sort by lastmod ascending (oldest-first) to emulate typical storage iterator.
        // Firmware order unspecified; ascending ensures deterministic tests.
        iterator.filterSince = since
        iterator.currentIndex = 0
        iterator.isActive = true

        // Calculate most recent lastmod (only if timestamp > 0 to match firmware behavior)
        if let mostRecent = iterator.contacts.last, mostRecent.lastModified.timeIntervalSince1970 > 0 {
            iterator.mostRecentLastMod = mostRecent.lastModified
        }

        contactIterator = iterator
        logger.info("Started contact iterator: \(iterator.contacts.count) contacts since \(since)")

        return iterator
    }

    public func getNextContact() -> MockContact? {
        guard contactIterator.isActive,
              contactIterator.currentIndex < contactIterator.contacts.count
        else {
            return nil
        }

        let contact = contactIterator.contacts[contactIterator.currentIndex]
        contactIterator.currentIndex += 1

        let pubKeyHex = contact.publicKey.hexString.prefix(8) // Short prefix for debug logs
        logger.debug("Contact \(self.contactIterator.currentIndex)/\(self.contactIterator.contacts.count): \(contact.name) [\(pubKeyHex)]")

        return contact
    }

    public func endContactIterator() -> Date {
        defer {
            contactIterator.isActive = false
            contactIterator.currentIndex = 0
        }

        logger.info("Ended contact iterator, most recent lastmod: \(self.contactIterator.mostRecentLastMod)")
        return contactIterator.mostRecentLastMod
    }

    /// Reset all contacts (useful for test isolation)
    public func resetContacts() {
        contacts.removeAll()
        logger.info("Reset all contacts")
    }

    /// Add or update contact with validation (matches firmware addOrUpdateContact)
    /// Firmware Reference: MyMesh.cpp:1023-1043 (CMD_ADD_UPDATE_CONTACT handler)
    public func addOrUpdateContact(_ contact: MockContact) throws {
        // Validate contact limit (firmware: MAX_CONTACTS = 100)
        let contactCount = contacts.count
        guard contactCount < 100 else {
            throw RadioError.tableFull
        }

        // Validate public key format (32 bytes exactly)
        guard contact.publicKey.count == 32 else {
            throw RadioError.invalidFrame
        }

        // Remove existing contact with same public key (firmware overwrite semantics)
        contacts.removeAll { $0.publicKey == contact.publicKey }

        // Validate storage space before adding
        let estimatedStorageUsage = estimateContactStorageUsage(contact)
        let availableStorageSpace = getAvailableStorageSpace()
        guard estimatedStorageUsage <= availableStorageSpace else {
            throw RadioError.storageFull
        }

        contacts.append(contact)
        logger.info("Added/updated contact: '\(contact.name)'")
    }

    /// Remove contact by public key
    public func removeContact(publicKey: Data) async -> Bool {
        guard publicKey.count == 32 else { return false }

        let initialCount = contacts.count
        contacts.removeAll { $0.publicKey == publicKey }
        let removed = contacts.count < initialCount

        if removed {
            logger.info("Removed contact: \(publicKey.hexString)")
        }

        return removed
    }

    /// Get contact by public key
    public func getContactByPublicKey(_ publicKey: Data) async -> MockContact? {
        guard publicKey.count == 32 else { return nil }
        return contacts.first { $0.publicKey == publicKey }
    }

    // MARK: - Device Configuration Methods

    /// Set device time (for CMD_SET_DEVICE_TIME)
    public func setDeviceTime(timestamp: UInt32, timezoneOffset: UInt16, daylightSavings: UInt8) async {
        // Update selfInfo with new time-related settings
        // Note: In actual implementation, this would update device's internal clock
        // For mock purposes, we just log the time update
        logger.info("Device time set: timestamp=\(timestamp), timezone=\(timezoneOffset), DST=\(daylightSavings)")
    }

    /// Set advertisement name (for CMD_SET_ADVERT_NAME)
    public func setAdvertisementName(_ name: String) async {
        var updatedSelf = selfInfo
        updatedSelf.nodeName = name
        selfInfo = updatedSelf

        logger.info("Advertisement name set: '\(name)'")
    }

    /// Set device location (for CMD_SET_ADVERT_LATLON)
    public func setDeviceLocation(latitude: Double, longitude: Double) async {
        var updatedSelf = selfInfo
        updatedSelf.latitude = Int32(latitude * 1_000_000)
        updatedSelf.longitude = Int32(longitude * 1_000_000)
        selfInfo = updatedSelf

        logger.info("Device location set: (\(latitude), \(longitude))")
    }

    // MARK: - Helper Methods

    /// Firmware Reference: MyMesh.cpp contact storage patterns
    /// Storage estimation for contact validation
    private func estimateContactStorageUsage(_ contact: MockContact) -> UInt32 {
        // Approximate storage usage based on firmware ContactInfo structure
        let publicKeySize: UInt32 = 32
        let nameSize: UInt32 = 32
        let pathSize: UInt32 = 64
        let metadataSize: UInt32 = 20  // timestamps, flags, etc.
        return publicKeySize + nameSize + pathSize + metadataSize
    }

    /// Storage space simulation (firmware: persistent storage on device)
    private func getAvailableStorageSpace() -> UInt32 {
        // Simulate available storage space
        let totalStorage: UInt32 = 1000000  // 1MB simulated
        let usedStorage = contacts.reduce(UInt32(0)) { total, contact in
            return total + estimateContactStorageUsage(contact)
        }
        return totalStorage - usedStorage
    }

    /// Test helper method to pre-populate contacts
    public func populateTestContacts() {
        let testContacts = [
            MockContact(
                publicKey: Data(repeating: 0xAA, count: 32),
                name: "Test Contact 1",
                type: 1, // chat
                flags: 0x01,
                outPathLength: 0,
                outPath: nil,
                lastAdvertisement: Date().addingTimeInterval(-3600),
                latitude: 37.7749,
                longitude: -122.4194,
                lastModified: Date().addingTimeInterval(-1800),
            ),
            MockContact(
                publicKey: Data(repeating: 0xBB, count: 32),
                name: "Test Repeater",
                type: 2, // repeater
                flags: 0x00,
                outPathLength: 4,
                outPath: Data([0x01, 0x02, 0x03, 0x04]),
                lastAdvertisement: Date().addingTimeInterval(-7200),
                latitude: 37.7849,
                longitude: -122.4094,
                lastModified: Date().addingTimeInterval(-3600),
            ),
            MockContact(
                publicKey: Data(repeating: 0xCC, count: 32),
                name: "Test Room",
                type: 3, // room
                flags: 0x02,
                outPathLength: 0,
                outPath: nil,
                lastAdvertisement: Date().addingTimeInterval(-1800),
                latitude: 37.7649,
                longitude: -122.4294,
                lastModified: Date().addingTimeInterval(-900),
            ),
        ]

        for contact in testContacts {
            addContact(contact)
        }

        logger.info("Populated \(testContacts.count) test contacts")
    }

    // MARK: - Radio Configuration

    /// Set radio parameters (firmware: radio_set_params())
    public func setRadioParameters(
        frequency: UInt32,
        bandwidth: UInt32,
        spreadingFactor: UInt8,
        codingRate: UInt8
    ) {
        radioConfig.frequency = frequency
        radioConfig.bandwidth = bandwidth
        radioConfig.spreadingFactor = spreadingFactor
        radioConfig.codingRate = codingRate
        logger.info("Set radio params: freq=\(frequency)Hz, bw=\(bandwidth)Hz, sf=\(spreadingFactor), cr=\(codingRate)")
    }

    /// Get current radio configuration
    public func getRadioConfiguration() -> MockRadioConfiguration {
        return radioConfig
    }

    /// Set radio TX power (firmware: setTxPower())
    public func setRadioTxPower(_ power: Int8) {
        radioConfig.txPower = power
        logger.info("Set radio TX power: \(power)dBm")
    }

    /// Set battery level (for simulation)
    public func setBatteryLevel(_ level: UInt8) {
        radioConfig.batteryLevel = min(100, max(0, level))
        logger.debug("Battery level: \(self.radioConfig.batteryLevel)%")
    }

    /// Update storage usage (for simulation)
    public func updateStorageUsage(used: UInt32) {
        radioConfig.storageUsed = min(used, radioConfig.storageTotal)
        logger.debug("Storage usage: \(self.radioConfig.storageUsed)/\(self.radioConfig.storageTotal) bytes")
    }

    /// Get battery and storage info for CMD_GET_BATT_AND_STORAGE response
    public func getBatteryAndStorageInfo() -> (battery: UInt8, used: UInt32, total: UInt32) {
        return (
            battery: radioConfig.batteryLevel,
            used: radioConfig.storageUsed,
            total: radioConfig.storageTotal
        )
    }

    // MARK: - Phase 2: Contact Management Extended

    /// Get contact by public key (for Phase 2 contact management)
    public func getContactByPublicKey(_ publicKey: Data) -> MockContact? {
        // Validate input format
        guard publicKey.count == 32 else { return nil }
        return contacts.first { $0.publicKey == publicKey }
    }

    // MARK: - Phase 2: Advanced Messaging

    private var rawMessageQueue: [RawMessageEntry] = []
    private var connectionStatus: [Data: Bool] = [:] // publicKey -> connected
    private var statusResponseQueue: [StatusResponseEntry] = []

    /// Queue raw data message for transmission
    public func queueRawDataMessage(_ data: Data, dataType: UInt8, targetKey: Data) {
        let entry = RawMessageEntry(data: data, dataType: dataType, targetKey: targetKey, timestamp: Date())
        rawMessageQueue.append(entry)
        logger.debug("Queued raw data message, queue length: \(self.rawMessageQueue.count)")
    }

    /// Check connection status for target device
    public func checkConnectionStatus(_ targetKeyPrefix: Data) -> Bool {
        // Simple mock implementation - return true for testing
        // In real implementation, would check actual connection status
        return connectionStatus[targetKeyPrefix] ?? true
    }

    /// Set connection status for device (for testing)
    public func setConnectionStatus(_ targetKeyPrefix: Data, connected: Bool) {
        connectionStatus[targetKeyPrefix] = connected
        logger.debug("Set connection status for [\(targetKeyPrefix.hexString.prefix(8))]: \(connected)")
    }

    /// Queue status response as push notification
    public func queueStatusResponse(_ responseData: Data, targetKey: Data) {
        let entry = StatusResponseEntry(data: responseData, targetKey: targetKey, timestamp: Date())
        statusResponseQueue.append(entry)
        logger.debug("Queued status response, queue length: \(self.statusResponseQueue.count)")
    }

    /// Get next queued status response (for testing)
    public func getNextStatusResponse() -> StatusResponseEntry? {
        guard !statusResponseQueue.isEmpty else { return nil }
        return statusResponseQueue.removeFirst()
    }

    // MARK: - Phase 2: Security Foundation

    private var devicePIN: UInt32 = 0
    private var customVariables: [String: String] = [:]

    /// Get device PIN
    public func getDevicePIN() -> UInt32 {
        return devicePIN
    }

    /// Set device PIN
    public func setDevicePIN(_ pin: UInt32) {
        devicePIN = pin
        logger.info("Device PIN updated")
    }

    /// Get all custom variables
    public func getCustomVariables() -> [String: String] {
        return customVariables
    }

    /// Set custom variable
    public func setCustomVariable(key: String, value: String) {
        customVariables[key] = value
        logger.debug("Set custom variable: \(key) = \(value)")
    }

    /// Get custom variable value
    public func getCustomVariable(key: String) -> String? {
        return customVariables[key]
    }

    /// Clear all custom variables (for testing)
    public func clearCustomVariables() {
        customVariables.removeAll()
        logger.debug("Cleared all custom variables")
    }

    // MARK: - Phase 3: Authentication Commands

    private var authenticatedSessions: [Data: Date] = [:] // publicKey -> loginTime
    private var privateKey: Data = Data(repeating: 0x42, count: 32) // Mock private key

    /// Export mock private key
    public func exportPrivateKey() async -> Data {
        return privateKey
    }

    /// Import private key (mock implementation)
    public func importPrivateKey(_ key: Data) async {
        guard key.count == 32 else { return }
        privateKey = key
        logger.info("Imported private key")
    }

    /// Authenticate contact (mock: always succeed for testing)
    public func authenticateContact(publicKey: Data, credentials: Data) async -> Bool {
        guard publicKey.count == 32 else { return false }
        // Simple mock authentication - always succeed for testing
        authenticatedSessions[publicKey] = Date()
        logger.info("Authenticated contact")
        return true
    }

    /// Logout contact (remove from authenticated sessions)
    public func logoutContact(publicKey: Data) async {
        guard publicKey.count == 32 else { return }
        authenticatedSessions.removeValue(forKey: publicKey)
        logger.info("Logged out contact")
    }

    /// Check if contact is authenticated
    public func isContactAuthenticated(_ publicKey: Data) async -> Bool {
        guard publicKey.count == 32 else { return false }
        return authenticatedSessions[publicKey] != nil
    }

    /// Get all authenticated sessions
    public func getAuthenticatedSessions() async -> [Data: Date] {
        return authenticatedSessions
    }

    // MARK: - Phase 3: Path Discovery Basic

    private var contactPaths: [Data: Data] = [:] // publicKey -> path (up to 64 bytes)

    /// Reset path for contact
    public func resetPath(for publicKey: Data) async {
        guard publicKey.count == 32 else { return }
        contactPaths[publicKey] = Data()
        logger.debug("Reset path for contact")
    }

    /// Get path for contact
    public func getContactPath(for publicKey: Data) async -> Data {
        guard publicKey.count == 32 else { return Data() }
        return contactPaths[publicKey] ?? Data()
    }

    /// Set path for contact
    public func setContactPath(for publicKey: Data, path: Data) async {
        guard publicKey.count == 32 else { return }
        contactPaths[publicKey] = path
        logger.debug("Set path for contact")
    }

    // MARK: - Phase 3: Advanced Configuration (v8+ Features)

    private var floodScope: UInt8 = 0 // Global flood
    private var transportKey: Data = Data(repeating: 0x00, count: 32) // Mock transport key
    private var controlDataQueue: [ControlDataEntry] = []

    // MARK: - Phase 4: Advanced Network Features

    private var networkTopology: [Data: [Data]] = [:] // publicKey -> neighbors array
    private var pathCache: [Data: [Data]] = [:] // destination -> path array with TTL
    private var pathCacheTimestamps: [Data: Date] = [:] // destination -> cache timestamp
    private let pathCacheTTL: TimeInterval = 60.0 // 60 seconds TTL for path cache

    // MARK: - Phase 4: Telemetry and Monitoring

    public struct TelemetryData: Sendable {
        public let batteryVoltage: Float
        public let temperature: Float
        public let humidity: Float
        public let lastUpdate: Date

        public init(batteryVoltage: Float, temperature: Float, humidity: Float, lastUpdate: Date) {
            self.batteryVoltage = batteryVoltage
            self.temperature = temperature
            self.humidity = humidity
            self.lastUpdate = lastUpdate
        }
    }

    public struct MinMaxAvgData: Sendable {
        public let min: Float
        public let max: Float
        public let avg: Float

        public init(min: Float, max: Float, avg: Float) {
            self.min = min
            self.max = max
            self.avg = avg
        }
    }

    public struct ACLEntry: Sendable {
        public let publicKey: Data
        public let permissions: UInt8
        public let granted: Date

        public init(publicKey: Data, permissions: UInt8, granted: Date) {
            self.publicKey = publicKey
            self.permissions = permissions
            self.granted = granted
        }
    }

    public struct NeighborInfo: Sendable {
        public let publicKey: Data
        public let signalStrength: Int8 // RSSI in dBm
        public let lastSeen: Date
        public let hopCount: UInt8 // Number of hops to reach this neighbor

        public init(publicKey: Data, signalStrength: Int8, lastSeen: Date, hopCount: UInt8) {
            self.publicKey = publicKey
            self.signalStrength = signalStrength
            self.lastSeen = lastSeen
            self.hopCount = hopCount
        }
    }

    private var currentTelemetry: TelemetryData = TelemetryData(
        batteryVoltage: 3.7,
        temperature: 25.0,
        humidity: 50.0,
        lastUpdate: Date()
    )
    private var neighborTable: [Data: NeighborInfo] = [:] // publicKey -> neighbor info
    private var aclEntries: [ACLEntry] = []
    private var binaryRequestQueue: [(request: Data, timestamp: Date, targetKey: Data)] = []

    /// Set flood scope with transport key
    public func setFloodScope(_ scope: UInt8, transportKey: Data) async {
        guard transportKey.count == 32 else { return }
        self.floodScope = scope
        self.transportKey = transportKey
        logger.info("Set flood scope: \(scope)")
    }

    /// Get current flood scope
    public func getFloodScope() async -> UInt8 {
        return floodScope
    }

    /// Get current transport key
    public func getTransportKey() async -> Data {
        return transportKey
    }

    /// Queue control data for transmission
    public func queueControlData(_ type: UInt8, targetKey: Data, data: Data) async {
        guard targetKey.count == 6 else { return }
        let entry = ControlDataEntry(type: type, targetKey: targetKey, data: data, timestamp: Date())
        controlDataQueue.append(entry)
        logger.debug("Queued control data, queue length: \(self.controlDataQueue.count)")
    }

    /// Get next queued control data (for testing)
    public func getNextControlData() -> ControlDataEntry? {
        guard !controlDataQueue.isEmpty else { return nil }
        return controlDataQueue.removeFirst()
    }

    /// Get control data queue length
    public func getControlDataQueueLength() -> Int {
        return controlDataQueue.count
    }

    /// Clear all control data (for testing)
    public func clearControlData() async {
        controlDataQueue.removeAll()
        logger.debug("Cleared all control data")
    }

    // MARK: - Phase 4: Advanced Network Features

    /// Discover path to destination using network topology
    /// Firmware Reference: Simple path discovery simulation
    public func discoverPath(to destination: Data) async -> [Data] {
        guard destination.count == 32 else { return [] }

        // Check if we have a cached path that's still valid
        if let cachedPath = pathCache[destination],
           let cacheTimestamp = pathCacheTimestamps[destination],
           Date().timeIntervalSince(cacheTimestamp) < pathCacheTTL {
            logger.debug("Using cached path to destination")
            return cachedPath
        }

        // Simple path discovery: check direct neighbors first
        if let directNeighbors = networkTopology[selfInfo.publicKey],
           directNeighbors.contains(destination) {
            let path = [destination] // Direct connection
            pathCache[destination] = path
            pathCacheTimestamps[destination] = Date()
            logger.debug("Found direct path to destination")
            return path
        }

        // Multi-hop simulation: construct path through neighbors
        for neighbor in networkTopology.keys {
            if let neighborNeighbors = networkTopology[neighbor],
               neighborNeighbors.contains(destination) {
                let path = [neighbor, destination] // Two-hop path
                pathCache[destination] = path
                pathCacheTimestamps[destination] = Date()
                logger.debug("Found two-hop path through neighbor")
                return path
            }
        }

        // Default empty path if no route found
        return []
    }

    /// Set network topology for path discovery simulation
    public func setNetworkTopology(_ topology: [Data: [Data]]) async {
        networkTopology = topology
        // Clear path cache when topology changes
        pathCache.removeAll()
        pathCacheTimestamps.removeAll()
        logger.info("Updated network topology with \(topology.count) nodes")
    }

    /// Get current network topology (for testing)
    public func getNetworkTopology() async -> [Data: [Data]] {
        return networkTopology
    }

    /// Add neighbor to network topology
    public func addNeighbor(_ publicKey: Data, neighbors: [Data]) async {
        guard publicKey.count == 32 else { return }
        networkTopology[publicKey] = neighbors
        // Clear affected path cache entries
        pathCache.removeAll()
        pathCacheTimestamps.removeAll()
        logger.debug("Added neighbor to topology")
    }

    /// Set contact path with enhanced validation
    public func setContactPathAdvanced(for publicKey: Data, path: [Data]) async {
        guard publicKey.count == 32 else { return }
        // Validate path (all entries should be 32-byte public keys)
        let validPath = path.allSatisfy { $0.count == 32 }
        guard validPath else {
            logger.warning("Invalid path format - skipping")
            return
        }

        contactPaths[publicKey] = Data(path.joined())
        logger.debug("Set advanced contact path with \(path.count) hops")
    }

    // MARK: - Phase 4: Telemetry and Monitoring

    /// Get current telemetry data with realistic sensor simulation
    public func getTelemetry() async -> TelemetryData {
        // Update telemetry with realistic variations
        currentTelemetry = TelemetryData(
            batteryVoltage: Float.random(in: 3.2...4.2), // Realistic Li-ion range
            temperature: Float.random(in: 15...35),     // Reasonable temperature range
            humidity: Float.random(in: 30...70),         // Reasonable humidity range
            lastUpdate: Date()
        )
        return currentTelemetry
    }

    /// Get min/max/avg data for sensor monitoring
    public func getMinMaxAvgData() async -> MinMaxAvgData {
        // Mock min/max/avg sensor data based on current telemetry
        return MinMaxAvgData(
            min: currentTelemetry.temperature - 5.0,
            max: currentTelemetry.temperature + 5.0,
            avg: currentTelemetry.temperature
        )
    }

    /// Get neighbor table entries for network monitoring
    public func getNeighborTable() async -> [NeighborInfo] {
        // Update neighbor timestamps and return sorted list
        let now = Date()
        for (publicKey, var neighbor) in neighborTable {
            neighbor = NeighborInfo(
                publicKey: neighbor.publicKey,
                signalStrength: neighbor.signalStrength,
                lastSeen: now, // Update to current time for freshness
                hopCount: neighbor.hopCount
            )
            neighborTable[publicKey] = neighbor
        }

        return neighborTable.values.sorted { $0.hopCount < $1.hopCount }
    }

    /// Add or update neighbor information
    public func updateNeighbor(_ publicKey: Data, signalStrength: Int8, hopCount: UInt8) async {
        guard publicKey.count == 32 else { return }
        let neighbor = NeighborInfo(
            publicKey: publicKey,
            signalStrength: signalStrength,
            lastSeen: Date(),
            hopCount: hopCount
        )
        neighborTable[publicKey] = neighbor
        logger.debug("Updated neighbor: hop=\(hopCount), rssi=\(signalStrength)dBm")
    }

    /// Process binary request with chunking support
    public func processBinaryRequest(_ request: Data, targetKey: Data) async -> Data {
        guard request.count <= 1024 else { return Data() } // Max 1KB for mock

        // Add to binary request queue for tracking
        binaryRequestQueue.append((request, Date(), targetKey))

        // Mock binary response - echo back request with processing indicator
        var response = Data()
        response.append(0x01) // Processing success flag
        response.append(UInt8(request.count)) // Echo original size
        response.append(request) // Echo original data

        // Keep queue size manageable
        if binaryRequestQueue.count > 100 {
            binaryRequestQueue.removeFirst()
        }

        logger.debug("Processed binary request: \(request.count) bytes")
        return response
    }

    /// Get binary request queue status (for testing)
    public func getBinaryRequestQueueLength() -> Int {
        return binaryRequestQueue.count
    }

    /// Clear binary request queue (for testing)
    public func clearBinaryRequestQueue() async {
        binaryRequestQueue.removeAll()
        logger.debug("Cleared binary request queue")
    }

    /// ACL management methods
    public func addACLEntry(_ publicKey: Data, permissions: UInt8) async {
        guard publicKey.count == 32 else { return }
        let entry = ACLEntry(publicKey: publicKey, permissions: permissions, granted: Date())

        // Remove existing entry if present
        aclEntries.removeAll { $0.publicKey == publicKey }
        aclEntries.append(entry)

        logger.info("Added ACL entry for device")
    }

    /// Get ACL entries
    public func getACLEntries() async -> [ACLEntry] {
        return aclEntries.sorted { $0.granted < $1.granted }
    }

    /// Remove ACL entry
    public func removeACLEntry(_ publicKey: Data) async {
        guard publicKey.count == 32 else { return }
        aclEntries.removeAll { $0.publicKey == publicKey }
        logger.info("Removed ACL entry")
    }

    /// Clear all ACL entries (for testing)
    public func clearACLEntries() async {
        aclEntries.removeAll()
        logger.debug("Cleared all ACL entries")
    }

    // MARK: - Channel Management

    public struct ChannelInfo: Sendable {
        public let channelId: UInt16
        public let name: String
        public let memberCount: Int
        public let lastActivity: Date

        public init(channelId: UInt16, name: String, memberCount: Int, lastActivity: Date) {
            self.channelId = channelId
            self.name = name
            self.memberCount = memberCount
            self.lastActivity = lastActivity
        }
    }

    private var currentChannel: ChannelInfo = ChannelInfo(channelId: 1, name: "default", memberCount: 1, lastActivity: Date())

    public func getChannelInfo() async -> ChannelInfo {
        return currentChannel
    }

    public func setChannel(channelId: UInt16, name: String) async {
        currentChannel = ChannelInfo(channelId: channelId, name: name, memberCount: 1, lastActivity: Date())
        logger.info("Channel set to: \(channelId) '\(name)'")
    }

    // MARK: - System Management

    public func simulateReboot() async {
        // Reset all non-persistent state
        offlineQueue.removeAll()
        expectedAcks.removeAll()
        authenticatedSessions.removeAll()
        connectionStatus.removeAll()

        // Keep persistent data like contacts and configuration
        logger.info("Reboot simulated - volatile state reset")
    }

    public func factoryReset() async {
        // Reset everything to default state
        await simulateReboot()
        contacts.removeAll()
        radioConfig = MockRadioConfiguration()
        currentChannel = ChannelInfo(channelId: 1, name: "default", memberCount: 1, lastActivity: Date())
        customVariables.removeAll()
        aclEntries.removeAll()

        logger.info("Factory reset completed - all state reset")
    }

    // MARK: - Digital Signing

    private struct SigningSession: Sendable {
        let sessionId: UInt32
        let dataLength: UInt32
        let dataHash: Data
        var chunks: [UInt16: Data] = [:]
        let startTime: Date
    }

    private var signingSessions: [UInt32: SigningSession] = [:]
    private var nextSigningSessionId: UInt32 = 1

    public func startSigningSession(dataLength: UInt32, dataHash: Data) async -> UInt32 {
        let sessionId = nextSigningSessionId
        nextSigningSessionId += 1

        let session = SigningSession(
            sessionId: sessionId,
            dataLength: dataLength,
            dataHash: dataHash,
            chunks: [:],
            startTime: Date()
        )

        signingSessions[sessionId] = session
        logger.info("Started signing session: \(sessionId)")

        return sessionId
    }

    public func addDataToSigningSession(sessionId: UInt32, chunkIndex: UInt16, data: Data) async -> Bool {
        guard var session = signingSessions[sessionId] else { return false }

        session.chunks[chunkIndex] = data
        signingSessions[sessionId] = session

        logger.debug("Added chunk \(chunkIndex) to signing session: \(sessionId)")
        return true
    }

    public func finishSigningSession(sessionId: UInt32) async -> Data? {
        guard signingSessions[sessionId] != nil else { return nil }

        // Generate mock signature (64 bytes for ECDSA)
        var signature = Data(count: 64)
        for i in 0..<64 {
            signature[i] = UInt8.random(in: 0...255)
        }

        // Clean up session
        signingSessions.removeValue(forKey: sessionId)

        logger.info("Completed signing session: \(sessionId)")
        return signature
    }

    // MARK: - Other Parameters

    private var otherParameters: [UInt8: Data] = [:]

    public func setOtherParameter(type: UInt8, data: Data) async {
        otherParameters[type] = data
        logger.debug("Set other parameter: type=\(type), size=\(data.count)")
    }

    public func getOtherParameter(type: UInt8) async -> Data? {
        return otherParameters[type]
    }

    // MARK: - Flood Scope Management

    public struct FloodScopeInfo: Sendable {
        public let floodScope: UInt8
        public let transportKey: Data

        public init(floodScope: UInt8, transportKey: Data) {
            self.floodScope = floodScope
            self.transportKey = transportKey
        }
    }

    private var floodScopeInfo: FloodScopeInfo = FloodScopeInfo(floodScope: 0, transportKey: Data(repeating: 0, count: 32))

    public func getFloodScopeInfo() async -> FloodScopeInfo {
        return floodScopeInfo
    }

    // MARK: - Phase 2: Helper Models

    private struct RawMessageEntry: Sendable {
        let data: Data
        let dataType: UInt8
        let targetKey: Data
        let timestamp: Date
    }

    /// Status response entry for advanced messaging testing
    public struct StatusResponseEntry: Sendable {
        public let data: Data
        public let targetKey: Data
        public let timestamp: Date

        public init(data: Data, targetKey: Data, timestamp: Date) {
            self.data = data
            self.targetKey = targetKey
            self.timestamp = timestamp
        }
    }

    /// Control data entry for v8+ advanced configuration testing
    public struct ControlDataEntry: Sendable {
        public let type: UInt8
        public let targetKey: Data // 6-byte prefix
        public let data: Data
        public let timestamp: Date

        public init(type: UInt8, targetKey: Data, data: Data, timestamp: Date) {
            self.type = type
            self.targetKey = targetKey
            self.data = data
            self.timestamp = timestamp
        }
    }

    // MARK: - Additional Methods for 100% Protocol Coverage

    /// Get multi-ACK status for CMD_GET_MULTI_ACKS (56)
    public func getMultiAckStatus() async -> MultiAckStatus {
        // Filter out expired ACKs (older than 30 seconds)
        let now = Date()
        let activeAcks = expectedAcks.compactMap { ack -> MultiAckEntry? in
            let timeSinceCreation = now.timeIntervalSince(ack.timestamp)
            if timeSinceCreation > 30 { // 30 second timeout
                return nil
            }

            // Ensure contact key prefix is 6 bytes
            let keyPrefix = ack.contactPublicKey.count >= 6 ?
                Data(ack.contactPublicKey.prefix(6)) :
                Data(repeating: 0, count: 6)

            return MultiAckEntry(
                ackCode: ack.ackCode,
                contactKeyPrefix: keyPrefix,
                timestamp: ack.timestamp,
                timeoutMs: 5000 // Default 5 second timeout
            )
        }

        // Multi-ACK is enabled if selfInfo has multi_acks enabled (v7+ feature)
        let enabled = selfInfo.multiAcks > 0

        return MultiAckStatus(enabled: enabled, activeAcks: activeAcks)
    }

    /// Update discovered path for CMD_SEND_PATH_DISCOVERY (58)
    public func updateDiscoveredPath(to publicKey: Data, path: [Data]) async {
        // This method updates internal path discovery state
        // For testing purposes, we'll store paths in a simple dictionary
        logger.info("Discovered path to \(publicKey.hexString): \(path.count) hops")

        // In a real implementation, this would update network topology
        // For mock, we just log the path discovery
    }

    /// Set contact path for CMD_CHANGE_CONTACT_PATH (60)
    public func setContactPath(for publicKey: Data, path: [Data]) async {
        // This method updates the path for a specific contact
        logger.info("Setting path for contact \(publicKey.hexString): \(path.count) nodes")

        // In a real implementation, this would update routing tables
        // For mock, we just log the path update
    }

    }
