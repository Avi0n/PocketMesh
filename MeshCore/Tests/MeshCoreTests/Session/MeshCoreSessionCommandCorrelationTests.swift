import Foundation
import Testing
@testable import MeshCore

@Suite("MeshCoreSession command correlation")
struct MeshCoreSessionCommandCorrelationTests {
    @Test("simple commands serialize concurrent OK/ERROR waits")
    func simpleCommandsSerializeConcurrentOKWaits() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MCTst")
        )

        try await startSession(session, transport: transport)

        let first = Task {
            try await session.factoryReset()
        }
        let second = Task {
            try await session.sendAdvertisement(flood: true)
        }

        try await waitUntil("first command should be sent") {
            await transport.sentData.count == 2
        }

        try? await Task.sleep(for: .milliseconds(50))
        #expect(await transport.sentData.count == 2)

        await transport.simulateOK()

        try await waitUntil("second command should wait for the first command to complete") {
            await transport.sentData.count == 3
        }

        await transport.simulateOK()

        try await first.value
        try await second.value
        await session.stop()
    }

    @Test("simple commands ignore OK responses with payloads")
    func simpleCommandsIgnoreOKResponsesWithPayloads() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MCTst")
        )

        try await startSession(session, transport: transport)

        let resetTask = Task {
            try await session.factoryReset()
        }

        try await waitUntil("factoryReset should be sent") {
            await transport.sentData.count == 2
        }

        await transport.simulateOK(value: 7)

        let error = await #expect(throws: MeshCoreError.self) {
            try await resetTask.value
        }
        guard case .timeout? = error else {
            Issue.record("Expected timeout after unrelated OK payload, got \(String(describing: error))")
            await session.stop()
            return
        }

        await session.stop()
    }

    @Test("simple commands still fail on device errors")
    func simpleCommandsStillFailOnDeviceErrors() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MCTst")
        )

        try await startSession(session, transport: transport)

        let commandTask = Task {
            try await session.setAutoAddConfig(AutoAddConfig(bitmask: 0x1E, maxHops: 2))
        }

        try await waitUntil("setAutoAddConfig should be sent") {
            await transport.sentData.count == 2
        }

        await transport.simulateError(code: 42)

        let error = await #expect(throws: MeshCoreError.self) {
            try await commandTask.value
        }
        guard case .deviceError(let code)? = error else {
            Issue.record("Expected deviceError, got \(String(describing: error))")
            await session.stop()
            return
        }
        #expect(code == 42)

        await session.stop()
    }
}

private func startSession(
    _ session: MeshCoreSession,
    transport: MockTransport
) async throws {
    let startTask = Task {
        try await session.start()
    }

    try await waitUntil("transport should send appStart before session starts") {
        await transport.sentData.count == 1
    }

    await transport.simulateReceive(makeSelfInfoPacket())
    try await startTask.value
}

private func makeSelfInfoPacket() -> Data {
    var payload = Data()
    payload.append(1)
    payload.append(UInt8(bitPattern: 22))
    payload.append(UInt8(bitPattern: 22))
    payload.append(Data(repeating: 0x01, count: 32))
    payload.append(contentsOf: withUnsafeBytes(of: Int32(0).littleEndian) { Array($0) })
    payload.append(contentsOf: withUnsafeBytes(of: Int32(0).littleEndian) { Array($0) })
    payload.append(0)
    payload.append(0)
    payload.append(0)
    payload.append(0)
    payload.append(contentsOf: withUnsafeBytes(of: UInt32(915_000).littleEndian) { Array($0) })
    payload.append(contentsOf: withUnsafeBytes(of: UInt32(125_000).littleEndian) { Array($0) })
    payload.append(7)
    payload.append(5)
    payload.append(contentsOf: "Test".utf8)

    var packet = Data([ResponseCode.selfInfo.rawValue])
    packet.append(payload)
    return packet
}
