import Foundation
import Testing
@testable import MeshCore

@Suite("MeshCoreSession request waiting")
struct MeshCoreSessionRequestWaitingTests {
    @Test("waitForEvent returns first matching event after ignoring unrelated events")
    func waitForEventReturnsFirstMatchingEventAfterIgnoringUnrelatedEvents() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(transport: transport)

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value

        let waitTask = Task {
            await session.waitForEvent(matching: { event in
                if case .battery = event { return true }
                return false
            }, timeout: 0.2)
        }

        try? await Task.sleep(for: .milliseconds(20))
        await transport.simulateReceive(makeCurrentTimePacket(timestamp: 1_710_000_000))
        await transport.simulateReceive(makeBatteryPacket(level: 4021))

        let event = await waitTask.value
        guard case .battery(let battery)? = event else {
            Issue.record("Expected battery event, got \(String(describing: event))")
            return
        }

        #expect(battery.level == 4021)
        await session.stop()
    }

    @Test("waitForEvent filter returns matching ok event")
    func waitForEventFilterReturnsMatchingOKEvent() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(transport: transport)

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value

        let waitTask = Task {
            await session.waitForEvent(filter: .ok, timeout: 0.2)
        }

        try? await Task.sleep(for: .milliseconds(20))
        await transport.simulateOK(value: 7)

        let event = await waitTask.value
        guard case .ok(let value)? = event else {
            Issue.record("Expected ok event, got \(String(describing: event))")
            await session.stop()
            return
        }

        #expect(value == 7)
        await session.stop()
    }

    @Test("getBattery returns parsed battery info")
    func getBatteryReturnsParsedBatteryInfo() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(transport: transport)

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value

        let batteryTask = Task {
            try await session.getBattery()
        }

        try await waitUntil("transport should send battery request") {
            await transport.sentData.count >= 2
        }

        await transport.simulateReceive(makeBatteryPacket(level: 4033, usedStorageKB: 22, totalStorageKB: 100))

        let battery = try await batteryTask.value
        #expect(battery.level == 4033)
        #expect(battery.usedStorageKB == 22)
        #expect(battery.totalStorageKB == 100)
        await session.stop()
    }

    @Test("getBattery ignores unrelated error events while waiting for a battery response")
    func getBatteryIgnoresUnrelatedErrorWhileWaitingForBatteryResponse() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MeshCore-Tests")
        )

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value

        let batteryTask = Task {
            try await session.getBattery()
        }

        try await waitUntil("transport should send battery request") {
            await transport.sentData.count >= 2
        }

        await transport.simulateError(code: 99)
        await transport.simulateReceive(makeBatteryPacket(level: 4018))

        let battery = try await batteryTask.value
        #expect(battery.level == 4018)
        await session.stop()
    }

    @Test("setAutoAddConfig should not treat unrelated ok as success")
    func setAutoAddConfigShouldNotTreatUnrelatedOKAsSuccess() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MeshCore-Tests")
        )

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value

        let commandTask = Task {
            try await session.setAutoAddConfig(AutoAddConfig(bitmask: 0x1E, maxHops: 2))
        }

        try await waitUntil("transport should send setAutoAddConfig command") {
            await transport.sentData.count >= 2
        }

        await transport.simulateOK(value: 7)

        await withKnownIssue("setAutoAddConfig currently treats any OK event as success, even when unrelated to the command") {
            let error = await #expect(throws: MeshCoreError.self) {
                try await commandTask.value
            }
            guard case .timeout? = error else {
                Issue.record("Expected timeout, got \(String(describing: error))")
                return
            }
        }

        await session.stop()
    }

    @Test("factoryReset should not treat unrelated ok as success")
    func factoryResetShouldNotTreatUnrelatedOKAsSuccess() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MeshCore-Tests")
        )

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value

        let commandTask = Task {
            try await session.factoryReset()
        }

        try await waitUntil("transport should send factoryReset command") {
            await transport.sentData.count >= 2
        }

        await transport.simulateOK(value: 99)

        await withKnownIssue("sendSimpleCommand currently treats any OK event as success, even when unrelated to the active command") {
            let error = await #expect(throws: MeshCoreError.self) {
                try await commandTask.value
            }
            guard case .timeout? = error else {
                Issue.record("Expected timeout, got \(String(describing: error))")
                return
            }
        }

        await session.stop()
    }

    @Test("getSelfTelemetry should ignore telemetry from another node")
    func getSelfTelemetryShouldIgnoreTelemetryFromAnotherNode() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MeshCore-Tests")
        )

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value

        let telemetryTask = Task {
            try await session.getSelfTelemetry()
        }

        try await waitUntil("transport should send getSelfTelemetry command") {
            await transport.sentData.count >= 2
        }

        await transport.simulateReceive(
            makeTelemetryPacket(
                publicKeyPrefix: Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]),
                lppPayload: Data([0x01, 0x67, 0x00, 0xFA])
            )
        )

        let error = await #expect(throws: MeshCoreError.self) {
            try await telemetryTask.value
        }
        guard case .timeout? = error else {
            Issue.record("Expected timeout, got \(String(describing: error))")
            return
        }

        await session.stop()
    }

    @Test("getCustomVars should ignore unsolicited customVars event")
    func getCustomVarsShouldIgnoreUnsolicitedCustomVarsEvent() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MeshCore-Tests")
        )

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value

        let varsTask = Task {
            try await session.getCustomVars()
        }

        try await waitUntil("transport should send getCustomVars command") {
            await transport.sentData.count >= 2
        }

        await transport.simulateReceive(makeCustomVarsPacket("mode:auto"))

        await withKnownIssue("getCustomVars currently accepts any customVars event, even when it may be unsolicited or unrelated to the active command") {
            let error = await #expect(throws: MeshCoreError.self) {
                try await varsTask.value
            }
            guard case .timeout? = error else {
                Issue.record("Expected timeout, got \(String(describing: error))")
                return
            }
        }

        await session.stop()
    }

    @Test("exportPrivateKey should not treat unrelated disabled as export-disabled result")
    func exportPrivateKeyShouldNotTreatUnrelatedDisabledAsResult() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MeshCore-Tests")
        )

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value

        let exportTask = Task {
            try await session.exportPrivateKey()
        }

        try await waitUntil("transport should send exportPrivateKey command") {
            await transport.sentData.count >= 2
        }

        await transport.simulateReceive(makeDisabledPacket())

        await withKnownIssue("exportPrivateKey currently treats any disabled event as its own export-disabled response") {
            let error = await #expect(throws: MeshCoreError.self) {
                _ = try await exportTask.value
            }
            guard case .timeout? = error else {
                Issue.record("Expected timeout, got \(String(describing: error))")
                return
            }
        }

        await session.stop()
    }

    @Test("getTime should ignore unsolicited currentTime event")
    func getTimeShouldIgnoreUnsolicitedCurrentTimeEvent() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MeshCore-Tests")
        )

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value

        let timeTask = Task {
            try await session.getTime()
        }

        try await waitUntil("transport should send getTime command") {
            await transport.sentData.count >= 2
        }

        await transport.simulateReceive(makeCurrentTimePacket(timestamp: 1_710_000_123))

        await withKnownIssue("getTime currently accepts any currentTime event, even when it may be unsolicited or unrelated to the active command") {
            let error = await #expect(throws: MeshCoreError.self) {
                _ = try await timeTask.value
            }
            guard case .timeout? = error else {
                Issue.record("Expected timeout, got \(String(describing: error))")
                return
            }
        }

        await session.stop()
    }

    @Test("getAutoAddConfig should ignore unsolicited autoAddConfig event")
    func getAutoAddConfigShouldIgnoreUnsolicitedEvent() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MeshCore-Tests")
        )

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value

        let configTask = Task {
            try await session.getAutoAddConfig()
        }

        try await waitUntil("transport should send getAutoAddConfig command") {
            await transport.sentData.count >= 2
        }

        await transport.simulateReceive(makeAutoAddConfigPacket(bitmask: 0x1E, maxHops: 3))

        await withKnownIssue("getAutoAddConfig currently accepts any autoAddConfig event, even when it may be unsolicited or unrelated to the active command") {
            let error = await #expect(throws: MeshCoreError.self) {
                _ = try await configTask.value
            }
            guard case .timeout? = error else {
                Issue.record("Expected timeout, got \(String(describing: error))")
                return
            }
        }

        await session.stop()
    }

    @Test("getStatsCore should ignore unsolicited core stats event")
    func getStatsCoreShouldIgnoreUnsolicitedEvent() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MeshCore-Tests")
        )

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value

        let statsTask = Task {
            try await session.getStatsCore()
        }

        try await waitUntil("transport should send getStatsCore command") {
            await transport.sentData.count >= 2
        }

        await transport.simulateReceive(makeCoreStatsPacket(batteryMV: 3750, uptime: 86_400, errors: 3, queueLength: 5))

        await withKnownIssue("getStatsCore currently accepts any statsCore event, even when it may be unsolicited or unrelated to the active command") {
            let error = await #expect(throws: MeshCoreError.self) {
                _ = try await statsTask.value
            }
            guard case .timeout? = error else {
                Issue.record("Expected timeout, got \(String(describing: error))")
                return
            }
        }

        await session.stop()
    }

    @Test("getStatsRadio should ignore unsolicited radio stats event")
    func getStatsRadioShouldIgnoreUnsolicitedEvent() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MeshCore-Tests")
        )

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value

        let statsTask = Task {
            try await session.getStatsRadio()
        }

        try await waitUntil("transport should send getStatsRadio command") {
            await transport.sentData.count >= 2
        }

        await transport.simulateReceive(makeRadioStatsPacket(noiseFloor: -115, lastRSSI: -90, lastSNRRaw: 28, txAir: 1_000, rxAir: 2_000))

        await withKnownIssue("getStatsRadio currently accepts any statsRadio event, even when it may be unsolicited or unrelated to the active command") {
            let error = await #expect(throws: MeshCoreError.self) {
                _ = try await statsTask.value
            }
            guard case .timeout? = error else {
                Issue.record("Expected timeout, got \(String(describing: error))")
                return
            }
        }

        await session.stop()
    }

    @Test("exportContact should ignore unsolicited contactURI event")
    func exportContactShouldIgnoreUnsolicitedURIEvent() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MeshCore-Tests")
        )

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value

        let exportTask = Task {
            try await session.exportContact()
        }

        try await waitUntil("transport should send exportContact command") {
            await transport.sentData.count >= 2
        }

        await transport.simulateReceive(makeContactURIPacket("meshcore://deadbeef"))

        await withKnownIssue("exportContact currently accepts any contactURI event, even when it may be unsolicited or unrelated to the active command") {
            let error = await #expect(throws: MeshCoreError.self) {
                _ = try await exportTask.value
            }
            guard case .timeout? = error else {
                Issue.record("Expected timeout, got \(String(describing: error))")
                return
            }
        }

        await session.stop()
    }

    @Test("getStatsPackets should ignore unsolicited packet stats event")
    func getStatsPacketsShouldIgnoreUnsolicitedEvent() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MeshCore-Tests")
        )

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value

        let statsTask = Task {
            try await session.getStatsPackets()
        }

        try await waitUntil("transport should send getStatsPackets command") {
            await transport.sentData.count >= 2
        }

        await transport.simulateReceive(makePacketStatsPacket(received: 1000, sent: 500, floodTx: 100, directTx: 400, floodRx: 200, directRx: 800))

        await withKnownIssue("getStatsPackets currently accepts any statsPackets event, even when it may be unsolicited or unrelated to the active command") {
            let error = await #expect(throws: MeshCoreError.self) {
                _ = try await statsTask.value
            }
            guard case .timeout? = error else {
                Issue.record("Expected timeout, got \(String(describing: error))")
                return
            }
        }

        await session.stop()
    }

    @Test("getRepeatFreq should ignore unsolicited allowedRepeatFreq event")
    func getRepeatFreqShouldIgnoreUnsolicitedEvent() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MeshCore-Tests")
        )

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value

        let repeatTask = Task {
            try await session.getRepeatFreq()
        }

        try await waitUntil("transport should send getRepeatFreq command") {
            await transport.sentData.count >= 2
        }

        await transport.simulateReceive(makeAllowedRepeatFreqPacket([FrequencyRange(lowerKHz: 902_000, upperKHz: 928_000)]))

        await withKnownIssue("getRepeatFreq currently accepts any allowedRepeatFreq event, even when it may be unsolicited or unrelated to the active command") {
            let error = await #expect(throws: MeshCoreError.self) {
                _ = try await repeatTask.value
            }
            guard case .timeout? = error else {
                Issue.record("Expected timeout, got \(String(describing: error))")
                return
            }
        }

        await session.stop()
    }

    @Test("getChannel should ignore unsolicited channelInfo event")
    func getChannelShouldIgnoreUnsolicitedChannelInfoEvent() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MeshCore-Tests")
        )

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value

        let channelTask = Task {
            try await session.getChannel(index: 3)
        }

        try await waitUntil("transport should send getChannel command") {
            await transport.sentData.count >= 2
        }

        await transport.simulateReceive(makeChannelInfoPacket(index: 9, name: "Unsolicited", secret: Data(repeating: 0xAA, count: 16)))

        let error = await #expect(throws: MeshCoreError.self) {
            _ = try await channelTask.value
        }
        guard case .timeout? = error else {
            Issue.record("Expected timeout, got \(String(describing: error))")
            return
        }

        await session.stop()
    }

    @Test("companion commands are serialized while a response is pending")
    func companionCommandsAreSerializedWhileAResponseIsPending() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MeshCore-Tests")
        )

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value

        let timeTask = Task {
            try await session.getTime()
        }

        try await waitUntil("transport should send getTime command") {
            await transport.sentData.count >= 2
        }

        let batteryTask = Task {
            try await session.getBattery()
        }

        try await Task.sleep(for: .milliseconds(50))
        #expect(await transport.sentData.count == 2, "getBattery should wait until getTime completes")

        await transport.simulateReceive(makeCurrentTimePacket(timestamp: 1_710_000_123))
        _ = try await timeTask.value

        try await waitUntil("transport should send battery request after getTime completes") {
            await transport.sentData.count >= 3
        }

        await transport.simulateReceive(makeBatteryPacket(level: 4025))
        let battery = try await batteryTask.value
        #expect(battery.level == 4025)

        await session.stop()
    }

    @Test("signStart should ignore unsolicited signStart event")
    func signStartShouldIgnoreUnsolicitedEvent() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MeshCore-Tests")
        )

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value

        let signTask = Task {
            try await session.signStart()
        }

        try await waitUntil("transport should send signStart command") {
            await transport.sentData.count >= 2
        }

        await transport.simulateReceive(makeSignStartPacket(maxLength: 4096))

        await withKnownIssue("signStart currently accepts any signStart event, even when it may be unsolicited or unrelated to the active command") {
            let error = await #expect(throws: MeshCoreError.self) {
                _ = try await signTask.value
            }
            guard case .timeout? = error else {
                Issue.record("Expected timeout, got \(String(describing: error))")
                return
            }
        }

        await session.stop()
    }

    @Test("signFinish should ignore unsolicited signature event")
    func signFinishShouldIgnoreUnsolicitedSignatureEvent() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MeshCore-Tests")
        )

        let startTask = Task {
            try await session.start()
        }

        try await waitUntil("transport should send appStart before session starts") {
            await transport.sentData.count == 1
        }

        await transport.simulateReceive(makeSelfInfoPacket())
        try await startTask.value

        let signTask = Task {
            try await session.signFinish(timeout: 0.2)
        }

        try await waitUntil("transport should send signFinish command") {
            await transport.sentData.count >= 2
        }

        await transport.simulateReceive(makeSignaturePacket(Data(repeating: 0x55, count: 64)))

        await withKnownIssue("signFinish currently accepts any signature event, even when it may be unsolicited or unrelated to the active command") {
            let error = await #expect(throws: MeshCoreError.self) {
                _ = try await signTask.value
            }
            guard case .timeout? = error else {
                Issue.record("Expected timeout, got \(String(describing: error))")
                return
            }
        }

        await session.stop()
    }
}

private func makeBatteryPacket(level: UInt16, usedStorageKB: UInt32? = nil, totalStorageKB: UInt32? = nil) -> Data {
    var packet = Data([ResponseCode.battery.rawValue])
    packet.append(contentsOf: withUnsafeBytes(of: level.littleEndian) { Array($0) })

    if let usedStorageKB, let totalStorageKB {
        packet.append(contentsOf: withUnsafeBytes(of: usedStorageKB.littleEndian) { Array($0) })
        packet.append(contentsOf: withUnsafeBytes(of: totalStorageKB.littleEndian) { Array($0) })
    }

    return packet
}

private func makeCurrentTimePacket(timestamp: UInt32) -> Data {
    var packet = Data([ResponseCode.currentTime.rawValue])
    packet.append(contentsOf: withUnsafeBytes(of: timestamp.littleEndian) { Array($0) })
    return packet
}

private func makeTelemetryPacket(publicKeyPrefix: Data, lppPayload: Data) -> Data {
    var packet = Data([ResponseCode.telemetryResponse.rawValue])
    packet.append(0x00)
    packet.append(publicKeyPrefix)
    packet.append(lppPayload)
    return packet
}

private func makeCustomVarsPacket(_ string: String) -> Data {
    var packet = Data([ResponseCode.customVars.rawValue])
    packet.append(contentsOf: string.utf8)
    return packet
}

private func makeDisabledPacket() -> Data {
    Data([ResponseCode.disabled.rawValue])
}

private func makeAutoAddConfigPacket(bitmask: UInt8, maxHops: UInt8) -> Data {
    Data([ResponseCode.autoAddConfig.rawValue, bitmask, maxHops])
}

private func makeCoreStatsPacket(batteryMV: UInt16, uptime: UInt32, errors: UInt16, queueLength: UInt8) -> Data {
    var packet = Data([ResponseCode.stats.rawValue, StatsType.core.rawValue])
    packet.append(contentsOf: withUnsafeBytes(of: batteryMV.littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: uptime.littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: errors.littleEndian) { Array($0) })
    packet.append(queueLength)
    return packet
}

private func makeRadioStatsPacket(
    noiseFloor: Int16,
    lastRSSI: Int8,
    lastSNRRaw: Int8,
    txAir: UInt32,
    rxAir: UInt32
) -> Data {
    var packet = Data([ResponseCode.stats.rawValue, StatsType.radio.rawValue])
    packet.append(contentsOf: withUnsafeBytes(of: noiseFloor.littleEndian) { Array($0) })
    packet.append(UInt8(bitPattern: lastRSSI))
    packet.append(UInt8(bitPattern: lastSNRRaw))
    packet.append(contentsOf: withUnsafeBytes(of: txAir.littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: rxAir.littleEndian) { Array($0) })
    return packet
}

private func makeContactURIPacket(_ uri: String) -> Data {
    let hex = uri.replacingOccurrences(of: "meshcore://", with: "")
    var packet = Data([ResponseCode.contactURI.rawValue])
    packet.append(hexDecodedBytes(hex))
    return packet
}

private func makePacketStatsPacket(
    received: UInt32,
    sent: UInt32,
    floodTx: UInt32,
    directTx: UInt32,
    floodRx: UInt32,
    directRx: UInt32
) -> Data {
    var packet = Data([ResponseCode.stats.rawValue, StatsType.packets.rawValue])
    packet.append(contentsOf: withUnsafeBytes(of: received.littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: sent.littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: floodTx.littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: directTx.littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: floodRx.littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: directRx.littleEndian) { Array($0) })
    return packet
}

private func makeAllowedRepeatFreqPacket(_ ranges: [FrequencyRange]) -> Data {
    var packet = Data([ResponseCode.allowedRepeatFreq.rawValue])
    for range in ranges {
        packet.append(contentsOf: withUnsafeBytes(of: range.lowerKHz.littleEndian) { Array($0) })
        packet.append(contentsOf: withUnsafeBytes(of: range.upperKHz.littleEndian) { Array($0) })
    }
    return packet
}

private func makeChannelInfoPacket(index: UInt8, name: String, secret: Data) -> Data {
    var packet = Data([ResponseCode.channelInfo.rawValue, index])
    let nameBytes = Data(name.utf8).prefix(32)
    packet.append(nameBytes)
    if nameBytes.count < 32 {
        packet.append(Data(repeating: 0, count: 32 - nameBytes.count))
    }
    packet.append(secret.prefix(16))
    if secret.count < 16 {
        packet.append(Data(repeating: 0, count: 16 - secret.count))
    }
    return packet
}

private func makeSignStartPacket(maxLength: UInt32) -> Data {
    var packet = Data([ResponseCode.signStart.rawValue, 0x00])
    packet.append(contentsOf: withUnsafeBytes(of: maxLength.littleEndian) { Array($0) })
    return packet
}

private func makeSignaturePacket(_ signature: Data) -> Data {
    var packet = Data([ResponseCode.signature.rawValue])
    packet.append(signature)
    return packet
}

private func makeSelfInfoPacket() -> Data {
    var payload = Data()
    payload.append(1)
    payload.append(22)
    payload.append(22)
    payload.append(Data(repeating: 0x01, count: 32))
    payload.append(int32Bytes(0))
    payload.append(int32Bytes(0))
    payload.append(0)
    payload.append(0)
    payload.append(0)
    payload.append(0)
    payload.append(1)
    payload.append(uint32Bytes(915_000))
    payload.append(uint32Bytes(125_000))
    payload.append(7)
    payload.append(5)
    payload.append(contentsOf: "Test".utf8)

    var packet = Data([ResponseCode.selfInfo.rawValue])
    packet.append(payload)
    return packet
}

private func int32Bytes(_ value: Int32) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}

private func uint32Bytes(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}

private func hexDecodedBytes(_ hex: String) -> Data {
    var data = Data()
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        let byteString = hex[index..<next]
        data.append(UInt8(byteString, radix: 16) ?? 0)
        index = next
    }
    return data
}
