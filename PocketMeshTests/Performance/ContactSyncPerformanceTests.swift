import XCTest
import SwiftData
@testable import PocketMesh
@testable import PocketMeshKit

/// Tests contact synchronization performance against CORRECT MeshCore specification
///
/// IMPORTANT: These tests validate against the CORRECT MeshCore specification as implemented
/// in the official Python client, not the current (incorrect) PocketMesh implementation.
/// Tests will FAIL until PocketMesh is fixed to match the specification.
@MainActor
final class ContactSyncPerformanceTests: BaseTestCase {

    var contactSyncPerformanceTester: ContactSyncPerformanceTester!
    var testDevice: Device!

    override func setUp() async throws {
        try await super.setUp()

        // Create test device
        testDevice = try TestDataFactory.createTestDevice()

        // Save to SwiftData context
        modelContext.insert(testDevice)
        try modelContext.save()

        // Initialize contact sync performance tester with mock BLE manager
        contactSyncPerformanceTester = ContactSyncPerformanceTester(
            bleManager: mockBLEManager,
            modelContext: modelContext
        )
    }

    override func tearDown() async throws {
        await contactSyncPerformanceTester.cleanup()
        contactSyncPerformanceTester = nil
        testDevice = nil
        try await super.tearDown()
    }

    // MARK: - Basic Contact Sync Performance Tests

    func testContactSync_SmallList() async throws {
        // Test contact sync performance with small contact list

        // Given
        let contactCount = 10
        let contacts = try createTestContacts(count: contactCount)
        let maxSyncTime: TimeInterval = 2.0

        // When
        let startTime = Date()

        let syncResult = try await contactSyncPerformanceTester.syncContacts(contacts)

        let syncTime = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertTrue(syncResult.success)
        XCTAssertEqual(syncResult.syncedContacts, contactCount)
        XCTAssertLessThan(syncTime, maxSyncTime)

        // Validate contacts were saved correctly
        let savedContacts = try modelContext.fetch(FetchDescriptor<Contact>())
        XCTAssertGreaterThanOrEqual(savedContacts.count, contactCount)

        XCTFail("TODO: Implement contact sync performance measurement for small lists")
    }

    func testContactSync_MediumList() async throws {
        // Test contact sync performance with medium contact list

        // Given
        let contactCount = 100
        let contacts = try createTestContacts(count: contactCount)
        let maxSyncTime: TimeInterval = 5.0

        // When
        let startTime = Date()

        let syncResult = try await contactSyncPerformanceTester.syncContacts(contacts)

        let syncTime = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertTrue(syncResult.success)
        XCTAssertEqual(syncResult.syncedContacts, contactCount)
        XCTAssertLessThan(syncTime, maxSyncTime)

        // Calculate throughput
        let throughput = Double(contactCount) / syncTime
        XCTAssertGreaterThan(throughput, 20) // At least 20 contacts/second

        XCTFail("TODO: Implement contact sync performance measurement for medium lists")
    }

    func testContactSync_LargeList() async throws {
        // Test contact sync performance with large contact list

        // Given
        let contactCount = 1000
        let contacts = try createTestContacts(count: contactCount)
        let maxSyncTime: TimeInterval = 30.0

        // When
        let startTime = Date()

        let syncResult = try await contactSyncPerformanceTester.syncContacts(contacts)

        let syncTime = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertTrue(syncResult.success)
        XCTAssertEqual(syncResult.syncedContacts, contactCount)
        XCTAssertLessThan(syncTime, maxSyncTime)

        // Calculate throughput
        let throughput = Double(contactCount) / syncTime
        XCTAssertGreaterThan(throughput, 33) // At least 33 contacts/second

        // Validate memory usage
        let memoryUsage = getMemoryUsage()
        XCTAssertLessThan(memoryUsage, 100_000_000) // Should not exceed 100MB

        XCTFail("TODO: Implement contact sync performance measurement for large lists")
    }

    // MARK: - Incremental Sync Performance Tests

    func testContactSync_Incremental_NewContacts() async throws {
        // Test incremental sync performance when adding new contacts

        // Given
        let initialContactCount = 100
        let newContactCount = 50
        let initialContacts = try createTestContacts(count: initialContactCount)

        // Initial sync
        let _ = try await contactSyncPerformanceTester.syncContacts(initialContacts)

        let newContacts = try createTestContacts(
            count: newContactCount,
            startIndex: initialContactCount
        )

        // When
        let startTime = Date()

        let incrementalSyncResult = try await contactSyncPerformanceTester.syncContacts(
            newContacts,
            mode: .incremental
        )

        let syncTime = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertTrue(incrementalSyncResult.success)
        XCTAssertEqual(incrementalSyncResult.syncedContacts, newContactCount)
        XCTAssertEqual(incrementalSyncResult.updatedContacts, 0)
        XCTAssertEqual(incrementalSyncResult.removedContacts, 0)

        // Incremental sync should be faster than full sync
        XCTAssertLessThan(syncTime, 5.0)

        // Validate total contact count
        let totalContacts = try modelContext.fetchCount(FetchDescriptor<Contact>())
        XCTAssertEqual(totalContacts, initialContactCount + newContactCount)

        XCTFail("TODO: Implement incremental contact sync for new contacts")
    }

    func testContactSync_Incremental_UpdatedContacts() async throws {
        // Test incremental sync performance when updating existing contacts

        // Given
        let contactCount = 100
        let contacts = try createTestContacts(count: contactCount)

        // Initial sync
        let _ = try await contactSyncPerformanceTester.syncContacts(contacts)

        // Update some contacts
        let updatedContacts = contacts.prefix(20).map { contact in
            let updatedContact = Contact(
                id: contact.id,
                name: "Updated \(contact.name)",
                publicKey: contact.publicKey,
                contactType: contact.contactType,
                approvalStatus: contact.approvalStatus,
                firstSeen: contact.firstSeen,
                lastSeen: Date(),
                pathData: contact.pathData
            )
            return updatedContact
        }

        // When
        let startTime = Date()

        let incrementalSyncResult = try await contactSyncPerformanceTester.syncContacts(
            Array(updatedContacts),
            mode: .incremental
        )

        let syncTime = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertTrue(incrementalSyncResult.success)
        XCTAssertEqual(incrementalSyncResult.updatedContacts, 20)
        XCTAssertEqual(incrementalSyncResult.syncedContacts, 20)
        XCTAssertEqual(incrementalSyncResult.removedContacts, 0)

        // Updates should be fast
        XCTAssertLessThan(syncTime, 2.0)

        // Validate updates were applied
        let fetchDescriptor = FetchDescriptor<Contact>(
            predicate: #Predicate<Contact> { contact in
                contact.name.hasPrefix("Updated")
            }
        )
        let updatedInDB = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(updatedInDB.count, 20)

        XCTFail("TODO: Implement incremental contact sync for updated contacts")
    }

    func testContactSync_Incremental_RemovedContacts() async throws {
        // Test incremental sync performance when removing contacts

        // Given
        let contactCount = 100
        let contacts = try createTestContacts(count: contactCount)

        // Initial sync
        let _ = try await contactSyncPerformanceTester.syncContacts(contacts)

        // Remove some contacts (simulate device contact list changed)
        let remainingContacts = Array(contacts.dropFirst(30))

        // When
        let startTime = Date()

        let incrementalSyncResult = try await contactSyncPerformanceTester.syncContacts(
            remainingContacts,
            mode: .incremental
        )

        let syncTime = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertTrue(incrementalSyncResult.success)
        XCTAssertEqual(incrementalSyncResult.removedContacts, 30)
        XCTAssertEqual(incrementalSyncResult.syncedContacts, remainingContacts.count)

        // Removals should be fast
        XCTAssertLessThan(syncTime, 2.0)

        // Validate contacts were removed
        let totalContacts = try modelContext.fetchCount(FetchDescriptor<Contact>())
        XCTAssertEqual(totalContacts, remainingContacts.count)

        XCTFail("TODO: Implement incremental contact sync for removed contacts")
    }

    // MARK: - MeshCore Protocol Compliance Performance Tests

    func testContactSync_MeshCoreProtocol_Performance() async throws {
        // Test contact sync performance while maintaining MeshCore protocol compliance

        // Given
        let contactCount = 500
        let contacts = try createTestContacts(count: contactCount)

        // Configure performance tester to validate protocol compliance
        await contactSyncPerformanceTester.enableProtocolComplianceValidation()

        // When
        let startTime = Date()

        let syncResult = try await contactSyncPerformanceTester.syncContactsWithComplianceValidation(
            contacts
        )

        let syncTime = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertTrue(syncResult.success)
        XCTAssertTrue(syncResult.protocolCompliant)
        XCTAssertEqual(syncResult.syncedContacts, contactCount)

        // Should maintain good performance even with validation
        XCTAssertLessThan(syncTime, 20.0)

        // Validate specific MeshCore compliance aspects:
        // 1. Contact data structure matches spec
        // 2. String encoding is properly null-terminated
        // 3. Enum values match MeshCore definitions
        XCTAssertTrue(syncResult.contactStructureCompliant)
        XCTAssertTrue(syncResult.stringEncodingCompliant)
        XCTAssertTrue(syncResult.enumValuesCompliant)

        XCTFail("TODO: Implement MeshCore protocol compliance validation during contact sync")
    }

    func testContactSync_MeshCoreProtocol_ContactDataStructure() async throws {
        // Test that contact data structures follow MeshCore specification

        // Given
        let contacts = [
            try createTestContactWithSpec(
                id: "spec_test_1",
                name: "Test Contact 1",
                contactType: .chat,
                publicKey: Data(repeating: 0x01, count: 32)
            ),
            try createTestContactWithSpec(
                id: "spec_test_2",
                name: "Test Contact 2",
                contactType: .companion,
                publicKey: Data(repeating: 0x02, count: 32)
            )
        ]

        // When
        let complianceResult = try await contactSyncPerformanceTester.validateContactDataStructure(
            contacts
        )

        // Then
        XCTAssertTrue(complianceResult.valid)

        // Validate MeshCore contact structure requirements:
        for contact in contacts {
            // Contact type should match MeshCore enum (CHAT=0, COMPANION=1)
            if contact.contactType == .chat {
                XCTAssertEqual(contact.contactType.rawValue, 0)
            } else if contact.contactType == .companion {
                XCTAssertEqual(contact.contactType.rawValue, 1)
            }

            // Public key should be exactly 32 bytes
            XCTAssertEqual(contact.publicKey.count, 32)

            // Name should be properly null-terminated UTF-8
            let nameData = contact.name.data(using: .utf8)!
            XCTAssertTrue(nameData.last == 0 || !nameData.contains(0)) // Either null-terminated or no nulls
        }

        XCTFail("TODO: Implement MeshCore contact data structure validation")
    }

    func testContactSync_MeshCoreProtocol_StringEncoding() async throws {
        // Test that string fields follow MeshCore UTF-8 null-termination specification

        // Given
        let testStrings = [
            "Simple",
            "With spaces",
            "With spéciäl chäräcters",
            String(repeating: "Very long string ", count: 10)
        ]

        var contacts: [Contact] = []
        for (index, testString) in testStrings.enumerated() {
            let contact = try createTestContactWithSpec(
                id: "encoding_test_\(index)",
                name: testString,
                contactType: .chat,
                publicKey: Data(repeating: UInt8(index), count: 32)
            )
            contacts.append(contact)
        }

        // When
        let encodingResult = try await contactSyncPerformanceTester.validateStringEncoding(
            contacts
        )

        // Then
        XCTAssertTrue(encodingResult.valid)

        // Validate each string follows MeshCore specification
        for (index, testString) in testStrings.enumerated() {
            let encodedData = encodingResult.encodedStrings[index]
            let utf8Data = testString.data(using: .utf8)!

            // Should contain valid UTF-8
            XCTAssertNotNil(String(data: encodedData, encoding: .utf8))

            // If null-terminated, should end with null byte
            if encodedData.last == 0 {
                XCTAssertEqual(encodedData.count, utf8Data.count + 1)
                XCTAssertEqual(encodedData.dropLast(), utf8Data)
            } else {
                XCTAssertEqual(encodedData, utf8Data)
            }
        }

        XCTFail("TODO: Implement MeshCore string encoding validation for contact sync")
    }

    // MARK: - Memory Usage Tests

    func testContactSync_MemoryUsage_LargeDataset() async throws {
        // Test memory usage during large contact sync operations

        // Given
        let contactCount = 5000
        let contacts = try createTestContacts(count: contactCount)
        let initialMemory = getMemoryUsage()

        // When
        var peakMemory = initialMemory
        let memorySnapshots: [Double] = []

        // Monitor memory during sync
        let syncTask = Task {
            return try await contactSyncPerformanceTester.syncContacts(contacts)
        }

        // Monitor memory while sync runs
        while !syncTask.isCancelled {
            let currentMemory = getMemoryUsage()
            memorySnapshots.append(currentMemory)
            if currentMemory > peakMemory {
                peakMemory = currentMemory
            }

            try await Task.sleep(nanoseconds: 100_000_000) // 100ms

            if syncTask.isCompleted {
                break
            }
        }

        let syncResult = try await syncTask.value
        let finalMemory = getMemoryUsage()

        // Then
        XCTAssertTrue(syncResult.success)

        let memoryIncrease = peakMemory - initialMemory
        let memoryRetained = finalMemory - initialMemory

        // Memory usage should be reasonable
        XCTAssertLessThan(memoryIncrease, 200_000_000) // Should not exceed 200MB increase
        XCTAssertLessThan(memoryRetained, 50_000_000) // Should retain less than 50MB

        // Memory growth should be linear, not exponential
        let memoryGrowthPerContact = memoryIncrease / Double(contactCount)
        XCTAssertLessThan(memoryGrowthPerContact, 40_000) // Less than 40KB per contact

        XCTFail("TODO: Implement memory usage monitoring for large contact sync operations")
    }

    // MARK: - Concurrent Sync Tests

    func testContactSync_ConcurrentPerformance() async throws {
        // Test concurrent contact sync performance

        // Given
        let contactBatches = 5
        let contactsPerBatch = 200
        let totalContactCount = contactBatches * contactsPerBatch

        let startTime = Date()

        // When
        await withTaskGroup(of: ContactSyncPerformanceTester.SyncResult.self) { group in
            for batchIndex in 0..<contactBatches {
                group.addTask {
                    let batchContacts = try self.createTestContacts(
                        count: contactsPerBatch,
                        startIndex: batchIndex * contactsPerBatch
                    )
                    return try await self.contactSyncPerformanceTester.syncContacts(
                        batchContacts,
                        batchId: batchIndex
                    )
                }
            }

            var allResults: [ContactSyncPerformanceTester.SyncResult] = []
            var totalSyncedContacts = 0

            for await result in group {
                allResults.append(result)
                totalSyncedContacts += result.syncedContacts
            }

            let totalTime = Date().timeIntervalSince(startTime)

            // Then
            XCTAssertEqual(allResults.count, contactBatches)
            XCTAssertEqual(totalSyncedContacts, totalContactCount)

            // All batches should succeed
            for result in allResults {
                XCTAssertTrue(result.success)
            }

            // Concurrent sync should be faster than sequential
            let throughput = Double(totalContactCount) / totalTime
            XCTAssertGreaterThan(throughput, 100) // At least 100 contacts/second concurrent

            // Should complete in reasonable time
            XCTAssertLessThan(totalTime, 20.0)
        }

        XCTFail("TODO: Implement concurrent contact sync performance testing")
    }

    // MARK: - Performance Regression Tests

    func testContactSync_PerformanceRegression() async throws {
        // Test that contact sync performance doesn't regress below baseline

        // Given
        let baselineMetrics = ContactSyncPerformanceTester.BaselineMetrics(
            smallListThroughput: 100, // contacts/second for 10 contacts
            mediumListThroughput: 50, // contacts/second for 100 contacts
            largeListThroughput: 40, // contacts/second for 1000 contacts
            incrementalThroughput: 200 // contacts/second for incremental sync
        )

        // Test small list performance
        let smallContacts = try createTestContacts(count: 10)
        let smallStartTime = Date()
        let smallResult = try await contactSyncPerformanceTester.syncContacts(smallContacts)
        let smallTime = Date().timeIntervalSince(smallStartTime)
        let smallThroughput = Double(smallResult.syncedContacts) / smallTime

        // Test medium list performance
        let mediumContacts = try createTestContacts(count: 100)
        let mediumStartTime = Date()
        let mediumResult = try await contactSyncPerformanceTester.syncContacts(mediumContacts)
        let mediumTime = Date().timeIntervalSince(mediumStartTime)
        let mediumThroughput = Double(mediumResult.syncedContacts) / mediumTime

        // Test large list performance
        let largeContacts = try createTestContacts(count: 1000)
        let largeStartTime = Date()
        let largeResult = try await contactSyncPerformanceTester.syncContacts(largeContacts)
        let largeTime = Date().timeIntervalSince(largeStartTime)
        let largeThroughput = Double(largeResult.syncedContacts) / largeTime

        // Test incremental sync performance
        let _ = try await contactSyncPerformanceTester.syncContacts(largeContacts)
        let incrementalContacts = try createTestContacts(count: 50, startIndex: 1000)
        let incrementalStartTime = Date()
        let incrementalResult = try await contactSyncPerformanceTester.syncContacts(
            incrementalContacts,
            mode: .incremental
        )
        let incrementalTime = Date().timeIntervalSince(incrementalStartTime)
        let incrementalThroughput = Double(incrementalResult.syncedContacts) / incrementalTime

        // Then - Compare against baseline (allow 20% degradation)
        XCTAssertGreaterThanOrEqual(smallThroughput, baselineMetrics.smallListThroughput * 0.8)
        XCTAssertGreaterThanOrEqual(mediumThroughput, baselineMetrics.mediumListThroughput * 0.8)
        XCTAssertGreaterThanOrEqual(largeThroughput, baselineMetrics.largeListThroughput * 0.8)
        XCTAssertGreaterThanOrEqual(incrementalThroughput, baselineMetrics.incrementalThroughput * 0.8)

        XCTFail("TODO: Implement performance regression testing with baseline comparison")
    }

    // MARK: - Helper Methods

    private func createTestContacts(count: Int, startIndex: Int = 0) throws -> [Contact] {
        var contacts: [Contact] = []

        for i in 0..<count {
            let contact = Contact(
                id: "test_contact_\(startIndex + i)",
                name: "Test Contact \(startIndex + i)",
                publicKey: Data(repeating: UInt8((startIndex + i) % 256), count: 32),
                contactType: .chat,
                approvalStatus: .approved,
                firstSeen: Date(),
                lastSeen: Date(),
                pathData: Data([0x01, 0x02, 0x03])
            )
            contacts.append(contact)
        }

        return contacts
    }

    private func createTestContactWithSpec(
        id: String,
        name: String,
        contactType: ContactType,
        publicKey: Data
    ) throws -> Contact {
        return Contact(
            id: id,
            name: name,
            publicKey: publicKey,
            contactType: contactType,
            approvalStatus: .approved,
            firstSeen: Date(),
            lastSeen: Date(),
            pathData: Data()
        )
    }

    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if kerr == KERN_SUCCESS {
            return Double(info.resident_size)
        } else {
            return 0
        }
    }
}

// MARK: - Contact Sync Performance Tester Helper Class

/// Helper class for testing contact synchronization performance
class ContactSyncPerformanceTester {
    private let bleManager: MockBLEManager
    private let modelContext: ModelContext

    struct SyncResult {
        let success: Bool
        let syncedContacts: Int
        let updatedContacts: Int
        let removedContacts: Int
        let syncTime: TimeInterval
        let protocolCompliant: Bool
        let contactStructureCompliant: Bool
        let stringEncodingCompliant: Bool
        let enumValuesCompliant: Bool
    }

    struct ComplianceResult {
        let valid: Bool
        let encodedStrings: [Data]
        let errors: [String]
    }

    struct BaselineMetrics {
        let smallListThroughput: Double
        let mediumListThroughput: Double
        let largeListThroughput: Double
        let incrementalThroughput: Double
    }

    enum SyncMode {
        case full
        case incremental
    }

    init(bleManager: MockBLEManager, modelContext: ModelContext) {
        self.bleManager = bleManager
        self.modelContext = modelContext
    }

    // MARK: - Sync Methods

    func syncContacts(_ contacts: [Contact], mode: SyncMode = .full, batchId: Int? = nil) async throws -> SyncResult {
        // TODO: Implement contact synchronization with performance monitoring
        return SyncResult(
            success: true,
            syncedContacts: contacts.count,
            updatedContacts: 0,
            removedContacts: 0,
            syncTime: 0.0,
            protocolCompliant: true,
            contactStructureCompliant: true,
            stringEncodingCompliant: true,
            enumValuesCompliant: true
        )
    }

    func syncContactsWithComplianceValidation(_ contacts: [Contact]) async throws -> SyncResult {
        // TODO: Implement sync with MeshCore protocol compliance validation
        return SyncResult(
            success: true,
            syncedContacts: contacts.count,
            updatedContacts: 0,
            removedContacts: 0,
            syncTime: 0.0,
            protocolCompliant: true,
            contactStructureCompliant: true,
            stringEncodingCompliant: true,
            enumValuesCompliant: true
        )
    }

    // MARK: - Validation Methods

    func validateContactDataStructure(_ contacts: [Contact]) async throws -> ComplianceResult {
        // TODO: Validate contact data structures against MeshCore specification
        return ComplianceResult(
            valid: true,
            encodedStrings: [],
            errors: []
        )
    }

    func validateStringEncoding(_ contacts: [Contact]) async throws -> ComplianceResult {
        // TODO: Validate string encoding against MeshCore specification
        return ComplianceResult(
            valid: true,
            encodedStrings: [],
            errors: []
        )
    }

    // MARK: - Configuration Methods

    func enableProtocolComplianceValidation() async {
        // TODO: Enable protocol compliance validation during sync
    }

    // MARK: - Cleanup Methods

    func cleanup() async {
        // TODO: Clean up test resources and caches
    }
}