import Testing
import Foundation
@testable import MC1Services
@testable import MeshCore

/// Thread-safe recorder for sleep durations in throttling tests.
private actor SleepRecorder {
    var durations: [Duration] = []

    func record(_ duration: Duration) {
        durations.append(duration)
    }
}

@Suite("MessagePollingService throttling")
struct MessagePollingThrottlingTests {

    // MARK: - Test Infrastructure

    /// Creates a session backed by MockTransport, starts it, and returns all three.
    private func createStartedSession() async throws -> (MeshCoreSession, MockTransport, PersistenceStore) {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 1.0, clientIdentifier: "ThrottlingTests")
        )

        let container = try PersistenceStore.createContainer(inMemory: true)
        let store = PersistenceStore(modelContainer: container)

        // Drive the appStart -> selfInfo handshake
        let startTask = Task { try await session.start() }
        try await waitUntil("appStart command should be sent") {
            await transport.sentData.count >= 1
        }
        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value
        await transport.clearSentData()

        return (session, transport, store)
    }

    /// Feeds `count` V1 contact message responses followed by noMoreMessages,
    /// timed to arrive after each getMessage command is sent.
    private func feedMessages(
        count: Int,
        transport: MockTransport,
        initialSentCount: Int = 0
    ) async throws {
        for i in 0..<count {
            try await waitUntil("getMessage \(i + 1) should be sent") {
                await transport.sentData.count >= initialSentCount + i + 1
            }
            await transport.simulateReceive(makeContactMessageV1Packet(index: i))
        }

        // Wait for the final getMessage then send noMoreMessages
        try await waitUntil("final getMessage should be sent") {
            await transport.sentData.count >= initialSentCount + count + 1
        }
        await transport.simulateReceive(Data([ResponseCode.noMoreMessages.rawValue]))
    }

    // MARK: - Tests

    @Test("zero-delay defaults produce no sleep calls")
    func zeroDelayDefaults() async throws {
        let (session, transport, store) = try await createStartedSession()
        let recorder = SleepRecorder()

        let service = MessagePollingService(
            session: session,
            dataStore: store,
            sleepFor: { duration in await recorder.record(duration) }
        )

        let messageCount = 3
        let feedTask = Task { try await feedMessages(count: messageCount, transport: transport) }

        let count = try await service.pollAllMessages()
        try await feedTask.value

        let sleepCalls = await recorder.durations
        #expect(count == messageCount)
        #expect(sleepCalls.isEmpty, "No sleeps should occur with zero defaults")

        await session.stop()
    }

    @Test("message delay applied after each message")
    func messageDelayApplied() async throws {
        let (session, transport, store) = try await createStartedSession()
        let recorder = SleepRecorder()

        let service = MessagePollingService(
            session: session,
            dataStore: store,
            sleepFor: { duration in await recorder.record(duration) }
        )

        let messageCount = 3
        let feedTask = Task { try await feedMessages(count: messageCount, transport: transport) }

        let count = try await service.pollAllMessages(
            messageDelay: .milliseconds(100)
        )
        try await feedTask.value

        let sleepCalls = await recorder.durations
        #expect(count == messageCount)
        #expect(sleepCalls.count == messageCount, "Should sleep after each of the \(messageCount) messages")
        for call in sleepCalls {
            #expect(call == .milliseconds(100), "Each sleep should be the message delay")
        }

        await session.stop()
    }

    @Test("breathing pause replaces message delay at correct interval")
    func breathingPauseReplacesDelay() async throws {
        let (session, transport, store) = try await createStartedSession()
        let recorder = SleepRecorder()

        let service = MessagePollingService(
            session: session,
            dataStore: store,
            sleepFor: { duration in await recorder.record(duration) }
        )

        // 4 messages with breathing every 2: messages at count 1,3 get messageDelay; count 2,4 get breathingDuration
        let messageCount = 4
        let feedTask = Task { try await feedMessages(count: messageCount, transport: transport) }

        let count = try await service.pollAllMessages(
            messageDelay: .milliseconds(50),
            breathingInterval: 2,
            breathingDuration: .milliseconds(500)
        )
        try await feedTask.value

        let sleepCalls = await recorder.durations
        #expect(count == messageCount)
        #expect(sleepCalls.count == messageCount, "Should sleep after each message")

        // count=1: not multiple of 2 -> messageDelay (50ms)
        #expect(sleepCalls[0] == .milliseconds(50), "Message 1: regular delay")
        // count=2: multiple of 2 -> breathingDuration (500ms)
        #expect(sleepCalls[1] == .milliseconds(500), "Message 2: breathing pause")
        // count=3: not multiple of 2 -> messageDelay (50ms)
        #expect(sleepCalls[2] == .milliseconds(50), "Message 3: regular delay")
        // count=4: multiple of 2 -> breathingDuration (500ms)
        #expect(sleepCalls[3] == .milliseconds(500), "Message 4: breathing pause")

        await session.stop()
    }

    @Test("breathing pause only, no inter-message delay")
    func breathingPauseOnly() async throws {
        let (session, transport, store) = try await createStartedSession()
        let recorder = SleepRecorder()

        let service = MessagePollingService(
            session: session,
            dataStore: store,
            sleepFor: { duration in await recorder.record(duration) }
        )

        // 3 messages, breathing every 3, no messageDelay
        let messageCount = 3
        let feedTask = Task { try await feedMessages(count: messageCount, transport: transport) }

        let count = try await service.pollAllMessages(
            messageDelay: .zero,
            breathingInterval: 3,
            breathingDuration: .milliseconds(300)
        )
        try await feedTask.value

        let sleepCalls = await recorder.durations
        #expect(count == messageCount)
        // count=1: not multiple of 3, delay=.zero -> no sleep
        // count=2: not multiple of 3, delay=.zero -> no sleep
        // count=3: multiple of 3, delay=300ms -> sleep
        #expect(sleepCalls.count == 1, "Only the breathing point should trigger a sleep")
        #expect(sleepCalls[0] == .milliseconds(300))

        await session.stop()
    }

    // MARK: - Binary Packet Helpers

    /// Builds a minimal V1 contact message response packet.
    /// Format: [0x07][pubkey:6][pathLen:1][textType:0][timestamp:4LE][text]
    private func makeContactMessageV1Packet(index: Int) -> Data {
        var data = Data([ResponseCode.contactMessageReceived.rawValue])
        data.append(Data(repeating: UInt8(index & 0xFF), count: 6)) // pubkey prefix
        data.append(0x01) // pathLen
        data.append(0x00) // textType (plain)
        let timestamp = UInt32(1_700_000_000)
        data.append(contentsOf: withUnsafeBytes(of: timestamp.littleEndian) { Data($0) })
        data.append("msg\(index)".data(using: .utf8)!)
        return data
    }

    /// Builds a selfInfo response for session startup handshake.
    private func makeSelfInfoPacket() -> Data {
        var payload = Data([ResponseCode.selfInfo.rawValue])
        payload.append(0x01)  // advType
        payload.append(UInt8(bitPattern: Int8(20)))  // txPower
        payload.append(UInt8(bitPattern: Int8(22)))  // maxTxPower
        payload.append(Data(repeating: 0xAA, count: 32))  // publicKey
        payload.append(contentsOf: withUnsafeBytes(of: Int32(0).littleEndian) { Data($0) })  // lat
        payload.append(contentsOf: withUnsafeBytes(of: Int32(0).littleEndian) { Data($0) })  // lon
        payload.append(0x00)  // multiAcks
        payload.append(0x00)  // adv policy
        payload.append(0x00)  // telemetry mode
        payload.append(0x01)  // manual add
        payload.append(contentsOf: withUnsafeBytes(of: UInt32(910_525).littleEndian) { Data($0) })  // freq
        payload.append(contentsOf: withUnsafeBytes(of: UInt32(62_500).littleEndian) { Data($0) })  // bw
        payload.append(0x07)  // sf
        payload.append(0x05)  // cr
        payload.append("Test".data(using: .utf8)!)
        return payload
    }

    /// Polls until condition is true, or fails after timeout.
    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(5),
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: pollInterval)
        }

        Issue.record("Timed out waiting: \(description)")
        throw MeshCoreError.timeout
    }
}
