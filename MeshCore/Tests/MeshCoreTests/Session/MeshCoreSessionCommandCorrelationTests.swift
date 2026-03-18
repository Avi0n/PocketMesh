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

    @Test("session start ignores unrelated errors until selfInfo arrives")
    func sessionStartIgnoresUnrelatedErrorsUntilSelfInfoArrives() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MCTst")
        )

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateError(code: 99)
        await transport.simulateReceive(makeSelfInfoPacket())

        try await startTask.value
        #expect(await session.currentSelfInfo?.name == "Test")
        await session.stop()
    }

    @Test("getBattery ignores unrelated errors while waiting for a battery response")
    func getBatteryIgnoresUnrelatedErrorsWhileWaitingForBatteryResponse() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MCTst")
        )

        try await startSession(session, transport: transport)

        let batteryTask = Task {
            try await session.getBattery()
        }

        try await waitUntil("getBattery should be sent") {
            await transport.sentData.count == 2
        }

        await transport.simulateError(code: 10)
        await transport.simulateReceive(makeBatteryPacket(level: 4018))

        let battery = try await batteryTask.value
        #expect(battery.level == 4018)
        await session.stop()
    }

    @Test("getSelfTelemetry ignores telemetry for other nodes")
    func getSelfTelemetryIgnoresTelemetryForOtherNodes() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MCTst")
        )

        try await startSession(session, transport: transport)

        let telemetryTask = Task {
            try await session.getSelfTelemetry()
        }

        try await waitUntil("getSelfTelemetry should be sent") {
            await transport.sentData.count == 2
        }

        await transport.simulateReceive(
            makeTelemetryPacket(
                publicKeyPrefix: Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]),
                lppPayload: Data([0x01, 0x67, 0x00, 0xFA])
            )
        )
        await transport.simulateReceive(
            makeTelemetryPacket(
                publicKeyPrefix: Data(repeating: 0x01, count: 6),
                lppPayload: Data([0x01, 0x67, 0x00, 0xF0])
            )
        )

        let response = try await telemetryTask.value
        #expect(response.publicKeyPrefix == Data(repeating: 0x01, count: 6))
        await session.stop()
    }

    @Test("getChannel ignores responses for other channel indexes")
    func getChannelIgnoresResponsesForOtherChannelIndexes() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MCTst")
        )

        try await startSession(session, transport: transport)

        let channelTask = Task {
            try await session.getChannel(index: 3)
        }

        try await waitUntil("getChannel should be sent") {
            await transport.sentData.count == 2
        }

        await transport.simulateReceive(
            makeChannelInfoPacket(index: 9, name: "Wrong", secret: Data(repeating: 0xAA, count: 16))
        )
        await transport.simulateReceive(
            makeChannelInfoPacket(index: 3, name: "Right", secret: Data(repeating: 0xBB, count: 16))
        )

        let channel = try await channelTask.value
        #expect(channel.index == 3)
        #expect(channel.name == "Right")
        await session.stop()
    }

    @Test("requestStatus ignores unrelated errors and wrong-node status responses")
    func requestStatusIgnoresUnrelatedErrorsAndWrongNodeResponses() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MCTst")
        )

        try await startSession(session, transport: transport)

        let target = Data(repeating: 0x31, count: 32)
        let statusTask = Task {
            try await session.requestStatus(from: target)
        }

        try await waitUntil("requestStatus should be sent") {
            await transport.sentData.count == 2
        }

        await transport.simulateError(code: 10)
        await transport.simulateReceive(makeStatusResponsePacket(publicKeyPrefix: Data(repeating: 0x99, count: 6), battery: 3900))
        await transport.simulateReceive(makeStatusResponsePacket(publicKeyPrefix: Data(repeating: 0x31, count: 6), battery: 4010))

        let response = try await statusTask.value
        #expect(response.publicKeyPrefix == Data(repeating: 0x31, count: 6))
        #expect(response.battery == 4010)
        await session.stop()
    }

    @Test("requestTelemetry ignores unrelated errors and wrong-node telemetry responses")
    func requestTelemetryIgnoresUnrelatedErrorsAndWrongNodeResponses() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MCTst")
        )

        try await startSession(session, transport: transport)

        let target = Data(repeating: 0x31, count: 32)
        let telemetryTask = Task {
            try await session.requestTelemetry(from: target)
        }

        try await waitUntil("requestTelemetry should be sent") {
            await transport.sentData.count == 2
        }

        await transport.simulateError(code: 11)
        await transport.simulateReceive(
            makeTelemetryPacket(
                publicKeyPrefix: Data(repeating: 0x88, count: 6),
                lppPayload: Data([0x01, 0x67, 0x00, 0xFA])
            )
        )
        await transport.simulateReceive(
            makeTelemetryPacket(
                publicKeyPrefix: Data(repeating: 0x31, count: 6),
                lppPayload: Data([0x01, 0x67, 0x00, 0xF0])
            )
        )

        let response = try await telemetryTask.value
        #expect(response.publicKeyPrefix == Data(repeating: 0x31, count: 6))
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

private func makeBatteryPacket(level: UInt16) -> Data {
    var packet = Data([ResponseCode.battery.rawValue])
    packet.append(contentsOf: withUnsafeBytes(of: level.littleEndian) { Array($0) })
    return packet
}

private func makeTelemetryPacket(publicKeyPrefix: Data, lppPayload: Data) -> Data {
    var packet = Data([ResponseCode.telemetryResponse.rawValue])
    packet.append(0x00)
    packet.append(publicKeyPrefix)
    packet.append(lppPayload)
    return packet
}

private func makeStatusResponsePacket(publicKeyPrefix: Data, battery: UInt16) -> Data {
    var packet = Data([ResponseCode.statusResponse.rawValue, 0x00])
    packet.append(publicKeyPrefix)
    packet.append(contentsOf: withUnsafeBytes(of: battery.littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: Int16(-110).littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: Int16(-85).littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: UInt32(100).littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: UInt32(50).littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: UInt32(25).littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: UInt32(3600).littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: UInt32(5).littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: UInt32(10).littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: UInt32(15).littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: UInt32(20).littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: Int16(0).littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
    return packet
}

private func makeChannelInfoPacket(index: UInt8, name: String, secret: Data) -> Data {
    var packet = Data([ResponseCode.channelInfo.rawValue, index])
    let nameBytes = Array(name.utf8.prefix(31))
    packet.append(contentsOf: nameBytes)
    packet.append(0)
    if nameBytes.count < 31 {
        packet.append(Data(repeating: 0, count: 31 - nameBytes.count))
    }
    packet.append(secret)
    return packet
}
