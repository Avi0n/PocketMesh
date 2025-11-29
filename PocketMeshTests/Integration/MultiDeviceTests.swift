import XCTest
import SwiftData
@testable import PocketMesh
@testable import PocketMeshKit

/// Tests multi-device mesh network interactions against CORRECT MeshCore specification
///
/// IMPORTANT: These tests validate against the CORRECT MeshCore specification as implemented
/// in the official Python client, not the current (incorrect) PocketMesh implementation.
/// Tests will FAIL until PocketMesh is fixed to match the specification.
@MainActor
final class MultiDeviceTests: BaseTestCase {

    var multiDeviceTester: MultiDeviceTester!
    var meshNetwork: MeshNetwork!

    override func setUp() async throws {
        try await super.setUp()

        // Initialize multi-device tester
        multiDeviceTester = MultiDeviceTester(
            bleManager: mockBLEManager,
            modelContext: modelContext
        )

        // Create test mesh network
        meshNetwork = try createTestMeshNetwork()
    }

    override func tearDown() async throws {
        await multiDeviceTester.cleanup()
        multiDeviceTester = nil
        meshNetwork = nil
        try await super.tearDown()
    }

    // MARK: - Basic Multi-Device Connectivity Tests

    func testMultiDeviceConnectivity_FullMesh() async throws {
        // Test full mesh connectivity between all devices

        // Given
        let deviceCount = 10
        let devices = meshNetwork.devices.prefix(deviceCount).map { $0 }

        // When - Establish full mesh connectivity
        let connectivityResult = try await multiDeviceTester.establishFullMeshConnectivity(
            devices: Array(devices)
        )

        // Then
        XCTAssertTrue(connectivityResult.success)
        XCTAssertEqual(connectivityResult.connectedDevices, deviceCount)

        // Every device should be able to reach every other device
        for device in devices {
            let reachableDevices = try await multiDeviceTester.getReachableDevices(from: device)
            XCTAssertEqual(reachableDevices.count, deviceCount - 1) // Can reach all except self

            // Verify bi-directional connectivity
            for otherDevice in devices where otherDevice.id != device.id {
                XCTAssertTrue(reachableDevices.contains(otherDevice.id))
            }
        }

        // Validate mesh topology
        let topologyValidation = try await multiDeviceTester.validateMeshTopology(devices: Array(devices))
        XCTAssertTrue(topologyValidation.valid)
        XCTAssertEqual(topologyValidation.totalConnections, deviceCount * (deviceCount - 1) / 2) // Complete graph

        XCTFail("TODO: Implement full mesh connectivity testing")
    }

    func testMultiDeviceConnectivity_LinearTopology() async throws {
        // Test linear topology (device1 -> device2 -> device3 -> ...)

        // Given
        let deviceCount = 8
        let devices = meshNetwork.devices.prefix(deviceCount).map { $0 }

        // When - Establish linear topology
        let topologyResult = try await multiDeviceTester.establishLinearTopology(
            devices: Array(devices)
        )

        // Then
        XCTAssertTrue(topologyResult.success)
        XCTAssertEqual(topologyResult.connectedDevices, deviceCount)

        // Each device should only be connected to its immediate neighbors
        for (index, device) in devices.enumerated() {
            let reachableDevices = try await multiDeviceTester.getReachableDevices(from: device)

            if index == 0 || index == deviceCount - 1 {
                // End devices - only one neighbor
                XCTAssertEqual(reachableDevices.count, 1)
            } else {
                // Middle devices - two neighbors
                XCTAssertEqual(reachableDevices.count, 2)
            }
        }

        // Validate linear topology properties
        let longestPath = try await multiDeviceTester.calculateLongestPath(devices: Array(devices))
        XCTAssertEqual(longestPath.hopCount, deviceCount - 1)

        XCTFail("TODO: Implement linear topology testing")
    }

    func testMultiDeviceConnectivity_StarTopology() async throws {
        // Test star topology (central hub device with all others connected)

        // Given
        let peripheralDeviceCount = 7
        let devices = meshNetwork.devices.prefix(peripheralDeviceCount + 1).map { $0 }
        let centralDevice = devices.first!
        let peripheralDevices = Array(devices.dropFirst())

        // When - Establish star topology
        let topologyResult = try await multiDeviceTester.establishStarTopology(
            centralDevice: centralDevice,
            peripheralDevices: peripheralDevices
        )

        // Then
        XCTAssertTrue(topologyResult.success)
        XCTAssertEqual(topologyResult.connectedDevices, devices.count)

        // Central device should reach all peripherals
        let centralReachable = try await multiDeviceTester.getReachableDevices(from: centralDevice)
        XCTAssertEqual(centralReachable.count, peripheralDeviceCount)

        // Each peripheral should only reach the central device
        for peripheral in peripheralDevices {
            let peripheralReachable = try await multiDeviceTester.getReachableDevices(from: peripheral)
            XCTAssertEqual(peripheralReachable.count, 1)
            XCTAssertTrue(peripheralReachable.contains(centralDevice.id))
        }

        XCTFail("TODO: Implement star topology testing")
    }

    // MARK: - Multi-Device Messaging Tests

    func testMultiDeviceMessaging_BroadcastToAll() async throws {
        // Test broadcasting message to all devices in mesh

        // Given
        let deviceCount = 6
        let devices = Array(meshNetwork.devices.prefix(deviceCount))
        let messageText = "Broadcast to all devices"
        let senderDevice = devices.first!

        // Establish mesh connectivity
        try await multiDeviceTester.establishFullMeshConnectivity(devices: devices)

        // When - Send broadcast message
        let broadcastResult = try await multiDeviceTester.broadcastMessage(
            from: senderDevice,
            text: messageText,
            targetDevices: Array(devices.dropFirst())
        )

        // Then
        XCTAssertTrue(broadcastResult.success)
        XCTAssertEqual(broadcastResult.targetDeviceCount, deviceCount - 1)
        XCTAssertEqual(broadcastResult.deliveredCount, deviceCount - 1)
        XCTAssertEqual(broadcastResult.failedCount, 0)

        // All target devices should have received the message
        for targetDevice in devices.dropFirst() {
            let deviceMessages = try await multiDeviceTester.getMessagesForDevice(targetDevice)
            let broadcastMessage = deviceMessages.first { $0.text == messageText }
            XCTAssertNotNil(broadcastMessage)
            XCTAssertEqual(broadcastMessage?.senderPublicKey, senderDevice.publicKey)
        }

        // Validate broadcast efficiency
        XCTAssertLessThan(broadcastResult.totalTransmissions, deviceCount) // Should use flooding efficiently
        XCTAssertGreaterThan(broadcastResult.deliveryRate, 0.9) // High delivery rate

        XCTFail("TODO: Implement multi-device broadcast messaging testing")
    }

    func testMultiDeviceMessaging_PointToPoint() async throws {
        // Test point-to-point messaging between specific devices

        // Given
        let deviceCount = 8
        let devices = Array(meshNetwork.devices.prefix(deviceCount))
        let sourceDevice = devices[0]
        let targetDevice = devices[4]
        let messageText = "Point-to-point message"

        // Establish mesh connectivity
        try await multiDeviceTester.establishFullMeshConnectivity(devices: devices)

        // When - Send point-to-point message
        let p2pResult = try await multiDeviceTester.sendPointToPointMessage(
            from: sourceDevice,
            to: targetDevice,
            text: messageText
        )

        // Then
        XCTAssertTrue(p2pResult.success)
        XCTAssertEqual(p2pResult.sourceDevice, sourceDevice.id)
        XCTAssertEqual(p2pResult.targetDevice, targetDevice.id)

        // Target device should have received the message
        let targetMessages = try await multiDeviceTester.getMessagesForDevice(targetDevice)
        let receivedMessage = targetMessages.first { $0.text == messageText }
        XCTAssertNotNil(receivedMessage)
        XCTAssertEqual(receivedMessage?.senderPublicKey, sourceDevice.publicKey)
        XCTAssertEqual(receivedMessage?.recipientPublicKey, targetDevice.publicKey)

        // Validate optimal routing was used
        XCTAssertLessThanOrEqual(p2pResult.hopCount, 3) // Should use efficient routing
        XCTAssertLessThan(p2pResult.latency, 2.0) // Should deliver quickly

        // Other devices should not have received the message
        for otherDevice in devices where otherDevice.id != targetDevice.id && otherDevice.id != sourceDevice.id {
            let otherMessages = try await multiDeviceTester.getMessagesForDevice(otherDevice)
            let otherReceived = otherMessages.first { $0.text == messageText }
            XCTAssertNil(otherReceived) // Should not have received
        }

        XCTFail("TODO: Implement point-to-point multi-device messaging testing")
    }

    func testMultiDeviceMessaging_MultiHop() async throws {
        // Test multi-hop messaging through intermediate devices

        // Given
        let hopCount = 4
        let devices = Array(meshNetwork.devices.prefix(hopCount + 1))
        let sourceDevice = devices.first!
        let targetDevice = devices.last!

        // Establish linear topology to force multi-hop
        try await multiDeviceTester.establishLinearTopology(devices: devices)

        let messageText = "Multi-hop message"

        // When - Send multi-hop message
        let multiHopResult = try await multiDeviceTester.sendMultiHopMessage(
            from: sourceDevice,
            to: targetDevice,
            text: messageText
        )

        // Then
        XCTAssertTrue(multiHopResult.success)
        XCTAssertEqual(multiHopResult.hopCount, hopCount)

        // Validate message path
        XCTAssertEqual(multiHopResult.messagePath.count, hopCount + 1) // Including source and target
        XCTAssertEqual(multiHopResult.messagePath.first, sourceDevice.id)
        XCTAssertEqual(multiHopResult.messagePath.last, targetDevice.id)

        // Target device should have received the message
        let targetMessages = try await multiDeviceTester.getMessagesForDevice(targetDevice)
        let receivedMessage = targetMessages.first { $0.text == messageText }
        XCTAssertNotNil(receivedMessage)

        // Validate message was properly forwarded through intermediate devices
        for intermediateDeviceIndex in 1..<hopCount {
            let intermediateDevice = devices[intermediateDeviceIndex]
            let deviceStats = try await multiDeviceTester.getDeviceMessageStats(intermediateDevice)
            XCTAssertGreaterThan(deviceStats.forwardedCount, 0) // Should have forwarded messages
        }

        XCTFail("TODO: Implement multi-hop messaging testing")
    }

    // MARK: - Mesh Network Dynamics Tests

    func testMeshNetwork_DeviceJoining() async throws {
        // Test dynamic device joining to existing mesh network

        // Given
        let initialDeviceCount = 5
        let initialDevices = Array(meshNetwork.devices.prefix(initialDeviceCount))
        let newDevice = meshNetwork.devices[initialDeviceCount]

        // Establish initial mesh
        try await multiDeviceTester.establishFullMeshConnectivity(devices: initialDevices)

        // When - New device joins the mesh
        let joinResult = try await multiDeviceTester.addDeviceToMesh(
            newDevice: newDevice,
            existingDevices: initialDevices
        )

        // Then
        XCTAssertTrue(joinResult.success)

        // New device should be connected to all existing devices
        let newDeviceReachable = try await multiDeviceTester.getReachableDevices(from: newDevice)
        XCTAssertEqual(newDeviceReachable.count, initialDeviceCount)

        // Existing devices should be able to reach the new device
        for existingDevice in initialDevices {
            let existingReachable = try await multiDeviceTester.getReachableDevices(from: existingDevice)
            XCTAssertTrue(existingReachable.contains(newDevice.id))
        }

        // Validate mesh network was updated correctly
        let updatedMesh = try await multiDeviceTester.getMeshNetworkState()
        XCTAssertEqual(updatedMesh.deviceCount, initialDeviceCount + 1)
        XCTAssertEqual(updatedMesh.totalConnections, initialDeviceCount * (initialDeviceCount + 1) / 2)

        XCTFail("TODO: Implement dynamic device joining testing")
    }

    func testMeshNetwork_DeviceLeaving() async throws {
        // Test device leaving from mesh network

        // Given
        let deviceCount = 6
        let devices = Array(meshNetwork.devices.prefix(deviceCount))
        let leavingDevice = devices[2] // Device in middle of list

        // Establish full mesh
        try await multiDeviceTester.establishFullMeshConnectivity(devices: devices)

        // When - Device leaves the mesh
        let leaveResult = try await multiDeviceTester.removeDeviceFromMesh(
            leavingDevice: leavingDevice,
            remainingDevices: devices.filter { $0.id != leavingDevice.id }
        )

        // Then
        XCTAssertTrue(leaveResult.success)

        // Remaining devices should not be able to reach the leaving device
        for remainingDevice in devices where remainingDevice.id != leavingDevice.id {
            let reachableDevices = try await multiDeviceTester.getReachableDevices(from: remainingDevice)
            XCTAssertFalse(reachableDevices.contains(leavingDevice.id))
        }

        // Mesh network should reconfigure to maintain connectivity
        let updatedMesh = try await multiDeviceTester.getMeshNetworkState()
        XCTAssertEqual(updatedMesh.deviceCount, deviceCount - 1)

        // Network should remain connected (mesh should be resilient)
        let connectivityCheck = try await multiDeviceTester.validateMeshConnectivity(
            devices: devices.filter { $0.id != leavingDevice.id }
        )
        XCTAssertTrue(connectivityCheck.connected)

        XCTFail("TODO: Implement dynamic device leaving testing")
    }

    func testMeshNetwork_PartitionHealing() async throws {
        // Test mesh network partition and healing

        // Given
        let deviceCount = 12
        let devices = Array(meshNetwork.devices.prefix(deviceCount))
        let partitionPoint = deviceCount / 2
        let partition1 = Array(devices.prefix(partitionPoint))
        let partition2 = Array(devices.suffix(partitionPoint))

        // Establish initial mesh
        try await multiDeviceTester.establishFullMeshConnectivity(devices: devices)

        // When - Create network partition
        try await multiDeviceTester.createPartition(
            partition1: partition1,
            partition2: partition2
        )

        // Verify partition exists
        let partitionCheck = try await multiDeviceTester.detectPartitions(devices: devices)
        XCTAssertEqual(partitionCheck.partitionCount, 2)

        // Heal the partition
        let healingResult = try await multiDeviceTester.healPartition(
            partition1: partition1,
            partition2: partition2
        )

        // Then
        XCTAssertTrue(healingResult.success)

        // Network should be fully connected again
        let healingCheck = try await multiDeviceTester.validateMeshConnectivity(devices: devices)
        XCTAssertTrue(healingCheck.connected)

        // Validate no partitions remain
        let finalPartitionCheck = try await multiDeviceTester.detectPartitions(devices: devices)
        XCTAssertEqual(finalPartitionCheck.partitionCount, 1)

        // Message delivery should work across former partition boundary
        let crossPartitionMessage = "Healing test message"
        let testResult = try await multiDeviceTester.sendPointToPointMessage(
            from: partition1.first!,
            to: partition2.last!,
            text: crossPartitionMessage
        )
        XCTAssertTrue(testResult.success)

        XCTFail("TODO: Implement mesh network partition and healing testing")
    }

    // MARK: - Load Balancing Tests

    func testLoadBalancing_MessageDistribution() async throws {
        // Test load balancing of message traffic across mesh network

        // Given
        let deviceCount = 8
        let devices = Array(meshNetwork.devices.prefix(deviceCount))
        let messageCount = 100
        let sourceDevice = devices.first!

        // Establish full mesh
        try await multiDeviceTester.establishFullMeshConnectivity(devices: devices)

        // When - Send many messages to distribute load
        let loadBalancingResult = try await multiDeviceTester.distributeMessageLoad(
            source: sourceDevice,
            targetDevices: Array(devices.dropFirst()),
            messageCount: messageCount
        )

        // Then
        XCTAssertTrue(loadBalancingResult.success)
        XCTAssertEqual(loadBalancingResult.totalMessages, messageCount)
        XCTAssertEqual(loadBalancingResult.deliveredMessages, messageCount)

        // Load should be distributed across multiple paths
        XCTAssertGreaterThan(loadBalancingResult.uniquePathsUsed, 1)
        XCTAssertLessThan(loadBalancingResult.maxPathUsage, messageCount * 0.6) // No single path > 60% of traffic

        // Validate no single device is overwhelmed
        for device in devices.dropFirst() {
            let deviceStats = try await multiDeviceTester.getDeviceMessageStats(device)
            XCTAssertLessThanOrEqual(deviceStats.messagesReceived, messageCount / devices.count * 2) // Within reasonable bounds
        }

        // Overall network performance should be good
        XCTAssertLessThan(loadBalancingResult.averageLatency, 1.0) // Average latency < 1 second
        XCTAssertGreaterThan(loadBalancingResult.throughput, 50) // Good throughput

        XCTFail("TODO: Implement message load balancing testing")
    }

    func testLoadBalancing_RouteOptimization() async throws {
        // Test route optimization for balancing network load

        // Given
        let deviceCount = 10
        let devices = Array(meshNetwork.devices.prefix(deviceCount))
        let trafficPattern = "many_to_many" // Many devices sending to many devices

        // Establish mesh with alternative paths
        try await multiDeviceTester.establishMeshWithRedundancy(devices: devices)

        // When - Generate traffic pattern and optimize routes
        let optimizationResult = try await multiDeviceTester.optimizeRoutes(
            devices: devices,
            trafficPattern: trafficPattern
        )

        // Then
        XCTAssertTrue(optimizationResult.success)

        // Route optimization should improve network efficiency
        XCTAssertLessThan(optimizationResult.averageHopCount, 3.0) // Efficient routing
        XCTAssertGreaterThan(optimizationResult.pathDiversity, 2.0) // Multiple paths available

        // Network should handle load well
        let loadTest = try await multiDeviceTester.stressTestNetwork(
            devices: devices,
            duration: 30.0,
            messageRate: 10.0 // messages per second
        )
        XCTAssertTrue(loadTest.success)
        XCTAssertLessThan(loadTest.maxLatency, 2.0) // Reasonable latency under load
        XCTAssertGreaterThan(loadTest.throughput, 80) // Good throughput under load

        XCTFail("TODO: Implement route optimization and load balancing testing")
    }

    // MARK: - Scalability Tests

    func testScalability_LargeMeshNetwork() async throws {
        // Test scalability with large mesh network

        // Given
        let largeDeviceCount = 50
        let largeDevices = Array(meshNetwork.devices.prefix(largeDeviceCount))
        let connectionDensity = 0.3 // 30% connectivity (sparse but connected)

        // When - Create large mesh network
        let scalabilityResult = try await multiDeviceTester.createLargeMeshNetwork(
            devices: largeDevices,
            connectionDensity: connectionDensity
        )

        // Then
        XCTAssertTrue(scalabilityResult.success)
        XCTAssertEqual(scalabilityResult.deviceCount, largeDeviceCount)

        // Network should be connected despite sparse connections
        let connectivityCheck = try await multiDeviceTester.validateMeshConnectivity(devices: largeDevices)
        XCTAssertTrue(connectivityCheck.connected)

        // Average path length should be reasonable (small world property)
        XCTAssertLessThan(scalabilityResult.averagePathLength, 6.0)

        // Network should handle basic operations efficiently
        let performanceTest = try await multiDeviceTester.testBasicOperations(
            devices: largeDevices,
            sampleSize: 20 // Test with sample of devices
        )
        XCTAssertTrue(performanceTest.success)
        XCTAssertLessThan(performanceTest.averageDiscoveryTime, 5.0) // Device discovery < 5 seconds
        XCTAssertLessThan(performanceTest.averageMessageTime, 2.0) // Message delivery < 2 seconds

        // Memory usage should be reasonable for large network
        let memoryUsage = getMemoryUsage()
        XCTAssertLessThan(memoryUsage, 300_000_000) // Should not exceed 300MB

        XCTFail("TODO: Implement large mesh network scalability testing")
    }

    func testScalability_DynamicTopology() async throws {
        // Test scalability with dynamic topology changes

        // Given
        let deviceCount = 30
        let devices = Array(meshNetwork.devices.prefix(deviceCount))

        // Establish initial network
        try await multiDeviceTester.createLargeMeshNetwork(
            devices: devices,
            connectionDensity: 0.4
        )

        // When - Simulate continuous topology changes
        let dynamicResult = try await multiDeviceTester.simulateDynamicTopology(
            devices: devices,
            duration: 60.0, // 1 minute of simulation
            changeFrequency: 5.0 // Change every 5 seconds
        )

        // Then
        XCTAssertTrue(dynamicResult.success)

        // Network should remain connected throughout changes
        XCTAssertGreaterThan(dynamicResult.connectivityUptime, 0.8) // At least 80% uptime
        XCTAssertLessThan(dynamicResult.maxPartitionTime, 10.0) // Partitions heal quickly

        // Message delivery should remain reliable
        XCTAssertGreaterThan(dynamicResult.messageDeliveryRate, 0.9) // At least 90% delivery rate

        // Network should adapt efficiently to changes
        XCTAssertLessThan(dynamicResult.averageConvergenceTime, 5.0) // Quick convergence after changes

        XCTFail("TODO: Implement dynamic topology scalability testing")
    }

    // MARK: - MeshCore Protocol Compliance Tests

    func testMeshCoreProtocol_MultiDeviceCompliance() async throws {
        // Test MeshCore protocol compliance in multi-device scenarios

        // Given
        let deviceCount = 6
        let devices = Array(meshNetwork.devices.prefix(deviceCount))

        // Enable strict protocol compliance monitoring
        await multiDeviceTester.enableProtocolComplianceValidation()

        // Establish mesh with compliance monitoring
        let meshResult = try await multiDeviceTester.establishCompliantMeshNetwork(devices: devices)

        // Then
        XCTAssertTrue(meshResult.success)
        XCTAssertTrue(meshResult.protocolCompliant)

        // Validate all MeshCore protocol aspects in multi-device context:

        // 1. Device discovery and advertisement compliance
        XCTAssertTrue(meshResult.deviceDiscoveryCompliant)
        for device in devices {
            let deviceCompliance = try await multiDeviceTester.getDeviceComplianceReport(device)
            XCTAssertTrue(deviceCompliance.advertisementFormatValid)
            XCTAssertTrue(deviceCompliance.contactStructureValid)
        }

        // 2. Message routing compliance
        XCTAssertTrue(meshResult.routingProtocolCompliant)
        XCTAssertTrue(meshResult.pathDiscoveryCompliant)

        // 3. Multi-hop forwarding compliance
        XCTAssertTrue(meshResult.forwardingCompliant)
        XCTAssertTrue(meshResult.hopLimitCompliant)

        // 4. Broadcast and flooding compliance
        XCTAssertTrue(meshResult.broadcastCompliant)
        XCTAssertTrue(meshResult.floodScopeCompliant)

        // 5. Binary protocol compliance
        XCTAssertTrue(meshResult.binaryProtocolCompliant)

        XCTFail("TODO: implement comprehensive MeshCore protocol compliance testing for multi-device scenarios")
    }

    func testMeshCoreProtocol_SpecificationValidation() async throws {
        // Test strict adherence to MeshCore specification

        // Given
        let deviceCount = 4
        let devices = Array(meshNetwork.devices.prefix(deviceCount))
        let testScenarios = [
            "device_discovery",
            "contact_sync",
            "message_routing",
            "broadcast_protocol",
            "binary_requests"
        ]

        var complianceResults: [String: Bool] = [:]

        // When - Test each specification scenario
        for scenario in testScenarios {
            let scenarioResult = try await multiDeviceTester.validateSpecificationScenario(
                scenario: scenario,
                devices: devices
            )
            complianceResults[scenario] = scenarioResult.compliant
        }

        // Then - All scenarios should be compliant
        for (scenario, compliant) in complianceResults {
            XCTAssertTrue(compliant, "Scenario \(scenario) should be MeshCore compliant")
        }

        // Generate comprehensive compliance report
        let complianceReport = try await multiDeviceTester.generateComplianceReport(devices: devices)
        XCTAssertTrue(complianceReport.overallCompliance)
        XCTAssertEqual(complianceReport.testedScenarios.count, testScenarios.count)

        // Validate specific MeshCore requirements:
        XCTAssertTrue(complianceReport.commandCodeMapping) // Correct command codes
        XCTAssertTrue(complianceReport.payloadFormats) // Correct payload formats
        XCTAssertTrue(complianceReport.encodingStandards) // Proper encoding
        XCTAssertTrue(complianceReport.retryMechanisms) // Spec-compliant retry logic
        XCTAssertTrue(complianceReport.errorHandling) // Proper error handling

        XCTFail("TODO: Implement comprehensive MeshCore specification validation")
    }

    // MARK: - Helper Methods

    private func createTestMeshNetwork() throws -> MeshNetwork {
        // Create test mesh network with multiple devices
        let deviceCount = 50
        var devices: [Device] = []

        for i in 0..<deviceCount {
            let device = try TestDataFactory.createTestDevice(id: "mesh_device_\(i)")
            devices.append(device)
            modelContext.insert(device)
        }

        try modelContext.save()

        return MeshNetwork(devices: devices, connections: [])
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

// MARK: - Multi-Device Tester Helper Class

/// Helper class for testing multi-device mesh network interactions
class MultiDeviceTester {
    private let bleManager: MockBLEManager
    private let modelContext: ModelContext

    struct ConnectivityResult {
        let success: Bool
        let connectedDevices: Int
        let totalConnections: Int
    }

    struct TopologyValidation {
        let valid: Bool
        let totalConnections: Int
        let averageDegree: Double
    }

    struct LongestPath {
        let hopCount: Int
        let path: [String]
    }

    struct BroadcastResult {
        let success: Bool
        let targetDeviceCount: Int
        let deliveredCount: Int
        let failedCount: Int
        let totalTransmissions: Int
        let deliveryRate: Double
    }

    struct PointToPointResult {
        let success: Bool
        let sourceDevice: String
        let targetDevice: String
        let hopCount: Int
        let latency: TimeInterval
    }

    struct MultiHopResult {
        let success: Bool
        let hopCount: Int
        let messagePath: [String]
        let latency: TimeInterval
    }

    struct DeviceJoinResult {
        let success: Bool
        let newConnections: Int
        let integrationTime: TimeInterval
    }

    struct PartitionHealingResult {
        let success: Bool
        let healingTime: TimeInterval
        let newConnections: Int
    }

    struct LoadBalancingResult {
        let success: Bool
        let totalMessages: Int
        let deliveredMessages: Int
        let uniquePathsUsed: Int
        let maxPathUsage: Int
        let averageLatency: TimeInterval
        let throughput: Double
    }

    struct RouteOptimizationResult {
        let success: Bool
        let averageHopCount: Double
        let pathDiversity: Double
        let improvementPercent: Double
    }

    struct StressTestResult {
        let success: Bool
        let totalMessages: Int
        let deliveredMessages: Int
        let maxLatency: TimeInterval
        let throughput: Double
    }

    struct MeshNetworkState {
        let deviceCount: Int
        let totalConnections: Int
        let averagePathLength: Double
    }

    struct PartitionDetection {
        let partitionCount: Int
        let partitions: [[String]]
        let largestPartitionSize: Int
    }

    init(bleManager: MockBLEManager, modelContext: ModelContext) {
        self.bleManager = bleManager
        self.modelContext = modelContext
    }

    // MARK: - Connectivity Methods

    func establishFullMeshConnectivity(devices: [Device]) async throws -> ConnectivityResult {
        // TODO: Establish full mesh connectivity
        return ConnectivityResult(
            success: true,
            connectedDevices: devices.count,
            totalConnections: devices.count * (devices.count - 1) / 2
        )
    }

    func establishLinearTopology(devices: [Device]) async throws -> ConnectivityResult {
        // TODO: Establish linear topology
        return ConnectivityResult(
            success: true,
            connectedDevices: devices.count,
            totalConnections: devices.count - 1
        )
    }

    func establishStarTopology(centralDevice: Device, peripheralDevices: [Device]) async throws -> ConnectivityResult {
        // TODO: Establish star topology
        return ConnectivityResult(
            success: true,
            connectedDevices: peripheralDevices.count + 1,
            totalConnections: peripheralDevices.count
        )
    }

    func getReachableDevices(from device: Device) async throws -> [String] {
        // TODO: Get reachable devices from specified device
        return []
    }

    func validateMeshTopology(devices: [Device]) async throws -> TopologyValidation {
        // TODO: Validate mesh topology
        return TopologyValidation(
            valid: true,
            totalConnections: devices.count * (devices.count - 1) / 2,
            averageDegree: Double(devices.count - 1)
        )
    }

    func calculateLongestPath(devices: [Device]) async throws -> LongestPath {
        // TODO: Calculate longest path in network
        return LongestPath(hopCount: devices.count - 1, path: [])
    }

    // MARK: - Messaging Methods

    func broadcastMessage(
        from sender: Device,
        text: String,
        targetDevices: [Device]
    ) async throws -> BroadcastResult {
        // TODO: Broadcast message to target devices
        return BroadcastResult(
            success: true,
            targetDeviceCount: targetDevices.count,
            deliveredCount: targetDevices.count,
            failedCount: 0,
            totalTransmissions: targetDevices.count,
            deliveryRate: 1.0
        )
    }

    func sendPointToPointMessage(
        from source: Device,
        to target: Device,
        text: String
    ) async throws -> PointToPointResult {
        // TODO: Send point-to-point message
        return PointToPointResult(
            success: true,
            sourceDevice: source.id,
            targetDevice: target.id,
            hopCount: 1,
            latency: 0.1
        )
    }

    func sendMultiHopMessage(
        from source: Device,
        to target: Device,
        text: String
    ) async throws -> MultiHopResult {
        // TODO: Send multi-hop message
        return MultiHopResult(
            success: true,
            hopCount: 3,
            messagePath: [source.id, "intermediate1", "intermediate2", target.id],
            latency: 0.5
        )
    }

    // MARK: - Network Dynamics Methods

    func addDeviceToMesh(newDevice: Device, existingDevices: [Device]) async throws -> DeviceJoinResult {
        // TODO: Add device to existing mesh
        return DeviceJoinResult(
            success: true,
            newConnections: existingDevices.count,
            integrationTime: 2.0
        )
    }

    func removeDeviceFromMesh(leavingDevice: Device, remainingDevices: [Device]) async throws -> Bool {
        // TODO: Remove device from mesh
        return true
    }

    func createPartition(partition1: [Device], partition2: [Device]) async throws {
        // TODO: Create network partition
    }

    func healPartition(partition1: [Device], partition2: [Device]) async throws -> PartitionHealingResult {
        // TODO: Heal network partition
        return PartitionHealingResult(
            success: true,
            healingTime: 5.0,
            newConnections: 1
        )
    }

    // MARK: - Load Balancing Methods

    func distributeMessageLoad(
        source: Device,
        targetDevices: [Device],
        messageCount: Int
    ) async throws -> LoadBalancingResult {
        // TODO: Distribute message load across network
        return LoadBalancingResult(
            success: true,
            totalMessages: messageCount,
            deliveredMessages: messageCount,
            uniquePathsUsed: 5,
            maxPathUsage: messageCount / 3,
            averageLatency: 0.3,
            throughput: 100.0
        )
    }

    func establishMeshWithRedundancy(devices: [Device]) async throws {
        // TODO: Establish mesh with redundant paths
    }

    func optimizeRoutes(devices: [Device], trafficPattern: String) async throws -> RouteOptimizationResult {
        // TODO: Optimize routes for traffic pattern
        return RouteOptimizationResult(
            success: true,
            averageHopCount: 2.5,
            pathDiversity: 3.0,
            improvementPercent: 25.0
        )
    }

    func stressTestNetwork(devices: [Device], duration: TimeInterval, messageRate: Double) async throws -> StressTestResult {
        // TODO: Stress test network
        return StressTestResult(
            success: true,
            totalMessages: Int(duration * messageRate),
            deliveredMessages: Int(duration * messageRate * 0.95),
            maxLatency: 1.5,
            throughput: messageRate * 0.95
        )
    }

    // MARK: - Scalability Methods

    func createLargeMeshNetwork(devices: [Device], connectionDensity: Double) async throws -> ConnectivityResult {
        // TODO: Create large mesh network with specified density
        let expectedConnections = Int(Double(devices.count) * Double(devices.count - 1) * connectionDensity / 2)
        return ConnectivityResult(
            success: true,
            connectedDevices: devices.count,
            totalConnections: expectedConnections
        )
    }

    func validateMeshConnectivity(devices: [Device]) async throws -> ConnectivityResult {
        // TODO: Validate mesh connectivity
        return ConnectivityResult(
            success: true,
            connectedDevices: devices.count,
            totalConnections: devices.count * (devices.count - 1) / 2
        )
    }

    func testBasicOperations(devices: [Device], sampleSize: Int) async throws -> StressTestResult {
        // TODO: Test basic operations on sample of devices
        return StressTestResult(
            success: true,
            totalMessages: sampleSize * 10,
            deliveredMessages: sampleSize * 10,
            maxLatency: 1.0,
            throughput: 50.0
        )
    }

    func simulateDynamicTopology(
        devices: [Device],
        duration: TimeInterval,
        changeFrequency: TimeInterval
    ) async throws -> DynamicTopologyResult {
        // TODO: Simulate dynamic topology changes
        return DynamicTopologyResult(
            success: true,
            connectivityUptime: 0.95,
            maxPartitionTime: 5.0,
            messageDeliveryRate: 0.95,
            averageConvergenceTime: 3.0
        )
    }

    // MARK: - Protocol Compliance Methods

    func enableProtocolComplianceValidation() async {
        // TODO: Enable protocol compliance validation
    }

    func establishCompliantMeshNetwork(devices: [Device]) async throws -> ComplianceResult {
        // TODO: Establish MeshCore-compliant mesh network
        return ComplianceResult(
            success: true,
            protocolCompliant: true,
            deviceDiscoveryCompliant: true,
            routingProtocolCompliant: true,
            pathDiscoveryCompliant: true,
            forwardingCompliant: true,
            hopLimitCompliant: true,
            broadcastCompliant: true,
            floodScopeCompliant: true,
            binaryProtocolCompliant: true
        )
    }

    func getDeviceComplianceReport(_ device: Device) async throws -> DeviceComplianceReport {
        // TODO: Get device compliance report
        return DeviceComplianceReport(
            advertisementFormatValid: true,
            contactStructureValid: true,
            commandHandlingValid: true,
            responseFormatValid: true
        )
    }

    func validateSpecificationScenario(scenario: String, devices: [Device]) async throws -> SpecificationComplianceResult {
        // TODO: Validate specific specification scenario
        return SpecificationComplianceResult(
            compliant: true,
            scenario: scenario,
            violations: []
        )
    }

    func generateComplianceReport(devices: [Device]) async throws -> OverallComplianceReport {
        // TODO: Generate overall compliance report
        return OverallComplianceReport(
            overallCompliance: true,
            testedScenarios: ["device_discovery", "contact_sync", "message_routing", "broadcast_protocol", "binary_requests"],
            commandCodeMapping: true,
            payloadFormats: true,
            encodingStandards: true,
            retryMechanisms: true,
            errorHandling: true
        )
    }

    // MARK: - Data Access Methods

    func getMessagesForDevice(_ device: Device) async throws -> [Message] {
        // TODO: Get messages for device
        return []
    }

    func getDeviceMessageStats(_ device: Device) async throws -> DeviceMessageStats {
        // TODO: Get device message statistics
        return DeviceMessageStats(
            messagesReceived: 10,
            messagesSent: 8,
            forwardedCount: 15
        )
    }

    func getMeshNetworkState() async throws -> MeshNetworkState {
        // TODO: Get current mesh network state
        return MeshNetworkState(
            deviceCount: 10,
            totalConnections: 45,
            averagePathLength: 2.5
        )
    }

    func detectPartitions(devices: [Device]) async throws -> PartitionDetection {
        // TODO: Detect network partitions
        return PartitionDetection(
            partitionCount: 1,
            partitions: [],
            largestPartitionSize: devices.count
        )
    }

    // MARK: - Cleanup Methods

    func cleanup() async {
        // TODO: Clean up test resources and simulations
    }
}

// MARK: - Supporting Types

struct MeshNetwork {
    let devices: [Device]
    let connections: [MeshConnection]
}

struct MeshConnection {
    let sourceDeviceId: String
    let targetDeviceId: String
    let strength: Double
}

struct ComplianceResult {
    let success: Bool
    let protocolCompliant: Bool
    let deviceDiscoveryCompliant: Bool
    let routingProtocolCompliant: Bool
    let pathDiscoveryCompliant: Bool
    let forwardingCompliant: Bool
    let hopLimitCompliant: Bool
    let broadcastCompliant: Bool
    let floodScopeCompliant: Bool
    let binaryProtocolCompliant: Bool
}

struct DeviceComplianceReport {
    let advertisementFormatValid: Bool
    let contactStructureValid: Bool
    let commandHandlingValid: Bool
    let responseFormatValid: Bool
}

struct SpecificationComplianceResult {
    let compliant: Bool
    let scenario: String
    let violations: [String]
}

struct OverallComplianceReport {
    let overallCompliance: Bool
    let testedScenarios: [String]
    let commandCodeMapping: Bool
    let payloadFormats: Bool
    let encodingStandards: Bool
    let retryMechanisms: Bool
    let errorHandling: Bool
}

struct DynamicTopologyResult {
    let success: Bool
    let connectivityUptime: Double
    let maxPartitionTime: TimeInterval
    let messageDeliveryRate: Double
    let averageConvergenceTime: TimeInterval
}

struct DeviceMessageStats {
    let messagesReceived: Int
    let messagesSent: Int
    let forwardedCount: Int
}