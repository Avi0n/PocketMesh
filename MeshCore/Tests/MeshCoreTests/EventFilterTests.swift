import Foundation
import Testing
@testable import MeshCore

// MARK: - EventFilter Tests

@Suite("EventFilter Tests")
struct EventFilterTests {

    // MARK: - Acknowledgement Filter Tests

    @Test("Acknowledgement filter matches correct code")
    func acknowledgementFilterMatchesCode() {
        let code = Data([0x01, 0x02, 0x03, 0x04])
        let filter = EventFilter.acknowledgement(code: code)

        let matchingEvent = MeshEvent.acknowledgement(code: code)
        #expect(filter.matches(matchingEvent))
    }

    @Test("Acknowledgement filter rejects different code")
    func acknowledgementFilterRejectsDifferentCode() {
        let code = Data([0x01, 0x02, 0x03, 0x04])
        let differentCode = Data([0xFF, 0xFF, 0xFF, 0xFF])
        let filter = EventFilter.acknowledgement(code: code)

        let nonMatchingEvent = MeshEvent.acknowledgement(code: differentCode)
        #expect(!filter.matches(nonMatchingEvent))
    }

    @Test("Acknowledgement filter rejects non-acknowledgement events")
    func acknowledgementFilterRejectsOtherEvents() {
        let code = Data([0x01, 0x02, 0x03, 0x04])
        let filter = EventFilter.acknowledgement(code: code)

        #expect(!filter.matches(.ok(value: nil)))
        #expect(!filter.matches(.error(code: 5)))
        #expect(!filter.matches(.noMoreMessages))
    }

    // MARK: - Channel Message Filter Tests

    @Test("Channel message filter matches correct channel")
    func channelMessageFilterMatchesChannel() {
        let filter = EventFilter.channelMessage(channel: 5)

        let message = ChannelMessage(
            channelIndex: 5,
            pathLength: 0,
            textType: 0,
            senderTimestamp: Date(),
            text: "test",
            snr: nil
        )
        let event = MeshEvent.channelMessageReceived(message)
        #expect(filter.matches(event))
    }

    @Test("Channel message filter rejects different channel")
    func channelMessageFilterRejectsDifferentChannel() {
        let filter = EventFilter.channelMessage(channel: 5)

        let message = ChannelMessage(
            channelIndex: 3,
            pathLength: 0,
            textType: 0,
            senderTimestamp: Date(),
            text: "test",
            snr: nil
        )
        let event = MeshEvent.channelMessageReceived(message)
        #expect(!filter.matches(event))
    }

    @Test("Channel message filter rejects non-channel events")
    func channelMessageFilterRejectsOtherEvents() {
        let filter = EventFilter.channelMessage(channel: 5)

        #expect(!filter.matches(.ok(value: nil)))
        #expect(!filter.matches(.noMoreMessages))
    }

    // MARK: - Contact Message Filter Tests

    @Test("Contact message filter matches sender prefix")
    func contactMessageFilterMatchesPrefix() {
        let prefix = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let filter = EventFilter.contactMessage(fromPrefix: prefix)

        let message = ContactMessage(
            senderPublicKeyPrefix: Data([0xDE, 0xAD, 0xBE, 0xEF, 0x12, 0x34]),
            pathLength: 0,
            textType: 0,
            senderTimestamp: Date(),
            signature: nil,
            text: "test",
            snr: nil
        )
        let event = MeshEvent.contactMessageReceived(message)
        #expect(filter.matches(event))
    }

    @Test("Contact message filter with partial prefix")
    func contactMessageFilterPartialPrefix() {
        // Filter with shorter prefix should match longer sender prefix
        let shortPrefix = Data([0xDE, 0xAD])
        let filter = EventFilter.contactMessage(fromPrefix: shortPrefix)

        let message = ContactMessage(
            senderPublicKeyPrefix: Data([0xDE, 0xAD, 0xBE, 0xEF, 0x12, 0x34]),
            pathLength: 0,
            textType: 0,
            senderTimestamp: Date(),
            signature: nil,
            text: "test",
            snr: nil
        )
        let event = MeshEvent.contactMessageReceived(message)
        #expect(filter.matches(event))
    }

    @Test("Contact message filter rejects different sender")
    func contactMessageFilterRejectsDifferentSender() {
        let prefix = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let filter = EventFilter.contactMessage(fromPrefix: prefix)

        let message = ContactMessage(
            senderPublicKeyPrefix: Data([0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC]),
            pathLength: 0,
            textType: 0,
            senderTimestamp: Date(),
            signature: nil,
            text: "test",
            snr: nil
        )
        let event = MeshEvent.contactMessageReceived(message)
        #expect(!filter.matches(event))
    }

    // MARK: - Status Response Filter Tests

    @Test("Status response filter matches prefix")
    func statusResponseFilterMatchesPrefix() {
        let prefix = Data([0xAB, 0xCD])
        let filter = EventFilter.statusResponse(fromPrefix: prefix)

        let response = StatusResponse(
            publicKeyPrefix: Data([0xAB, 0xCD, 0xEF, 0x12, 0x34, 0x56]),
            battery: 100,
            txQueueLength: 0,
            noiseFloor: -100,
            lastRSSI: -50,
            packetsReceived: 100,
            packetsSent: 50,
            airtime: 1000,
            uptime: 3600,
            sentFlood: 10,
            sentDirect: 40,
            receivedFlood: 20,
            receivedDirect: 80,
            fullEvents: 0,
            lastSNR: 5.0,
            directDuplicates: 0,
            floodDuplicates: 0,
            rxAirtime: 500
        )
        let event = MeshEvent.statusResponse(response)
        #expect(filter.matches(event))
    }

    @Test("Status response filter rejects different prefix")
    func statusResponseFilterRejectsDifferentPrefix() {
        let prefix = Data([0xAB, 0xCD])
        let filter = EventFilter.statusResponse(fromPrefix: prefix)

        let response = StatusResponse(
            publicKeyPrefix: Data([0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC]),
            battery: 100,
            txQueueLength: 0,
            noiseFloor: -100,
            lastRSSI: -50,
            packetsReceived: 100,
            packetsSent: 50,
            airtime: 1000,
            uptime: 3600,
            sentFlood: 10,
            sentDirect: 40,
            receivedFlood: 20,
            receivedDirect: 80,
            fullEvents: 0,
            lastSNR: 5.0,
            directDuplicates: 0,
            floodDuplicates: 0,
            rxAirtime: 500
        )
        let event = MeshEvent.statusResponse(response)
        #expect(!filter.matches(event))
    }

    // MARK: - Event Type Filters Tests

    @Test("Ok filter matches ok events")
    func okFilterMatchesOkEvents() {
        let filter = EventFilter.ok

        #expect(filter.matches(.ok(value: nil)))
        #expect(filter.matches(.ok(value: 42)))
        #expect(!filter.matches(.error(code: 1)))
        #expect(!filter.matches(.noMoreMessages))
    }

    @Test("Error filter matches error events")
    func errorFilterMatchesErrorEvents() {
        let filter = EventFilter.error

        #expect(filter.matches(.error(code: nil)))
        #expect(filter.matches(.error(code: 5)))
        #expect(!filter.matches(.ok(value: nil)))
        #expect(!filter.matches(.noMoreMessages))
    }

    @Test("NoMoreMessages filter")
    func noMoreMessagesFilter() {
        let filter = EventFilter.noMoreMessages

        #expect(filter.matches(.noMoreMessages))
        #expect(!filter.matches(.messagesWaiting))
        #expect(!filter.matches(.ok(value: nil)))
    }

    @Test("MessagesWaiting filter")
    func messagesWaitingFilter() {
        let filter = EventFilter.messagesWaiting

        #expect(filter.matches(.messagesWaiting))
        #expect(!filter.matches(.noMoreMessages))
        #expect(!filter.matches(.ok(value: nil)))
    }

    // MARK: - Custom Filter Tests

    @Test("Custom filter with eventType")
    func customFilterWithEventType() {
        let filter = EventFilter.eventType { event in
            if case .battery = event { return true }
            return false
        }

        let battery = BatteryInfo(level: 4200, usedStorageKB: nil, totalStorageKB: nil)
        #expect(filter.matches(.battery(battery)))
        #expect(!filter.matches(.ok(value: nil)))
    }

    // MARK: - Combinator Tests

    @Test("Or combinator matches either filter")
    func orCombinatorMatchesEither() {
        let filter1 = EventFilter.ok
        let filter2 = EventFilter.error
        let combined = filter1.or(filter2)

        #expect(combined.matches(.ok(value: nil)))
        #expect(combined.matches(.error(code: 1)))
        #expect(!combined.matches(.noMoreMessages))
    }

    @Test("And combinator requires both filters")
    func andCombinatorRequiresBoth() {
        // Filter for acks with specific code (will always match specific acks)
        let code = Data([0x01, 0x02, 0x03, 0x04])
        let ackFilter = EventFilter.acknowledgement(code: code)

        // Custom filter that checks if it's an ack
        let isAckFilter = EventFilter { event in
            if case .acknowledgement = event { return true }
            return false
        }

        let combined = ackFilter.and(isAckFilter)

        // Should match: correct code AND is acknowledgement
        #expect(combined.matches(.acknowledgement(code: code)))

        // Should not match: wrong code
        #expect(!combined.matches(.acknowledgement(code: Data([0xFF]))))

        // Should not match: not an acknowledgement
        #expect(!combined.matches(.ok(value: nil)))
    }

    @Test("Negated filter inverts logic")
    func negatedFilterInvertsLogic() {
        let okFilter = EventFilter.ok
        let notOkFilter = okFilter.negated

        #expect(!notOkFilter.matches(.ok(value: nil)))
        #expect(notOkFilter.matches(.error(code: 1)))
        #expect(notOkFilter.matches(.noMoreMessages))
    }

    // MARK: - Advertisement Filter Tests

    @Test("Advertisement filter matches prefix")
    func advertisementFilterMatchesPrefix() {
        let prefix = Data([0xAB, 0xCD])
        let filter = EventFilter.advertisement(fromPrefix: prefix)

        let event = MeshEvent.advertisement(publicKey: Data([0xAB, 0xCD, 0xEF, 0x12, 0x34, 0x56]))
        #expect(filter.matches(event))
    }

    @Test("Advertisement filter rejects different prefix")
    func advertisementFilterRejectsDifferentPrefix() {
        let prefix = Data([0xAB, 0xCD])
        let filter = EventFilter.advertisement(fromPrefix: prefix)

        let event = MeshEvent.advertisement(publicKey: Data([0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC]))
        #expect(!filter.matches(event))
    }

    // MARK: - Path Update Filter Tests

    @Test("Path update filter matches prefix")
    func pathUpdateFilterMatchesPrefix() {
        let prefix = Data([0xAB, 0xCD])
        let filter = EventFilter.pathUpdate(forPrefix: prefix)

        let event = MeshEvent.pathUpdate(publicKey: Data([0xAB, 0xCD, 0xEF, 0x12, 0x34, 0x56]))
        #expect(filter.matches(event))
    }

    // MARK: - Telemetry Response Filter Tests

    @Test("Telemetry response filter matches prefix")
    func telemetryResponseFilterMatchesPrefix() {
        let prefix = Data([0xAB, 0xCD])
        let filter = EventFilter.telemetryResponse(fromPrefix: prefix)

        let response = TelemetryResponse(
            publicKeyPrefix: Data([0xAB, 0xCD, 0xEF, 0x12, 0x34, 0x56]),
            tag: nil,
            rawData: Data()
        )
        let event = MeshEvent.telemetryResponse(response)
        #expect(filter.matches(event))
    }
}

// MARK: - MeshEvent Attributes Tests

@Suite("MeshEvent Attributes Tests")
struct MeshEventAttributesTests {

    @Test("Contact message has correct attributes")
    func contactMessageAttributes() {
        let message = ContactMessage(
            senderPublicKeyPrefix: Data([0xDE, 0xAD, 0xBE, 0xEF, 0x12, 0x34]),
            pathLength: 2,
            textType: 1,
            senderTimestamp: Date(),
            signature: nil,
            text: "test",
            snr: nil
        )
        let event = MeshEvent.contactMessageReceived(message)
        let attrs = event.attributes

        #expect(attrs["publicKeyPrefix"] as? Data == message.senderPublicKeyPrefix)
        #expect(attrs["textType"] as? UInt8 == 1)
    }

    @Test("Channel message has correct attributes")
    func channelMessageAttributes() {
        let message = ChannelMessage(
            channelIndex: 5,
            pathLength: 0,
            textType: 2,
            senderTimestamp: Date(),
            text: "test",
            snr: nil
        )
        let event = MeshEvent.channelMessageReceived(message)
        let attrs = event.attributes

        #expect(attrs["channelIndex"] as? UInt8 == 5)
        #expect(attrs["textType"] as? UInt8 == 2)
    }

    @Test("Acknowledgement has correct attributes")
    func acknowledgementAttributes() {
        let code = Data([0x01, 0x02, 0x03, 0x04])
        let event = MeshEvent.acknowledgement(code: code)
        let attrs = event.attributes

        #expect(attrs["code"] as? Data == code)
    }

    @Test("MessageSent has correct attributes")
    func messageSentAttributes() {
        let info = MessageSentInfo(
            type: 1,
            expectedAck: Data([0xAB, 0xCD]),
            suggestedTimeoutMs: 5000
        )
        let event = MeshEvent.messageSent(info)
        let attrs = event.attributes

        #expect(attrs["type"] as? UInt8 == 1)
        #expect(attrs["expectedAck"] as? Data == Data([0xAB, 0xCD]))
    }

    @Test("Events without attributes return empty dictionary")
    func eventsWithoutAttributes() {
        let event = MeshEvent.noMoreMessages
        let attrs = event.attributes

        #expect(attrs.isEmpty)
    }
}

// MARK: - EventDispatcher Filter Tests

@Suite("EventDispatcher Filter Tests")
struct EventDispatcherFilterTests {

    @Test("Filtered subscription only receives matching events")
    func filteredSubscriptionReceivesOnlyMatching() async {
        let dispatcher = EventDispatcher()

        // Subscribe with filter for only .ok events
        let filteredStream = await dispatcher.subscribe { event in
            if case .ok = event { return true }
            return false
        }

        // Dispatch various events
        await dispatcher.dispatch(.ok(value: 1))
        await dispatcher.dispatch(.error(code: 5))
        await dispatcher.dispatch(.ok(value: 2))
        await dispatcher.dispatch(.noMoreMessages)
        await dispatcher.dispatch(.ok(value: 3))

        // Collect events from filtered stream
        var iterator = filteredStream.makeAsyncIterator()

        // Should only receive .ok events
        if case .ok(let val) = await iterator.next() {
            #expect(val == 1)
        } else {
            Issue.record("Expected .ok(1)")
        }

        if case .ok(let val) = await iterator.next() {
            #expect(val == 2)
        } else {
            Issue.record("Expected .ok(2)")
        }

        if case .ok(let val) = await iterator.next() {
            #expect(val == 3)
        } else {
            Issue.record("Expected .ok(3)")
        }
    }

    @Test("Unfiltered subscription receives all events")
    func unfilteredSubscriptionReceivesAll() async {
        let dispatcher = EventDispatcher()

        // Subscribe without filter
        let stream = await dispatcher.subscribe()

        // Dispatch events
        await dispatcher.dispatch(.ok(value: 1))
        await dispatcher.dispatch(.error(code: 5))

        var iterator = stream.makeAsyncIterator()

        // Should receive both events
        let event1 = await iterator.next()
        let event2 = await iterator.next()

        if case .ok = event1 {
            // expected
        } else {
            Issue.record("Expected .ok event first")
        }

        if case .error = event2 {
            // expected
        } else {
            Issue.record("Expected .error event second")
        }
    }

    @Test("Multiple filtered subscriptions work independently")
    func multipleFilteredSubscriptions() async {
        let dispatcher = EventDispatcher()

        // Two different filters
        let okStream = await dispatcher.subscribe { event in
            if case .ok = event { return true }
            return false
        }

        let errorStream = await dispatcher.subscribe { event in
            if case .error = event { return true }
            return false
        }

        // Dispatch
        await dispatcher.dispatch(.ok(value: 1))
        await dispatcher.dispatch(.error(code: 2))
        await dispatcher.dispatch(.ok(value: 3))

        var okIterator = okStream.makeAsyncIterator()
        var errorIterator = errorStream.makeAsyncIterator()

        // okStream should get .ok events
        if case .ok(let val) = await okIterator.next() {
            #expect(val == 1)
        }

        // errorStream should get .error event
        if case .error(let code) = await errorIterator.next() {
            #expect(code == 2)
        }
    }
}
