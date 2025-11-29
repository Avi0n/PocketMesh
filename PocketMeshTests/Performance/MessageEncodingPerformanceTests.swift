import XCTest
import SwiftData
@testable import PocketMesh
@testable import PocketMeshKit

/// Tests message encoding performance against CORRECT MeshCore specification
///
/// IMPORTANT: These tests validate against the CORRECT MeshCore specification as implemented
/// in the official Python client, not the current (incorrect) PocketMesh implementation.
/// Tests will FAIL until PocketMesh is fixed to match the specification.
@MainActor
final class MessageEncodingPerformanceTests: BaseTestCase {

    var performanceTester: MessageEncodingPerformanceTester!
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

        // Initialize performance tester with mock BLE manager
        performanceTester = MessageEncodingPerformanceTester(
            bleManager: mockBLEManager,
            modelContext: modelContext
        )
    }

    override func tearDown() async throws {
        await performanceTester.cleanup()
        performanceTester = nil
        testDevice = nil
        testContact = nil
        try await super.tearDown()
    }

    // MARK: - Basic Encoding Performance Tests

    func testMessageEncoding_ShortMessage() async throws {
        // Test encoding performance for short messages

        // Given
        let messageText = "Hello"
        let iterations = 1000
        let maxAverageTime: TimeInterval = 0.001 // 1ms average

        // When
        let results = try await performanceTester.measureEncodingPerformance(
            message: messageText,
            iterations: iterations
        )

        // Then
        XCTAssertEqual(results.iterations, iterations)
        XCTAssertLessThan(results.averageTime, maxAverageTime)
        XCTAssertLessThan(results.totalTime, maxAverageTime * Double(iterations))
        XCTAssertGreaterThan(results.throughput, 1000) // At least 1000 messages/second

        // Validate encoded format matches MeshCore specification
        XCTAssertNotNil(results.encodedData)
        XCTAssertGreaterThan(results.encodedData!.count, 0)

        XCTFail("TODO: Implement message encoding performance measurement for short messages")
    }

    func testMessageEncoding_MediumMessage() async throws {
        // Test encoding performance for medium-length messages

        // Given
        let messageText = String(repeating: "This is a medium length test message. ", count: 10)
        let iterations = 500
        let maxAverageTime: TimeInterval = 0.002 // 2ms average

        // When
        let results = try await performanceTester.measureEncodingPerformance(
            message: messageText,
            iterations: iterations
        )

        // Then
        XCTAssertEqual(results.iterations, iterations)
        XCTAssertLessThan(results.averageTime, maxAverageTime)
        XCTAssertGreaterThan(results.throughput, 500) // At least 500 messages/second

        XCTFail("TODO: Implement message encoding performance measurement for medium messages")
    }

    func testMessageEncoding_LongMessage() async throws {
        // Test encoding performance for long messages

        // Given
        let messageText = String(repeating: "This is a very long message for performance testing. ", count: 100)
        let iterations = 100
        let maxAverageTime: TimeInterval = 0.01 // 10ms average

        // When
        let results = try await performanceTester.measureEncodingPerformance(
            message: messageText,
            iterations: iterations
        )

        // Then
        XCTAssertEqual(results.iterations, iterations)
        XCTAssertLessThan(results.averageTime, maxAverageTime)
        XCTAssertGreaterThan(results.throughput, 100) // At least 100 messages/second

        // Long messages should be properly fragmented according to MeshCore spec
        XCTAssertGreaterThan(results.encodedData!.count, messageText.utf8.count)

        XCTFail("TODO: Implement message encoding performance measurement for long messages with fragmentation")
    }

    // MARK: - Large Dataset Performance Tests

    func testMessageEncoding_LargeDataset_10KMessages() async throws {
        // Test encoding performance with 10,000 messages

        // Given
        let messageCount = 10000
        var messages: [String] = []

        // Generate varied message content
        for i in 0..<messageCount {
            let length = (i % 100) + 1 // Messages from 1 to 100 characters
            let message = String(repeating: "x", count: length)
            messages.append(message)
        }

        let startTime = Date()

        // When
        var totalEncodingTime: TimeInterval = 0
        var encodedMessages: [Data] = []

        for message in messages {
            let encodingStartTime = Date()
            let encodedData = try await performanceTester.encodeMessage(message)
            let encodingTime = Date().timeIntervalSince(encodingStartTime)

            totalEncodingTime += encodingTime
            encodedMessages.append(encodedData)
        }

        let totalTime = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertEqual(encodedMessages.count, messageCount)

        let averageEncodingTime = totalEncodingTime / Double(messageCount)
        let throughput = Double(messageCount) / totalTime

        XCTAssertLessThan(averageEncodingTime, 0.005) // Average < 5ms per message
        XCTAssertGreaterThan(throughput, 1000) // At least 1000 messages/second total throughput
        XCTAssertLessThan(totalTime, 30.0) // Should complete within 30 seconds

        // Validate all encoded messages follow MeshCore format
        for encodedData in encodedMessages {
            XCTAssertTrue(performanceTester.validateMeshCoreFormat(encodedData))
        }

        XCTFail("TODO: Implement large dataset encoding performance test with 10K messages")
    }

    func testMessageEncoding_LargeDataset_100KMessages() async throws {
        // Test encoding performance with 100,000 messages (stress test)

        // Given
        let messageCount = 100000
        let messageTemplates = [
            "Short",
            "Medium length message",
            String(repeating: "Long message for testing encoding performance. ", count: 5)
        ]

        let startTime = Date()

        // When
        var encodedCount = 0
        let batchSize = 1000 // Process in batches to avoid memory issues

        for batchStart in stride(from: 0, to: messageCount, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, messageCount)
            var batchEncoded: [Data] = []

            for i in batchStart..<batchEnd {
                let template = messageTemplates[i % messageTemplates.count]
                let message = "\(template) \(i)"
                let encodedData = try await performanceTester.encodeMessage(message)
                batchEncoded.append(encodedData)
            }

            encodedCount += batchEncoded.count

            // Periodic memory check
            if batchStart % 10000 == 0 {
                let memoryUsage = getMemoryUsage()
                XCTAssertLessThan(memoryUsage, 200_000_000) // Should not exceed 200MB
            }
        }

        let totalTime = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertEqual(encodedCount, messageCount)

        let throughput = Double(messageCount) / totalTime
        XCTAssertGreaterThan(throughput, 2000) // Should handle 2000+ messages/second even at scale
        XCTAssertLessThan(totalTime, 120.0) // Should complete within 2 minutes

        XCTFail("TODO: Implement large dataset encoding performance test with 100K messages")
    }

    // MARK: - MeshCore Specification Compliance Tests

    func testMessageEncoding_MeshCoreFormat_ShortMessage() async throws {
        // Test that encoding follows MeshCore specification for short messages

        // Given
        let messageText = "Hello MeshCore"
        let attempt: UInt8 = 0
        let timestamp: UInt32 = 1234567890

        // When
        let encodedData = try await performanceTester.encodeMessageWithSpec(
            text: messageText,
            attempt: attempt,
            timestamp: timestamp,
            recipientPublicKey: testContact.publicKey
        )

        // Then - Validate exact MeshCore format:
        // [0x02][0x00][attempt:1][timestamp:4][recipient:32][text:UTF8]
        XCTAssertEqual(encodedData.count, 1 + 1 + 1 + 4 + 32 + messageText.utf8.count)

        // Validate header
        XCTAssertEqual(encodedData[0], 0x02) // sendMessage command
        XCTAssertEqual(encodedData[1], 0x00) // Text message type

        // Validate attempt (little-endian)
        XCTAssertEqual(encodedData[2], attempt)

        // Validate timestamp (little-endian)
        let timestampBytes = Array(encodedData[3..<7])
        let decodedTimestamp = timestampBytes.reversed().reduce(UInt32(0)) { result, byte in
            (result << 8) + UInt32(byte)
        }
        XCTAssertEqual(decodedTimestamp, timestamp)

        // Validate recipient public key
        let recipientBytes = Array(encodedData[7..<39])
        XCTAssertEqual(Data(recipientBytes), testContact.publicKey)

        // Validate message text
        let textBytes = Array(encodedData[39...])
        XCTAssertEqual(String(bytes: textBytes, encoding: .utf8), messageText)

        XCTFail("TODO: Implement exact MeshCore format validation for short messages")
    }

    func testMessageEncoding_MeshCoreFormat_LongMessage() async throws {
        // Test that encoding handles long messages with proper fragmentation

        // Given
        let longMessage = String(repeating: "This is a very long message that should be fragmented according to MeshCore specification. ", count: 20)

        // When
        let encodedData = try await performanceTester.encodeMessageWithSpec(
            text: longMessage,
            attempt: 0,
            timestamp: 1234567890,
            recipientPublicKey: testContact.publicKey
        )

        // Then - Validate fragmentation follows MeshCore spec
        // Long messages should be properly fragmented with sequence numbers
        XCTAssertTrue(encodedData.count > 0)

        // TODO: Validate MeshCore fragmentation format
        // - Each fragment should have proper header
        // - Sequence numbers should be consecutive
        // - Reassembly should work correctly

        XCTFail("TODO: Implement MeshCore fragmentation validation for long messages")
    }

    func testMessageEncoding_MeshCoreFormat_CommandMessage() async throws {
        // Test that command messages follow correct MeshCore format

        // Given
        let commandText = "cmd:set_frequency 915.0"
        let attempt: UInt8 = 0
        let timestamp: UInt32 = 1234567890

        // When
        let encodedData = try await performanceTester.encodeCommandMessageWithSpec(
            command: commandText,
            attempt: attempt,
            timestamp: timestamp,
            recipientPublicKey: testContact.publicKey
        )

        // Then - Validate command message format:
        // [0x02][0x01][0x00][attempt:1][timestamp:4][recipient:32][command:UTF8]
        XCTAssertEqual(encodedData.count, 1 + 1 + 1 + 1 + 4 + 32 + commandText.utf8.count)

        // Validate command message type
        XCTAssertEqual(encodedData[0], 0x02) // sendMessage command
        XCTAssertEqual(encodedData[1], 0x01) // Command message type
        XCTAssertEqual(encodedData[2], 0x00) // Reserved byte

        XCTFail("TODO: Implement MeshCore command message format validation")
    }

    // MARK: - Memory Usage Tests

    func testMessageEncoding_MemoryUsage_SingleMessage() async throws {
        // Test memory usage for single message encoding

        // Given
        let messageText = "Memory test message"
        let initialMemory = getMemoryUsage()

        // When
        let encodedData = try await performanceTester.encodeMessage(messageText)
        let peakMemory = getMemoryUsage()

        // Then
        XCTAssertNotNil(encodedData)
        let memoryIncrease = peakMemory - initialMemory
        XCTAssertLessThan(memoryIncrease, 1_000_000) // Should not increase by more than 1MB

        // Clean up
        let finalMemory = getMemoryUsage()
        let memoryAfterCleanup = finalMemory - initialMemory
        XCTAssertLessThan(memoryAfterCleanup, 100_000) // Most memory should be released

        XCTFail("TODO: Implement memory usage tracking for single message encoding")
    }

    func testMessageEncoding_MemoryUsage_BatchProcessing() async throws {
        // Test memory usage for batch message encoding

        // Given
        let messageCount = 1000
        var messages: [String] = []

        for i in 0..<messageCount {
            messages.append("Batch test message \(i)")
        }

        let initialMemory = getMemoryUsage()

        // When
        var encodedMessages: [Data] = []
        var peakMemory = initialMemory

        for message in messages {
            let currentMemory = getMemoryUsage()
            if currentMemory > peakMemory {
                peakMemory = currentMemory
            }

            let encodedData = try await performanceTester.encodeMessage(message)
            encodedMessages.append(encodedData)
        }

        let finalMemory = getMemoryUsage()

        // Then
        XCTAssertEqual(encodedMessages.count, messageCount)

        let totalMemoryIncrease = peakMemory - initialMemory
        XCTAssertLessThan(totalMemoryIncrease, 50_000_000) // Should not exceed 50MB increase

        let memoryRetained = finalMemory - initialMemory
        XCTAssertLessThan(memoryRetained, 10_000_000) // Should retain less than 10MB

        // Clean up
        encodedMessages.removeAll()
        let memoryAfterCleanup = getMemoryUsage()
        let memoryAfterCleanupIncrease = memoryAfterCleanup - initialMemory
        XCTAssertLessThan(memoryAfterCleanupIncrease, 1_000_000) // Most memory should be released

        XCTFail("TODO: Implement memory usage tracking for batch message encoding")
    }

    // MARK: - Concurrent Encoding Tests

    func testMessageEncoding_ConcurrentPerformance() async throws {
        // Test concurrent message encoding performance

        // Given
        let messageCount = 1000
        let concurrentThreads = 10
        let messagesPerThread = messageCount / concurrentThreads

        let startTime = Date()

        // When
        await withTaskGroup(of: [Data].self) { group in
            for threadIndex in 0..<concurrentThreads {
                group.addTask {
                    var threadResults: [Data] = []

                    for messageIndex in 0..<messagesPerThread {
                        let message = "Concurrent test \(threadIndex)-\(messageIndex)"
                        let encodedData = try await self.performanceTester.encodeMessage(message)
                        threadResults.append(encodedData)
                    }

                    return threadResults
                }
            }

            var allEncodedMessages: [Data] = []
            for await threadResults in group {
                allEncodedMessages.append(contentsOf: threadResults)
            }

            let totalTime = Date().timeIntervalSince(startTime)

            // Then
            XCTAssertEqual(allEncodedMessages.count, messageCount)

            let throughput = Double(messageCount) / totalTime
            XCTAssertGreaterThan(throughput, 500) // Should handle 500+ messages/second concurrently
            XCTAssertLessThan(totalTime, 15.0) // Should complete within 15 seconds

            // Validate all encoded messages follow MeshCore format
            for encodedData in allEncodedMessages {
                XCTAssertTrue(performanceTester.validateMeshCoreFormat(encodedData))
            }
        }

        XCTFail("TODO: Implement concurrent message encoding performance test")
    }

    // MARK: - Encoding Optimization Tests

    func testMessageEncoding_Optimization_CachedEncoding() async throws {
        // Test performance improvement with cached encoding for repeated messages

        // Given
        let messageText = "Repeated message for caching test"
        let repetitions = 1000

        // Measure without caching
        let startTimeWithoutCache = Date()
        for _ in 0..<repetitions {
            let _ = try await performanceTester.encodeMessage(messageText, useCache: false)
        }
        let timeWithoutCache = Date().timeIntervalSince(startTimeWithoutCache)

        // Measure with caching
        let startTimeWithCache = Date()
        for _ in 0..<repetitions {
            let _ = try await performanceTester.encodeMessage(messageText, useCache: true)
        }
        let timeWithCache = Date().timeIntervalSince(startTimeWithCache)

        // Then
        let speedupRatio = timeWithoutCache / timeWithCache
        XCTAssertGreaterThan(speedupRatio, 2.0) // Should be at least 2x faster with caching

        XCTFail("TODO: Implement message encoding caching mechanism")
    }

    func testMessageEncoding_Optimization_BatchProcessing() async throws {
        // Test performance improvement with batch processing

        // Given
        let messageCount = 1000
        var messages: [String] = []

        for i in 0..<messageCount {
            messages.append("Batch optimization test \(i)")
        }

        // Measure individual encoding
        let startTimeIndividual = Date()
        var individualResults: [Data] = []
        for message in messages {
            let encodedData = try await performanceTester.encodeMessage(message)
            individualResults.append(encodedData)
        }
        let timeIndividual = Date().timeIntervalSince(startTimeIndividual)

        // Measure batch encoding
        let startTimeBatch = Date()
        let batchResults = try await performanceTester.encodeMessageBatch(messages)
        let timeBatch = Date().timeIntervalSince(startTimeBatch)

        // Then
        XCTAssertEqual(individualResults.count, messageCount)
        XCTAssertEqual(batchResults.count, messageCount)

        let speedupRatio = timeIndividual / timeBatch
        XCTAssertGreaterThan(speedupRatio, 1.5) // Should be at least 1.5x faster with batch processing

        // Results should be identical
        for i in 0..<messageCount {
            XCTAssertEqual(individualResults[i], batchResults[i])
        }

        XCTFail("TODO: Implement batch message encoding optimization")
    }

    // MARK: - Regression Tests

    func testMessageEncoding_PerformanceRegression() async throws {
        // Test that encoding performance doesn't regress below baseline

        // Given
        let baselineMetrics = MessageEncodingPerformanceTester.BaselineMetrics(
            shortMessageAverageTime: 0.0005, // 0.5ms
            mediumMessageAverageTime: 0.0015, // 1.5ms
            longMessageAverageTime: 0.008, // 8ms
            throughput: 2000 // 2000 messages/second
        )

        // When - Measure current performance
        let shortMessageResults = try await performanceTester.measureEncodingPerformance(
            message: "Short",
            iterations: 1000
        )

        let mediumMessageResults = try await performanceTester.measureEncodingPerformance(
            message: String(repeating: "Medium ", count: 20),
            iterations: 500
        )

        let longMessageResults = try await performanceTester.measureEncodingPerformance(
            message: String(repeating: "Long ", count: 100),
            iterations: 100
        )

        // Then - Compare against baseline
        XCTAssertLessThanOrEqual(shortMessageResults.averageTime, baselineMetrics.shortMessageAverageTime * 1.2)
        XCTAssertLessThanOrEqual(mediumMessageResults.averageTime, baselineMetrics.mediumMessageAverageTime * 1.2)
        XCTAssertLessThanOrEqual(longMessageResults.averageTime, baselineMetrics.longMessageAverageTime * 1.2)
        XCTAssertGreaterThanOrEqual(min(shortMessageResults.throughput, mediumMessageResults.throughput), baselineMetrics.throughput * 0.8)

        XCTFail("TODO: Implement performance regression testing with baseline comparison")
    }

    // MARK: - Helper Methods

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

// MARK: - Message Encoding Performance Tester Helper Class

/// Helper class for testing message encoding performance
class MessageEncodingPerformanceTester {
    private let bleManager: MockBLEManager
    private let modelContext: ModelContext

    struct EncodingResults {
        let iterations: Int
        let totalTime: TimeInterval
        let averageTime: TimeInterval
        let throughput: Double // messages per second
        let encodedData: Data?
    }

    struct BaselineMetrics {
        let shortMessageAverageTime: TimeInterval
        let mediumMessageAverageTime: TimeInterval
        let longMessageAverageTime: TimeInterval
        let throughput: Double
    }

    init(bleManager: MockBLEManager, modelContext: ModelContext) {
        self.bleManager = bleManager
        self.modelContext = modelContext
    }

    // MARK: - Encoding Methods

    func encodeMessage(_ text: String, useCache: Bool = false) async throws -> Data {
        // TODO: Implement message encoding according to MeshCore specification
        // Should use proper little-endian encoding for attempt and timestamp
        return Data()
    }

    func encodeMessageWithSpec(
        text: String,
        attempt: UInt8,
        timestamp: UInt32,
        recipientPublicKey: Data
    ) async throws -> Data {
        // TODO: Implement exact MeshCore specification encoding
        return Data()
    }

    func encodeCommandMessageWithSpec(
        command: String,
        attempt: UInt8,
        timestamp: UInt32,
        recipientPublicKey: Data
    ) async throws -> Data {
        // TODO: Implement command message encoding according to MeshCore spec
        return Data()
    }

    func encodeMessageBatch(_ messages: [String]) async throws -> [Data] {
        // TODO: Implement optimized batch encoding
        return []
    }

    // MARK: - Performance Measurement Methods

    func measureEncodingPerformance(message: String, iterations: Int) async throws -> EncodingResults {
        // TODO: Implement performance measurement for encoding
        return EncodingResults(
            iterations: iterations,
            totalTime: 0.0,
            averageTime: 0.0,
            throughput: 0.0,
            encodedData: Data()
        )
    }

    // MARK: - Validation Methods

    func validateMeshCoreFormat(_ data: Data) -> Bool {
        // TODO: Validate that data follows MeshCore specification format
        return true
    }

    // MARK: - Cleanup Methods

    func cleanup() async {
        // TODO: Clean up test resources and caches
    }
}