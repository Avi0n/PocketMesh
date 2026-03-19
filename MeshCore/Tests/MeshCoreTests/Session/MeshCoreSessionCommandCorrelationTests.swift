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

    @Test("getContact ignores responses for other public keys")
    func getContactIgnoresResponsesForOtherPublicKeys() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MCTst")
        )

        try await startSession(session, transport: transport)

        let requestedKey = Data(repeating: 0x11, count: 32)
        let contactTask = Task {
            try await session.getContact(publicKey: requestedKey)
        }

        try await waitUntil("getContact should be sent") {
            await transport.sentData.count == 2
        }

        await transport.simulateReceive(
            makeContactPacket(publicKey: Data(repeating: 0x22, count: 32), name: "Wrong")
        )
        await transport.simulateReceive(
            makeContactPacket(publicKey: requestedKey, name: "Right")
        )

        let contact = try #require(await contactTask.value)
        #expect(contact.publicKey == requestedKey)
        #expect(contact.advertisedName == "Right")
        await session.stop()
    }

    @Test("importPrivateKey ignores OK responses with payloads")
    func importPrivateKeyIgnoresOKResponsesWithPayloads() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MCTst")
        )

        try await startSession(session, transport: transport)

        let importTask = Task {
            try await session.importPrivateKey(Data(repeating: 0x33, count: 64))
        }

        try await waitUntil("importPrivateKey should be sent") {
            await transport.sentData.count == 2
        }

        await transport.simulateOK(value: 7)

        let error = await #expect(throws: MeshCoreError.self) {
            try await importTask.value
        }
        guard case .timeout? = error else {
            Issue.record("Expected timeout after unrelated OK payload, got \(String(describing: error))")
            await session.stop()
            return
        }

        await session.stop()
    }

    @Test("requestStatus fails fast on device error before messageSent")
    func requestStatusFailsFastOnDeviceErrorBeforeMessageSent() async throws {
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

        let error = await #expect(throws: MeshCoreError.self) {
            try await statusTask.value
        }
        guard case .deviceError(let code)? = error else {
            Issue.record("Expected deviceError for binary status request, got \(String(describing: error))")
            await session.stop()
            return
        }
        #expect(code == 10)
        await session.stop()
    }

    @Test("requestTelemetry fails fast on device error before messageSent")
    func requestTelemetryFailsFastOnDeviceErrorBeforeMessageSent() async throws {
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

        let error = await #expect(throws: MeshCoreError.self) {
            try await telemetryTask.value
        }
        guard case .deviceError(let code)? = error else {
            Issue.record("Expected deviceError for binary telemetry request, got \(String(describing: error))")
            await session.stop()
            return
        }
        #expect(code == 11)
        await session.stop()
    }

    @Test("binary request errors release the serializer for following requests")
    func binaryRequestErrorsReleaseTheSerializer() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MCTst")
        )

        try await startSession(session, transport: transport)

        let firstTarget = Data(repeating: 0x31, count: 32)
        let secondTarget = Data(repeating: 0x42, count: 32)

        let statusTask = Task {
            try await session.requestStatus(from: firstTarget)
        }
        let telemetryTask = Task {
            try await session.requestTelemetry(from: secondTarget)
        }

        try await waitUntil("first binary request should be sent") {
            await transport.sentData.count == 2
        }

        try? await Task.sleep(for: .milliseconds(50))
        #expect(await transport.sentData.count == 2)

        await transport.simulateError(code: 12)

        let statusError = await #expect(throws: MeshCoreError.self) {
            try await statusTask.value
        }
        guard case .deviceError(let firstCode)? = statusError else {
            Issue.record("Expected first binary request to fail with deviceError, got \(String(describing: statusError))")
            await session.stop()
            return
        }
        #expect(firstCode == 12)

        try await waitUntil("second binary request should send after the first one fails") {
            await transport.sentData.count == 3
        }

        await transport.simulateError(code: 13)

        let telemetryError = await #expect(throws: MeshCoreError.self) {
            try await telemetryTask.value
        }
        guard case .deviceError(let secondCode)? = telemetryError else {
            Issue.record("Expected second binary request to fail with deviceError, got \(String(describing: telemetryError))")
            await session.stop()
            return
        }
        #expect(secondCode == 13)
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

private func makeContactPacket(publicKey: Data, name: String) -> Data {
    var packet = Data([ResponseCode.contact.rawValue])
    packet.append(publicKey)
    packet.append(ContactType.chat.rawValue)
    packet.append(ContactFlags().rawValue)
    packet.append(0xFF)
    packet.append(Data(repeating: 0, count: 64))

    let nameBytes = Array(name.utf8.prefix(31))
    packet.append(contentsOf: nameBytes)
    packet.append(0)
    if nameBytes.count < 31 {
        packet.append(Data(repeating: 0, count: 31 - nameBytes.count))
    }

    packet.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: Int32(0).littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: Int32(0).littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
    return packet
}
