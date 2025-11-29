import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.mock", category: "RadioState")

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
}
