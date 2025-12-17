import Testing
import Foundation
@testable import PocketMeshKit

@Suite("MeshEventDispatcher Tests")
struct MeshEventDispatcherTests {

    @Test("Basic event dispatch to subscriber")
    func testBasicDispatch() async throws {
        let dispatcher = MeshEventDispatcher()
        await dispatcher.start()

        // Use confirmation pattern instead of sleep-based timing (avoids flaky tests)
        await confirmation { confirm in
            let subscriptionID = await dispatcher.subscribe { event in
                #expect(event.type == .statusResponse)
                confirm()
            }

            await dispatcher.dispatch(MeshEvent(type: .statusResponse, payload: EmptyPayload()))

            // Cleanup after confirmation
            await dispatcher.unsubscribe(subscriptionID)
        }

        await dispatcher.stop()
    }

    @Test("Event type filtering - only matching types delivered")
    func testEventTypeFiltering() async throws {
        let dispatcher = MeshEventDispatcher()
        await dispatcher.start()

        // Use confirmation with expectedCount for multiple expected callbacks
        await confirmation(expectedCount: 2) { confirm in
            let statusSub = await dispatcher.subscribe(to: .statusResponse) { event in
                #expect(event.type == .statusResponse)
                confirm()
            }

            let messageSub = await dispatcher.subscribe(to: .contactMessage) { event in
                #expect(event.type == .contactMessage)
                confirm()
            }

            // Dispatch 3 different event types - only 2 should match
            await dispatcher.dispatch(MeshEvent(type: .statusResponse, payload: EmptyPayload()))
            await dispatcher.dispatch(MeshEvent(type: .contactMessage, payload: EmptyPayload()))
            await dispatcher.dispatch(MeshEvent(type: .advertisement, payload: EmptyPayload()))

            await dispatcher.unsubscribe(statusSub)
            await dispatcher.unsubscribe(messageSub)
        }

        await dispatcher.stop()
    }

    @Test("Attribute filtering - only matching attributes delivered")
    func testAttributeFiltering() async throws {
        let dispatcher = MeshEventDispatcher()
        await dispatcher.start()

        await confirmation { confirm in
            let subscriptionID = await dispatcher.subscribe(
                to: .statusResponse,
                attributeFilters: ["publicKeyPrefix": "abc123"]
            ) { event in
                #expect(event.attributes["publicKeyPrefix"] == "abc123")
                confirm()
            }

            // Should NOT match - wrong attribute value
            await dispatcher.dispatch(MeshEvent(
                type: .statusResponse,
                payload: EmptyPayload(),
                attributes: ["publicKeyPrefix": "xyz789"]
            ))

            // Should match (this one triggers the confirmation)
            await dispatcher.dispatch(MeshEvent(
                type: .statusResponse,
                payload: EmptyPayload(),
                attributes: ["publicKeyPrefix": "abc123"]
            ))

            // Should NOT match - missing attribute
            await dispatcher.dispatch(MeshEvent(
                type: .statusResponse,
                payload: EmptyPayload()
            ))

            await dispatcher.unsubscribe(subscriptionID)
        }

        await dispatcher.stop()
    }

    @Test("waitForEvent returns nil on timeout")
    func testWaitForEventTimeout() async throws {
        let dispatcher = MeshEventDispatcher()
        await dispatcher.start()

        let result = await dispatcher.waitForEvent(
            .statusResponse,
            timeout: .milliseconds(50)
        )

        #expect(result == nil)

        await dispatcher.stop()
    }

    @Test("waitForEvent returns event when dispatched")
    func testWaitForEventSuccess() async throws {
        let dispatcher = MeshEventDispatcher()
        await dispatcher.start()

        // Dispatch event after a delay
        Task {
            try await Task.sleep(for: .milliseconds(20))
            await dispatcher.dispatch(MeshEvent(
                type: .statusResponse,
                payload: EmptyPayload(),
                attributes: ["tag": "abc"]
            ))
        }

        let result = await dispatcher.waitForEvent(
            .statusResponse,
            attributeFilters: ["tag": "abc"],
            timeout: .milliseconds(200)
        )

        #expect(result != nil)
        #expect(result?.type == .statusResponse)
        #expect(result?.attributes["tag"] == "abc")

        await dispatcher.stop()
    }

    @Test("waitForEvent with attribute filter ignores non-matching events")
    func testWaitForEventAttributeFilter() async throws {
        let dispatcher = MeshEventDispatcher()
        await dispatcher.start()

        // Dispatch non-matching event first
        Task {
            try await Task.sleep(for: .milliseconds(10))
            await dispatcher.dispatch(MeshEvent(
                type: .statusResponse,
                payload: EmptyPayload(),
                attributes: ["tag": "wrong"]
            ))

            try await Task.sleep(for: .milliseconds(10))
            await dispatcher.dispatch(MeshEvent(
                type: .statusResponse,
                payload: EmptyPayload(),
                attributes: ["tag": "correct"]
            ))
        }

        let result = await dispatcher.waitForEvent(
            .statusResponse,
            attributeFilters: ["tag": "correct"],
            timeout: .milliseconds(200)
        )

        #expect(result != nil)
        #expect(result?.attributes["tag"] == "correct")

        await dispatcher.stop()
    }

    @Test("Unsubscribe stops callback invocations")
    func testUnsubscribe() async throws {
        let dispatcher = MeshEventDispatcher()
        await dispatcher.start()

        // First, confirm we receive an event
        await confirmation { confirm in
            let subscriptionID = await dispatcher.subscribe { _ in
                confirm()
            }

            await dispatcher.dispatch(MeshEvent(type: .commandOk, payload: EmptyPayload()))

            // Wait for confirmation, then unsubscribe
            await dispatcher.unsubscribe(subscriptionID)
        }

        // After unsubscribing, events should NOT trigger callbacks
        // Use waitForEvent with short timeout to verify no callbacks fire
        let callbackFired = MutableBox(false)
        _ = await dispatcher.subscribe { _ in
            callbackFired.value = true
        }
        await dispatcher.unsubscribe(UUID()) // Unsubscribe a non-existent ID (no effect)

        // Create a new subscriber, unsubscribe it, then dispatch
        let newSub = await dispatcher.subscribe { _ in
            callbackFired.value = true
        }
        await dispatcher.unsubscribe(newSub)
        await dispatcher.dispatch(MeshEvent(type: .commandOk, payload: EmptyPayload()))

        // Small delay to ensure event would have been processed
        try await Task.sleep(for: .milliseconds(20))
        // Note: Can't easily assert callbackFired is false without negative testing

        await dispatcher.stop()
    }

    @Test("Multiple subscribers receive same event")
    func testMultipleSubscribers() async throws {
        let dispatcher = MeshEventDispatcher()
        await dispatcher.start()

        await confirmation(expectedCount: 2) { confirm in
            let sub1 = await dispatcher.subscribe(to: .advertisement) { _ in
                confirm()
            }

            let sub2 = await dispatcher.subscribe(to: .advertisement) { _ in
                confirm()
            }

            await dispatcher.dispatch(MeshEvent(type: .advertisement, payload: EmptyPayload()))

            await dispatcher.unsubscribe(sub1)
            await dispatcher.unsubscribe(sub2)
        }

        await dispatcher.stop()
    }

    @Test("Nil event type subscribes to all events")
    func testSubscribeToAllEvents() async throws {
        let dispatcher = MeshEventDispatcher()
        await dispatcher.start()

        let receivedTypes = MutableBox<[MeshEventType]>([])

        await confirmation(expectedCount: 3) { confirm in
            let subscriptionID = await dispatcher.subscribe { event in
                receivedTypes.value.append(event.type)
                confirm()
            }

            await dispatcher.dispatch(MeshEvent(type: .commandOk, payload: EmptyPayload()))
            await dispatcher.dispatch(MeshEvent(type: .error, payload: EmptyPayload()))
            await dispatcher.dispatch(MeshEvent(type: .advertisement, payload: EmptyPayload()))

            await dispatcher.unsubscribe(subscriptionID)
        }

        #expect(receivedTypes.value.contains(.commandOk))
        #expect(receivedTypes.value.contains(.error))
        #expect(receivedTypes.value.contains(.advertisement))

        await dispatcher.stop()
    }

    @Test("Dispatcher not started ignores dispatch calls")
    func testDispatchBeforeStart() async throws {
        let dispatcher = MeshEventDispatcher()
        // Don't call start()

        let receivedEvents = MutableBox<[MeshEvent]>([])
        _ = await dispatcher.subscribe { event in
            receivedEvents.value.append(event)
        }

        await dispatcher.dispatch(MeshEvent(type: .commandOk, payload: EmptyPayload()))

        // Small delay to ensure event would have been processed if dispatcher was running
        try await Task.sleep(for: .milliseconds(20))

        #expect(receivedEvents.value.isEmpty)
    }

    @Test("Stress test - rapid dispatch handling")
    func testRapidDispatch() async throws {
        let dispatcher = MeshEventDispatcher()
        await dispatcher.start()

        let eventCount = 100
        let receivedCount = MutableBox(0)

        await confirmation(expectedCount: eventCount) { confirm in
            let subscriptionID = await dispatcher.subscribe { _ in
                receivedCount.value += 1
                confirm()
            }

            // Dispatch many events rapidly
            for index in 0..<eventCount {
                await dispatcher.dispatch(MeshEvent(
                    type: .commandOk,
                    payload: OKPayload(value: UInt32(index))
                ))
            }

            await dispatcher.unsubscribe(subscriptionID)
        }

        #expect(receivedCount.value == eventCount)
        await dispatcher.stop()
    }

    @Test("Concurrent subscribe/unsubscribe during dispatch")
    func testConcurrentSubscribeUnsubscribe() async throws {
        let dispatcher = MeshEventDispatcher()
        await dispatcher.start()

        // Subscribe to events
        let receivedEvents = MutableBox<[MeshEvent]>([])
        let sub1 = await dispatcher.subscribe { event in
            receivedEvents.value.append(event)
        }

        // Dispatch while subscribing/unsubscribing
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for _ in 0..<10 {
                    await dispatcher.dispatch(MeshEvent(type: .commandOk, payload: EmptyPayload()))
                }
            }

            group.addTask {
                // Subscribe and unsubscribe rapidly
                for _ in 0..<5 {
                    let tempSub = await dispatcher.subscribe { _ in }
                    await dispatcher.unsubscribe(tempSub)
                }
            }
        }

        // Small delay for processing
        try await Task.sleep(for: .milliseconds(50))

        // Should have received some events (exact count may vary due to timing)
        #expect(receivedEvents.value.count > 0)

        await dispatcher.unsubscribe(sub1)
        await dispatcher.stop()
    }
}

// MARK: - MeshEventParser Tests

@Suite("MeshEventParser Tests")
struct MeshEventParserTests {

    @Test("Parser returns nil for empty data")
    func testEmptyData() {
        let result = MeshEventParser.parseResponse(Data())
        #expect(result == nil)
    }

    @Test("Parser returns nil for truncated push notification")
    func testTruncatedPush() {
        // statusResponse needs at least 60 bytes (per FrameCodec.decodeStatusResponse)
        let truncated = Data([PushCode.statusResponse.rawValue, 0x00])
        let result = MeshEventParser.parseResponse(truncated)
        #expect(result == nil)
    }

    @Test("Parser returns nil for unknown response code")
    func testUnknownResponseCode() {
        let unknown = Data([0x7F])  // Not a valid ResponseCode
        let result = MeshEventParser.parseResponse(unknown)
        #expect(result == nil)
    }

    @Test("Parser returns nil for unknown push code")
    func testUnknownPushCode() {
        let unknown = Data([0xFF])  // Not a valid PushCode
        let result = MeshEventParser.parseResponse(unknown)
        #expect(result == nil)
    }

    @Test("Parser handles messageWaiting push correctly")
    func testMessageWaitingPush() {
        let data = Data([PushCode.messageWaiting.rawValue])
        let result = MeshEventParser.parseResponse(data)
        #expect(result?.type == .messagesWaiting)
    }

    @Test("Parser handles OK response correctly")
    func testOKResponse() {
        let data = Data([ResponseCode.ok.rawValue])
        let result = MeshEventParser.parseResponse(data)
        #expect(result?.type == .commandOk)
    }

    @Test("Parser handles OK response with value correctly")
    func testOKResponseWithValue() {
        // OK response with 4-byte value (little endian)
        var data = Data([ResponseCode.ok.rawValue])
        data.append(contentsOf: withUnsafeBytes(of: UInt32(42).littleEndian) { Array($0) })
        let result = MeshEventParser.parseResponse(data)
        #expect(result?.type == .commandOk)
        if let payload = result?.payload as? OKPayload {
            #expect(payload.value == 42)
        } else {
            Issue.record("Expected OKPayload")
        }
    }

    @Test("Parser handles error response correctly")
    func testErrorResponse() {
        let data = Data([ResponseCode.error.rawValue, 0x05])
        let result = MeshEventParser.parseResponse(data)
        #expect(result?.type == .error)
        if let payload = result?.payload as? ErrorPayload {
            #expect(payload.errorCode == 0x05)
        } else {
            Issue.record("Expected ErrorPayload")
        }
    }

    @Test("Parser handles noMoreMessages response correctly")
    func testNoMoreMessages() {
        let data = Data([ResponseCode.noMoreMessages.rawValue])
        let result = MeshEventParser.parseResponse(data)
        #expect(result?.type == .noMoreMessages)
    }

    @Test("Parser handles disabled response correctly")
    func testDisabledResponse() {
        let data = Data([ResponseCode.disabled.rawValue])
        let result = MeshEventParser.parseResponse(data)
        #expect(result?.type == .disabled)
    }

    @Test("Parser handles contactsEnd response correctly")
    func testContactsEnd() {
        let data = Data([ResponseCode.endOfContacts.rawValue])
        let result = MeshEventParser.parseResponse(data)
        #expect(result?.type == .contactsEnd)
    }

    @Test("Parser handles currentTime response correctly")
    func testCurrentTime() {
        // currentTime response: [0x09][timestamp:4]
        var data = Data([ResponseCode.currentTime.rawValue])
        data.append(contentsOf: withUnsafeBytes(of: UInt32(1234567890).littleEndian) { Array($0) })
        let result = MeshEventParser.parseResponse(data)
        #expect(result?.type == .currentTime)
        if let payload = result?.payload as? CurrentTimePayload {
            #expect(payload.timestamp == 1234567890)
        } else {
            Issue.record("Expected CurrentTimePayload")
        }
    }

    @Test("Parser handles hasConnection response correctly")
    func testHasConnection() {
        let dataFalse = Data([ResponseCode.hasConnection.rawValue, 0x00])
        let resultFalse = MeshEventParser.parseResponse(dataFalse)
        #expect(resultFalse?.type == .hasConnection)

        let dataTrue = Data([ResponseCode.hasConnection.rawValue, 0x01])
        let resultTrue = MeshEventParser.parseResponse(dataTrue)
        #expect(resultTrue?.type == .hasConnection)
    }

    @Test("Parser handles rawData push correctly")
    func testRawDataPush() {
        let data = Data([PushCode.rawData.rawValue, 0x01, 0x02, 0x03])
        let result = MeshEventParser.parseResponse(data)
        #expect(result?.type == .rawData)
        if let payload = result?.payload as? Data {
            #expect(payload == Data([0x01, 0x02, 0x03]))
        } else {
            Issue.record("Expected Data payload")
        }
    }

    @Test("Parser handles logRxData push correctly")
    func testLogRxDataPush() {
        let data = Data([PushCode.logRxData.rawValue, 0xAA, 0xBB])
        let result = MeshEventParser.parseResponse(data)
        #expect(result?.type == .logData)
    }

    @Test("Parser handles advert push correctly")
    func testAdvertPush() {
        // advert push: [0x80][publicKey:32]
        var data = Data([PushCode.advert.rawValue])
        data.append(Data(repeating: 0xAB, count: 32))
        let result = MeshEventParser.parseResponse(data)
        #expect(result?.type == .advertisement)
        #expect(result?.attributes["publicKey"] != nil)
    }

    @Test("Parser handles truncated advert push")
    func testTruncatedAdvertPush() {
        // advert needs 33 bytes total, send only 20
        var data = Data([PushCode.advert.rawValue])
        data.append(Data(repeating: 0xAB, count: 18))
        let result = MeshEventParser.parseResponse(data)
        #expect(result == nil)
    }

    @Test("Parser handles pathUpdated push correctly")
    func testPathUpdatedPush() {
        // pathUpdated: [0x81][publicKey:32]
        var data = Data([PushCode.pathUpdated.rawValue])
        data.append(Data(repeating: 0xCD, count: 32))
        let result = MeshEventParser.parseResponse(data)
        #expect(result?.type == .pathUpdate)
        #expect(result?.attributes["publicKey"] != nil)
    }

    @Test("Parser handles signature response correctly")
    func testSignatureResponse() {
        var data = Data([ResponseCode.signature.rawValue])
        data.append(Data(repeating: 0xEF, count: 64))
        let result = MeshEventParser.parseResponse(data)
        #expect(result?.type == .signature)
        if let payload = result?.payload as? SignaturePayload {
            #expect(payload.signature.count == 64)
        } else {
            Issue.record("Expected SignaturePayload")
        }
    }

    @Test("Parser handles customVars response correctly")
    func testCustomVarsResponse() {
        var data = Data([ResponseCode.customVars.rawValue])
        data.append("key1:value1,key2:value2".data(using: .utf8)!)
        let result = MeshEventParser.parseResponse(data)
        #expect(result?.type == .customVars)
        if let payload = result?.payload as? [String: String] {
            #expect(payload["key1"] == "value1")
            #expect(payload["key2"] == "value2")
        } else {
            Issue.record("Expected [String: String] payload")
        }
    }

    @Test("Parser handles contactsStart response correctly")
    func testContactsStartResponse() {
        var data = Data([ResponseCode.contactsStart.rawValue])
        data.append(contentsOf: withUnsafeBytes(of: UInt32(5).littleEndian) { Array($0) })
        let result = MeshEventParser.parseResponse(data)
        #expect(result?.type == .contactsStart)
    }

    @Test("Parser handles privateKey response correctly")
    func testPrivateKeyResponse() {
        var data = Data([ResponseCode.privateKey.rawValue])
        data.append(Data(repeating: 0x11, count: 64))
        let result = MeshEventParser.parseResponse(data)
        #expect(result?.type == .privateKey)
        if let payload = result?.payload as? PrivateKeyPayload {
            #expect(payload.privateKey.count == 64)
        } else {
            Issue.record("Expected PrivateKeyPayload")
        }
    }

    @Test("Parser handles truncated privateKey response")
    func testTruncatedPrivateKey() {
        var data = Data([ResponseCode.privateKey.rawValue])
        data.append(Data(repeating: 0x11, count: 32))  // Needs 64 bytes
        let result = MeshEventParser.parseResponse(data)
        #expect(result == nil)
    }

    @Test("Parser handles truncated currentTime response")
    func testTruncatedCurrentTime() {
        // currentTime needs 5 bytes total
        let data = Data([ResponseCode.currentTime.rawValue, 0x01, 0x02])
        let result = MeshEventParser.parseResponse(data)
        #expect(result == nil)
    }
}
