import XCTest
import SwiftData
import Foundation
@testable import PocketMesh
@testable import PocketMeshKit

/// Tests AdvertisementService integration with MockBLERadio against CORRECT MeshCore specification
///
/// IMPORTANT: These tests validate against the CORRECT MeshCore specification as implemented
/// in the official Python client, not the current (incorrect) PocketMesh implementation.
/// Tests will FAIL until PocketMesh is fixed to match the specification.
@MainActor
final class AdvertisementServiceTests: BaseTestCase {

    var advertisementService: AdvertisementService!
    var testDevice: Device!
    var testContact: Contact!

    override func setUp() async throws {
        try await super.setUp()

        // Create test device and contact
        testDevice = try TestDataFactory.createTestDevice()
        testContact = try TestDataFactory.createTestContact()

        // Save to SwiftData context
        modelContext.insert(testDevice)
        modelContext.insert(testContact)
        try modelContext.save()

        // Initialize AdvertisementService with mock BLE manager
        advertisementService = AdvertisementService(
            bleManager: mockBLEManager,
            modelContext: modelContext
        )
    }

    override func tearDown() async throws {
        advertisementService = nil
        testDevice = nil
        testContact = nil
        try await super.tearDown()
    }

    // MARK: - Advertisement Sending Tests

    func testSendAdvertisement_DirectMode() async throws {
        // Given
        let advertisementData = AdvertisementService.AdvertisementData(
            publicKey: testContact.publicKey,
            timestamp: Date(),
            messageType: .direct,
            floodScope: .none // Direct mode (not flooding)
        )

        // When
        try await advertisementService.sendAdvertisement(data: advertisementData)

        // Then - Advertisement should be sent in direct mode
        // TODO: Validate that AdvertisementService uses correct MeshCore advertisement format
        // TODO: Validate flood scope is set to .none for direct mode

        // Validate protocol calls were made correctly
        // TODO: Validate exact bytes sent match MeshCore specification
        XCTFail("TODO: Implement MockBLERadio TX capture to validate advertisement sending")
    }

    func testSendAdvertisement_FloodMode() async throws {
        // Given
        let advertisementData = AdvertisementService.AdvertisementData(
            publicKey: testContact.publicKey,
            timestamp: Date(),
            messageType: .direct,
            floodScope: .local // Flood mode
        )

        // When
        try await advertisementService.sendAdvertisement(data: advertisementData)

        // Then - Advertisement should be sent in flood mode
        // TODO: Validate that AdvertisementService correctly sets flood scope
        // TODO: Validate MeshCore protocol flood parameters

        XCTFail("TODO: Implement flood mode validation in AdvertisementService tests")
    }

    func testSendAdvertisement_SpecCompliance_PayloadFormat() async throws {
        // Test that AdvertisementService follows MeshCore specification for advertisement format
        // Current PocketMesh: May have incorrect advertisement format - needs validation

        // Given
        let advertisementData = AdvertisementService.AdvertisementData(
            publicKey: testContact.publicKey,
            timestamp: Date(),
            messageType: .direct,
            floodScope: .none
        )

        // Configure mock to capture outgoing bytes for validation
        // TODO: This requires MockBLERadio TX capture functionality

        // When
        try await advertisementService.sendAdvertisement(data: advertisementData)

        // Then - Validate advertisement payload format matches MeshCore specification
        // TODO: Validate exact bytes match MeshCore advertisement format
        XCTFail("TODO: Implement MockBLERadio TX capture to validate advertisement payload format")
    }

    // MARK: - Contact Synchronization Tests

    func testSyncContacts_EmptyList() async throws {
        // Given - No contacts in database initially
        let initialCount = try modelContext.fetchCount(FetchDescriptor<Contact>())
        XCTAssertEqual(initialCount, 1) // Only our test contact

        // When - Sync with empty contact list from device
        let deviceContacts: [Contact] = []

        try await advertisementService.syncContacts(deviceContacts)

        // Then - Database should only contain our test contact
        let finalCount = try modelContext.fetchCount(FetchDescriptor<Contact>())
        XCTAssertEqual(finalCount, 1) // Test contact should remain
    }

    func testSyncContacts_IncrementalUpdate() async throws {
        // Given - Existing contact
        let existingContact = try TestDataFactory.createTestContact(id: "existing")
        existingContact.name = "Old Name"
        modelContext.insert(existingContact)
        try modelContext.save()

        // When - Sync with updated contact information
        let updatedContact = try TestDataFactory.createTestContact(id: "existing")
        updatedContact.name = "Updated Name"
        updatedContact.lastSeen = Date()

        try await advertisementService.syncContacts([updatedContact])

        // Then - Contact should be updated in database
        let fetchDescriptor = FetchDescriptor<Contact>(
            predicate: #Predicate<Contact> { contact in
                contact.id == "existing"
            }
        )
        let contacts = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(contacts.count, 1)

        let savedContact = contacts.first!
        XCTAssertEqual(savedContact.name, "Updated Name")
        XCTAssertEqual(savedContact.publicKey, updatedContact.publicKey)
    }

    func testSyncContacts_NewContact() async throws {
        // Given - Initial contact count
        let initialCount = try modelContext.fetchCount(FetchDescriptor<Contact>())

        // When - Sync with new contact from device
        let newContact = try TestDataFactory.createTestContact(id: "new_contact")

        try await advertisementService.syncContacts([newContact])

        // Then - New contact should be added to database
        let finalCount = try modelContext.fetchCount(FetchDescriptor<Contact>())
        XCTAssertEqual(finalCount, initialCount + 1)

        let fetchDescriptor = FetchDescriptor<Contact>(
            predicate: #Predicate<Contact> { contact in
                contact.id == "new_contact"
            }
        )
        let contacts = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(contacts.count, 1)
        XCTAssertEqual(contacts.first?.name, newContact.name)
    }

    func testSyncContacts_RemovedContact() async throws {
        // Given - Contact that will be removed
        let removableContact = try TestDataFactory.createTestContact(id: "removable")
        modelContext.insert(removableContact)
        try modelContext.save()

        let initialCount = try modelContext.fetchCount(FetchDescriptor<Contact>())

        // When - Sync without the removable contact
        let remainingContacts = [testContact] // Only keep our test contact

        try await advertisementService.syncContacts(remainingContacts)

        // Then - Removed contact should be deleted from database
        let finalCount = try modelContext.fetchCount(FetchDescriptor<Contact>())
        XCTAssertEqual(finalCount, initialCount - 1)

        let fetchDescriptor = FetchDescriptor<Contact>(
            predicate: #Predicate<Contact> { contact in
                contact.id == "removable"
            }
        )
        let contacts = try modelContext.fetch(fetchDescriptor)
        XCTAssertTrue(contacts.isEmpty)
    }

    // MARK: - Contact Discovery Tests

    func testContactDiscovery_AutoAdd() async throws {
        // Test that newly discovered contacts are automatically added
        // Configure AdvertisementService to auto-add new contacts

        // Given
        let discoveredPublicKey = Data(repeating: 0x42, count: 32)
        let discoveredTimestamp = Date()

        // When
        await advertisementService.handleDiscoveredContact(
            publicKey: discoveredPublicKey,
            timestamp: discoveredTimestamp,
            autoAdd: true
        )

        // Then
        let fetchDescriptor = FetchDescriptor<Contact>(
            predicate: #Predicate<Contact> { contact in
                contact.publicKey == discoveredPublicKey
            }
        )
        let contacts = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(contacts.count, 1)

        let discoveredContact = contacts.first!
        XCTAssertEqual(discoveredContact.publicKey, discoveredPublicKey)
        XCTAssertEqual(discoveredContact.approvalStatus, .approved) // Auto-added contacts should be approved
        XCTAssertNotNil(discoveredContact.firstSeen)
        XCTAssertNotNil(discoveredContact.lastSeen)
    }

    func testContactDiscovery_PendingApproval() async throws {
        // Test that newly discovered contacts can be marked as pending approval
        // Configure AdvertisementService to require approval for new contacts

        // Given
        let discoveredPublicKey = Data(repeating: 0x43, count: 32)
        let discoveredTimestamp = Date()

        // When
        await advertisementService.handleDiscoveredContact(
            publicKey: discoveredPublicKey,
            timestamp: discoveredTimestamp,
            autoAdd: false // Require manual approval
        )

        // Then
        let fetchDescriptor = FetchDescriptor<Contact>(
            predicate: #Predicate<Contact> { contact in
                contact.publicKey == discoveredPublicKey
            }
        )
        let contacts = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(contacts.count, 1)

        let discoveredContact = contacts.first!
        XCTAssertEqual(discoveredContact.publicKey, discoveredPublicKey)
        XCTAssertEqual(discoveredContact.approvalStatus, .pending) // Should be pending approval
    }

    func testContactDiscovery_DuplicateDetection() async throws {
        // Test that discovering an existing contact doesn't create duplicates

        // Given - Existing contact
        let existingContact = try TestDataFactory.createTestContact(id: "duplicate_test")
        modelContext.insert(existingContact)
        try modelContext.save()

        let initialCount = try modelContext.fetchCount(FetchDescriptor<Contact>())

        // When - Discover same contact again
        await advertisementService.handleDiscoveredContact(
            publicKey: existingContact.publicKey,
            timestamp: Date(),
            autoAdd: true
        )

        // Then - No duplicate should be created
        let finalCount = try modelContext.fetchCount(FetchDescriptor<Contact>())
        XCTAssertEqual(finalCount, initialCount)

        // Existing contact should have updated lastSeen
        let fetchDescriptor = FetchDescriptor<Contact>(
            predicate: #Predicate<Contact> { contact in
                contact.id == "duplicate_test"
            }
        )
        let contacts = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(contacts.count, 1)

        let updatedContact = contacts.first!
        XCTAssertGreaterThan(updatedContact.lastSeen!, existingContact.lastSeen!)
    }

    // MARK: - Advertisement Processing Tests

    func testProcessReceivedAdvertisement_ValidFormat() async throws {
        // Test processing of received advertisements in correct MeshCore format

        // Given
        let receivedAdvertisement = MockBLEManager.ReceivedAdvertisement(
            publicKey: testContact.publicKey,
            timestamp: Date(),
            messageType: .direct,
            rssi: -45
        )

        // When
        await advertisementService.processReceivedAdvertisement(receivedAdvertisement)

        // Then
        // TODO: Validate that advertisement is processed according to MeshCore spec
        // TODO: Validate contact creation/update behavior
        XCTFail("TODO: Implement advertisement processing validation")
    }

    func testProcessReceivedAdvertisement_InvalidFormat() async throws {
        // Test handling of malformed advertisements

        // Given
        let malformedAdvertisement = MockBLEManager.ReceivedAdvertisement(
            publicKey: Data(), // Empty public key (invalid)
            timestamp: Date(),
            messageType: .direct,
            rssi: -45
        )

        // When
        await advertisementService.processReceivedAdvertisement(malformedAdvertisement)

        // Then - Should handle gracefully without crashing
        // TODO: Validate error handling for malformed advertisements
        XCTFail("TODO: Implement malformed advertisement handling validation")
    }

    // MARK: - Prefix Matching Tests

    func testAdvertisementPrefixMatching() async throws {
        // Test prefix matching functionality for contact filtering
        // MeshCore specification may support prefix-based contact matching

        // Given
        let targetPrefix = "mesh"
        let matchingContact = try TestDataFactory.createTestContact(id: "mesh_contact_1")
        let nonMatchingContact = try TestDataFactory.createTestContact(id: "other_contact")

        modelContext.insert(matchingContact)
        modelContext.insert(nonMatchingContact)
        try modelContext.save()

        // When
        let filteredContacts = await advertisementService.filterContactsByPrefix(targetPrefix)

        // Then
        XCTAssertTrue(filteredContacts.contains { $0.id.hasPrefix(targetPrefix) })
        XCTAssertFalse(filteredContacts.contains { !$0.id.hasPrefix(targetPrefix) })

        // TODO: Implement actual prefix matching in AdvertisementService
        XCTFail("TODO: Implement prefix matching functionality in AdvertisementService")
    }

    // MARK: - Location Update Tests

    func testSendLocationAdvertisement() async throws {
        // Test sending advertisements with location information

        // Given
        let locationData = AdvertisementService.LocationData(
            latitude: 37.7749,
            longitude: -122.4194,
            altitude: 100.0,
            timestamp: Date()
        )

        // When
        try await advertisementService.sendLocationAdvertisement(
            publicKey: testContact.publicKey,
            location: locationData
        )

        // Then
        // TODO: Validate location advertisement format matches MeshCore spec
        // TODO: Validate altitude field is properly included (required by spec)
        XCTFail("TODO: Implement location advertisement sending and validation")
    }

    // MARK: - Path Notification Tests

    func testPathNotificationProcessing() async throws {
        // Test processing of path notifications from MeshCore device
        // Path notifications indicate successful message routing

        // Given
        let pathNotification = MockBLEManager.PathNotification(
            sourcePublicKey: testContact.publicKey,
            destinationPublicKey: testDevice.publicKey,
            hopCount: 2,
            timestamp: Date()
        )

        // When
        await advertisementService.processPathNotification(pathNotification)

        // Then
        // TODO: Validate path data is stored correctly for routing table
        // TODO: Validate contact path length vs actual path data handling
        XCTFail("TODO: Implement path notification processing validation")
    }

    // MARK: - Advertisement Frequency Tests

    func testAdvertisementFrequency_Limiting() async throws {
        // Test that advertisement sending respects frequency limits
        // MeshCore specification may have rate limiting requirements

        // Given
        let rapidAdvertisements = Array(repeating: AdvertisementService.AdvertisementData(
            publicKey: testContact.publicKey,
            timestamp: Date(),
            messageType: .direct,
            floodScope: .none
        ), count: 10)

        // When
        for advertisement in rapidAdvertisements {
            try await advertisementService.sendAdvertisement(data: advertisement)
        }

        // Then
        // TODO: Validate that frequency limiting is respected
        // TODO: Validate rate limiting behavior per MeshCore specification
        XCTFail("TODO: Implement advertisement frequency limiting validation")
    }

    // MARK: - Advertisement Cache Tests

    func testAdvertisementCache_DuplicateSuppression() async throws {
        // Test that duplicate advertisements are suppressed within cache window

        // Given
        let duplicateAdvertisement = AdvertisementService.AdvertisementData(
            publicKey: testContact.publicKey,
            timestamp: Date(),
            messageType: .direct,
            floodScope: .none
        )

        // When - Send same advertisement multiple times quickly
        try await advertisementService.sendAdvertisement(data: duplicateAdvertisement)
        try await advertisementService.sendAdvertisement(data: duplicateAdvertisement)
        try await advertisementService.sendAdvertisement(data: duplicateAdvertisement)

        // Then
        // TODO: Validate that duplicates are suppressed within cache window
        // TODO: Validate cache TTL and cleanup behavior
        XCTFail("TODO: Implement advertisement cache and duplicate suppression validation")
    }

    // MARK: - MeshCore Protocol Compliance Tests

    func testAdvertisementProtocol_SpecCompliance() async throws {
        // Test that AdvertisementService follows MeshCore specification exactly
        // This test documents current violations and required fixes

        // TODO: Validate that AdvertisementService:
        // 1. Uses correct advertisement payload format
        // 2. Implements proper contact data structures (enum values, string encoding)
        // 3. Handles path data correctly
        // 4. Follows MeshCore timing and frequency requirements

        XCTFail("TODO: Implement comprehensive MeshCore specification compliance validation")
    }

    // MARK: - Performance Tests

    func testAdvertisementPerformance_HighVolume() async throws {
        // Test AdvertisementService performance under high advertisement volume

        // Given
        let highVolumeCount = 1000
        let startTime = Date()

        // When
        for i in 0..<highVolumeCount {
            let advertisementData = AdvertisementService.AdvertisementData(
                publicKey: testContact.publicKey,
                timestamp: Date(),
                messageType: .direct,
                floodScope: .local
            )

            try await advertisementService.sendAdvertisement(data: advertisementData)
        }

        let duration = Date().timeIntervalSince(startTime)

        // Then - Should handle high volume efficiently
        XCTAssertLessThan(duration, 30.0) // Should complete within 30 seconds
        XCTAssertLessThan(duration / Double(highVolumeCount), 0.1) // Average < 100ms per advertisement
    }

    func testContactSyncPerformance_LargeContactList() async throws {
        // Test contact sync performance with large contact lists

        // Given
        let largeContactList = (0..<500).map { i in
            try! TestDataFactory.createTestContact(id: "contact_\(i)")
        }

        let startTime = Date()

        // When
        try await advertisementService.syncContacts(largeContactList)

        let duration = Date().timeIntervalSince(startTime)

        // Then - Should sync large lists efficiently
        XCTAssertLessThan(duration, 10.0) // Should complete within 10 seconds

        // Validate all contacts were saved
        let finalCount = try modelContext.fetchCount(FetchDescriptor<Contact>())
        XCTAssertGreaterThanOrEqual(finalCount, 500)
    }
}