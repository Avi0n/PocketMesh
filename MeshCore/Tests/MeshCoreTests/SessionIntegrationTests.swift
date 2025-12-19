import Foundation
import Testing
@testable import MeshCore

@Suite("Session Integration Tests", .serialized)
struct SessionIntegrationTests {

    // MARK: - Session Lifecycle

    @Test("Session start initializes and receives selfInfo")
    func sessionStartReceivesSelfInfo() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(transport: transport)

        async let startTask: () = session.start()
        try await Task.sleep(for: .milliseconds(50))
        await transport.simulateReceive(makeSelfInfoResponse())
        try await startTask

        let sentData = await transport.sentData
        #expect(sentData.count == 1)
        #expect(sentData[0].first == CommandCode.appStart.rawValue)
    }

    @Test("Session stop disconnects cleanly")
    func sessionStopDisconnects() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(transport: transport)

        async let startTask: () = session.start()
        try await Task.sleep(for: .milliseconds(50))
        await transport.simulateReceive(makeSelfInfoResponse())
        try await startTask

        await session.stop()

        let isConnected = await transport.isConnected
        #expect(isConnected == false)
    }

    // MARK: - Device Queries

    @Test("queryDevice returns device capabilities")
    func queryDeviceReturnsCapabilities() async throws {
        let (session, transport) = try await makeStartedSession()

        async let queryTask = session.queryDevice()
        try await Task.sleep(for: .milliseconds(50))

        var response = Data([ResponseCode.deviceInfo.rawValue])
        response.append(TestFixtures.deviceInfoV3Payload)
        await transport.simulateReceive(response)

        let capabilities = try await queryTask

        #expect(capabilities.firmwareVersion == 3)
        #expect(capabilities.maxChannels == 8)
        #expect(capabilities.model == "T-Echo")
    }

    @Test("getBattery returns battery info")
    func getBatteryReturnsBatteryInfo() async throws {
        let (session, transport) = try await makeStartedSession()

        async let batteryTask = session.getBattery()
        try await Task.sleep(for: .milliseconds(50))

        var response = Data([ResponseCode.battery.rawValue])
        response.append(TestFixtures.batteryExtendedPayload)
        await transport.simulateReceive(response)

        let battery = try await batteryTask

        #expect(battery.level == 4200)
        #expect(battery.usedStorageKB == 1024)
        #expect(battery.totalStorageKB == 4096)
    }

    // MARK: - Contact Management

    @Test("getContacts returns contact list")
    func getContactsReturnsContactList() async throws {
        let (session, transport) = try await makeStartedSession()

        async let contactsTask = session.getContacts()
        try await Task.sleep(for: .milliseconds(50))

        await transport.simulateReceive(Data([ResponseCode.contactStart.rawValue, 0x01]))

        var contactResponse = Data([ResponseCode.contact.rawValue])
        contactResponse.append(TestFixtures.validContactPayload)
        await transport.simulateReceive(contactResponse)

        var endResponse = Data([ResponseCode.contactEnd.rawValue])
        endResponse.append(contentsOf: withUnsafeBytes(of: UInt32(1700000100).littleEndian) { Array($0) })
        await transport.simulateReceive(endResponse)

        let contacts = try await contactsTask

        #expect(contacts.count == 1)
        #expect(contacts[0].advertisedName == "TestNode")
        #expect(abs(contacts[0].latitude - 37.7749) < 0.0001)
    }

    @Test("Contact lookup by name works")
    func contactLookupByName() async throws {
        let (session, transport) = try await makeStartedSession()

        async let contactsTask: [MeshContact] = session.getContacts()
        try await Task.sleep(for: .milliseconds(50))

        await transport.simulateReceive(Data([ResponseCode.contactStart.rawValue, 0x01]))
        var contactResponse = Data([ResponseCode.contact.rawValue])
        contactResponse.append(TestFixtures.validContactPayload)
        await transport.simulateReceive(contactResponse)
        var endResponse = Data([ResponseCode.contactEnd.rawValue])
        endResponse.append(contentsOf: withUnsafeBytes(of: UInt32(1700000100).littleEndian) { Array($0) })
        await transport.simulateReceive(endResponse)
        _ = try await contactsTask

        let contact = await session.getContactByName("test", exactMatch: false)
        #expect(contact?.advertisedName == "TestNode")

        let exactMatch = await session.getContactByName("testnode", exactMatch: true)
        #expect(exactMatch?.advertisedName == "TestNode")

        let noMatch = await session.getContactByName("nonexistent", exactMatch: false)
        #expect(noMatch == nil)
    }

    // MARK: - Messaging

    @Test("sendMessage returns message sent info")
    func sendMessageReturnsSentInfo() async throws {
        let (session, transport) = try await makeStartedSession()

        let destination = Data(repeating: 0xAB, count: 6)

        async let sendTask = session.sendMessage(to: destination, text: "Hello")
        try await Task.sleep(for: .milliseconds(50))

        var response = Data([ResponseCode.messageSent.rawValue])
        response.append(TestFixtures.messageSentPayload)
        await transport.simulateReceive(response)

        let info = try await sendTask

        #expect(info.type == 0x00)
        #expect(info.suggestedTimeoutMs == 5000)
    }

    @Test("getMessage returns contact message")
    func getMessageReturnsContactMessage() async throws {
        let (session, transport) = try await makeStartedSession()

        async let msgTask = session.getMessage()
        try await Task.sleep(for: .milliseconds(50))

        var response = Data([ResponseCode.contactMessageReceived.rawValue])
        response.append(TestFixtures.contactMessageV1Payload)
        await transport.simulateReceive(response)

        let result = try await msgTask

        if case .contactMessage(let msg) = result {
            #expect(msg.text == "Hello")
            #expect(msg.pathLength == 1)
        } else {
            Issue.record("Expected contactMessage result")
        }
    }

    @Test("getMessage returns no more messages")
    func getMessageReturnsNoMore() async throws {
        let (session, transport) = try await makeStartedSession()

        async let msgTask = session.getMessage()
        try await Task.sleep(for: .milliseconds(50))

        await transport.simulateReceive(Data([ResponseCode.noMoreMessages.rawValue]))

        let result = try await msgTask

        guard case .noMoreMessages = result else {
            Issue.record("Expected noMoreMessages result")
            return
        }
    }

    // MARK: - Channels

    @Test("getChannel returns channel info")
    func getChannelReturnsInfo() async throws {
        let (session, transport) = try await makeStartedSession()

        async let channelTask = session.getChannel(index: 1)
        try await Task.sleep(for: .milliseconds(50))

        var response = Data([ResponseCode.channelInfo.rawValue])
        response.append(TestFixtures.channelInfoPayload)
        await transport.simulateReceive(response)

        let info = try await channelTask

        #expect(info.index == 1)
        #expect(info.name == "TestChannel")
        #expect(info.secret.count == 16)
    }

    @Test("setChannel sends correct command")
    func setChannelSendsCommand() async throws {
        let (session, transport) = try await makeStartedSession()
        await transport.clearSentData()

        async let setTask: () = session.setChannel(index: 2, name: "NewChannel", secret: .deriveFromName)
        try await Task.sleep(for: .milliseconds(50))
        await transport.simulateOK()
        try await setTask

        let sentData = await transport.sentData
        #expect(sentData.count == 1)
        #expect(sentData[0].first == CommandCode.setChannel.rawValue)
    }

    // MARK: - Stats

    @Test("getStatsCore returns core statistics")
    func getStatsCoreReturnsStats() async throws {
        let (session, transport) = try await makeStartedSession()

        async let statsTask = session.getStatsCore()
        try await Task.sleep(for: .milliseconds(50))

        var response = Data([ResponseCode.stats.rawValue, StatsType.core.rawValue])
        response.append(TestFixtures.coreStatsPayload)
        await transport.simulateReceive(response)

        let stats = try await statsTask

        #expect(stats.batteryMV == 4200)
        #expect(stats.uptimeSeconds == 3600)
        #expect(stats.queueLength == 3)
    }

    @Test("getStatsRadio returns radio statistics")
    func getStatsRadioReturnsStats() async throws {
        let (session, transport) = try await makeStartedSession()

        async let statsTask = session.getStatsRadio()
        try await Task.sleep(for: .milliseconds(50))

        var response = Data([ResponseCode.stats.rawValue, StatsType.radio.rawValue])
        response.append(TestFixtures.radioStatsPayload)
        await transport.simulateReceive(response)

        let stats = try await statsTask

        #expect(stats.noiseFloor == -110)
        #expect(stats.lastRSSI == -70)
    }

    // MARK: - Configuration

    @Test("setName sends correct command")
    func setNameSendsCommand() async throws {
        let (session, transport) = try await makeStartedSession()
        await transport.clearSentData()

        async let setTask: () = session.setName("MyDevice")
        try await Task.sleep(for: .milliseconds(50))
        await transport.simulateOK()
        try await setTask

        let sentData = await transport.sentData
        #expect(sentData.count == 1)
        #expect(sentData[0].first == CommandCode.setName.rawValue)
        #expect(String(data: sentData[0].dropFirst(), encoding: .utf8) == "MyDevice")
    }

    @Test("setCoordinates sends correct command")
    func setCoordinatesSendsCommand() async throws {
        let (session, transport) = try await makeStartedSession()
        await transport.clearSentData()

        async let setTask: () = session.setCoordinates(latitude: 37.7749, longitude: -122.4194)
        try await Task.sleep(for: .milliseconds(50))
        await transport.simulateOK()
        try await setTask

        let sentData = await transport.sentData
        #expect(sentData.count == 1)
        #expect(sentData[0].first == CommandCode.setCoordinates.rawValue)
    }

    @Test("setOtherParams sends correct command with all parameters")
    func setOtherParamsSendsCommand() async throws {
        let (session, transport) = try await makeStartedSession()
        await transport.clearSentData()

        async let setTask: () = session.setOtherParams(
            manualAddContacts: true,
            telemetryModeEnvironment: 1,
            telemetryModeLocation: 2,
            telemetryModeBase: 1,
            advertisementLocationPolicy: 1,
            multiAcks: 1
        )
        try await Task.sleep(for: .milliseconds(50))
        await transport.simulateOK()
        try await setTask

        let sentData = await transport.sentData
        #expect(sentData.count == 1)
        #expect(sentData[0].first == CommandCode.setOtherParams.rawValue)
    }

    // MARK: - Signing

    @Test("sign performs full signing flow")
    func signPerformsFullFlow() async throws {
        let (session, transport) = try await makeStartedSession()

        let testData = Data("Test data to sign".utf8)

        async let signTask = session.sign(testData, chunkSize: 120)
        try await Task.sleep(for: .milliseconds(50))

        var startResponse = Data([ResponseCode.signStart.rawValue])
        startResponse.append(TestFixtures.signStartPayload)
        await transport.simulateReceive(startResponse)

        try await Task.sleep(for: .milliseconds(50))

        await transport.simulateOK()

        try await Task.sleep(for: .milliseconds(50))

        var sigResponse = Data([ResponseCode.signature.rawValue])
        sigResponse.append(Data(repeating: 0xAB, count: 64))
        await transport.simulateReceive(sigResponse)

        let signature = try await signTask

        #expect(signature.count == 64)
    }

    // MARK: - Event Subscription

    @Test("waitForEvent returns matching event")
    func waitForEventReturnsMatchingEvent() async throws {
        let (session, transport) = try await makeStartedSession()

        async let waitTask = session.waitForEvent(matching: { event in
            if case .advertisement = event { return true }
            return false
        }, timeout: 2.0)

        try await Task.sleep(for: .milliseconds(50))

        var advert = Data([ResponseCode.advertisement.rawValue])
        advert.append(Data(repeating: 0xCD, count: 32))
        await transport.simulateReceive(advert)

        let event = await waitTask
        
        guard case .advertisement = event else {
            Issue.record("Expected advertisement event")
            return
        }
    }

    // MARK: - Error Handling

    @Test("Device error throws correctly")
    func deviceErrorThrowsCorrectly() async throws {
        let (session, transport) = try await makeStartedSession()

        async let batteryTask = session.getBattery()
        try await Task.sleep(for: .milliseconds(50))

        await transport.simulateError(code: 0x05)

        do {
            _ = try await batteryTask
            Issue.record("Expected error to be thrown")
        } catch let error as MeshCoreError {
            if case .deviceError(let code) = error {
                #expect(code == 0x05)
            } else {
                Issue.record("Expected deviceError")
            }
        }
    }

    // MARK: - Auto Message Fetching

    @Test("startAutoMessageFetching sends initial getMessage")
    func startAutoMessageFetchingSendsInitialGetMessage() async throws {
        let (session, transport) = try await makeStartedSession()
        await transport.clearSentData()

        // Start auto fetching in background (it will call getMessage internally)
        async let fetchTask: () = session.startAutoMessageFetching()
        try await Task.sleep(for: .milliseconds(50))

        // Simulate response so getMessage() completes
        await transport.simulateReceive(Data([ResponseCode.noMoreMessages.rawValue]))
        try await fetchTask

        let sentData = await transport.sentData
        let getMessageCommands = sentData.filter { $0.first == CommandCode.getMessage.rawValue }
        #expect(getMessageCommands.count >= 1)

        await session.stopAutoMessageFetching()
    }

    // MARK: - Helpers

    private func makeStartedSession() async throws -> (MeshCoreSession, MockTransport) {
        let transport = MockTransport()
        let session = MeshCoreSession(transport: transport)

        async let startTask: () = session.start()
        try await Task.sleep(for: .milliseconds(50))
        await transport.simulateReceive(makeSelfInfoResponse())
        try await startTask
        await transport.clearSentData()

        return (session, transport)
    }

    private func makeSelfInfoResponse() -> Data {
        var response = Data([ResponseCode.selfInfo.rawValue])
        response.append(TestFixtures.selfInfoPayload)
        return response
    }
}
