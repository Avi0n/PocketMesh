import Foundation
import Testing
@testable import MeshCore

// MARK: - EventDispatcher Tests

@Suite("EventDispatcher Tests")
struct EventDispatcherTests {

    @Test("Single subscriber receives events")
    func singleSubscriberReceivesEvents() async {
        let dispatcher = EventDispatcher()

        let stream = await dispatcher.subscribe()

        // Dispatch some events
        await dispatcher.dispatch(.ok(value: nil))
        await dispatcher.dispatch(.error(code: 5))
        await dispatcher.dispatch(.noMoreMessages)

        // Collect first 3 events
        var iterator = stream.makeAsyncIterator()
        let event1 = await iterator.next()
        let event2 = await iterator.next()
        let event3 = await iterator.next()

        #expect(event1 != nil)
        #expect(event2 != nil)
        #expect(event3 != nil)

        if case .ok(let val) = event1 {
            #expect(val == nil)
        } else {
            Issue.record("Expected .ok event, got \(String(describing: event1))")
        }

        if case .error(let code) = event2 {
            #expect(code == 5)
        } else {
            Issue.record("Expected .error event, got \(String(describing: event2))")
        }

        if case .noMoreMessages = event3 {
            // Expected
        } else {
            Issue.record("Expected .noMoreMessages event, got \(String(describing: event3))")
        }
    }

    @Test("Multiple subscribers receive same event")
    func multipleSubscribersReceiveSameEvent() async {
        let dispatcher = EventDispatcher()

        let stream1 = await dispatcher.subscribe()
        let stream2 = await dispatcher.subscribe()

        // Dispatch an event
        await dispatcher.dispatch(.ok(value: 42))

        // Both streams should receive the event
        var iterator1 = stream1.makeAsyncIterator()
        var iterator2 = stream2.makeAsyncIterator()

        let event1 = await iterator1.next()
        let event2 = await iterator2.next()

        if case .ok(let val) = event1 {
            #expect(val == 42)
        } else {
            Issue.record("Stream 1 expected .ok, got \(String(describing: event1))")
        }

        if case .ok(let val) = event2 {
            #expect(val == 42)
        } else {
            Issue.record("Stream 2 expected .ok, got \(String(describing: event2))")
        }
    }

    @Test("Events are dispatched in order")
    func eventsDispatchedInOrder() async {
        let dispatcher = EventDispatcher()
        let stream = await dispatcher.subscribe()

        // Dispatch numbered events
        for i in 0..<5 {
            await dispatcher.dispatch(.ok(value: UInt32(i)))
        }

        // Verify order
        var iterator = stream.makeAsyncIterator()
        for expected in 0..<5 {
            let event = await iterator.next()
            if case .ok(let value) = event {
                #expect(value == UInt32(expected))
            } else {
                Issue.record("Expected .ok(\(expected)), got \(String(describing: event))")
            }
        }
    }

    @Test("Late subscriber misses early events")
    func lateSubscriberMissesEarlyEvents() async {
        let dispatcher = EventDispatcher()

        // Dispatch before subscribing
        await dispatcher.dispatch(.ok(value: 1))
        await dispatcher.dispatch(.ok(value: 2))

        // Subscribe late
        let stream = await dispatcher.subscribe()

        // Dispatch after subscribing
        await dispatcher.dispatch(.ok(value: 3))

        // Should only receive the event dispatched after subscription
        var iterator = stream.makeAsyncIterator()
        let event = await iterator.next()

        if case .ok(let value) = event {
            #expect(value == 3)
        } else {
            Issue.record("Expected .ok(3), got \(String(describing: event))")
        }
    }

    @Test("Dispatcher handles different event types")
    func handlesVariousEventTypes() async {
        let dispatcher = EventDispatcher()
        let stream = await dispatcher.subscribe()

        // Dispatch various event types
        await dispatcher.dispatch(.ok(value: 100))
        await dispatcher.dispatch(.error(code: 42))
        await dispatcher.dispatch(.noMoreMessages)
        await dispatcher.dispatch(.messagesWaiting)

        var iterator = stream.makeAsyncIterator()

        // Verify each event type is received correctly
        if case .ok(let val) = await iterator.next() {
            #expect(val == 100)
        } else {
            Issue.record("Expected .ok(100)")
        }

        if case .error(let code) = await iterator.next() {
            #expect(code == 42)
        } else {
            Issue.record("Expected .error(42)")
        }

        if case .noMoreMessages = await iterator.next() {
            // Expected
        } else {
            Issue.record("Expected .noMoreMessages")
        }

        if case .messagesWaiting = await iterator.next() {
            // Expected
        } else {
            Issue.record("Expected .messagesWaiting")
        }
    }

    @Test("Events include correct associated values")
    func eventAssociatedValues() async {
        let dispatcher = EventDispatcher()
        let stream = await dispatcher.subscribe()

        // Create events with associated values
        let battery = BatteryInfo(level: 4200, usedStorageKB: 1024, totalStorageKB: 4096)
        let message = ContactMessage(
            senderPublicKeyPrefix: Data([0xDE, 0xAD, 0xBE, 0xEF, 0x12, 0x34]),
            pathLength: 2,
            textType: 0,
            senderTimestamp: Date(timeIntervalSince1970: 1700000000),
            signature: nil,
            text: "Test",
            snr: -5.25
        )

        // Dispatch events
        await dispatcher.dispatch(.battery(battery))
        await dispatcher.dispatch(.contactMessageReceived(message))

        var iterator = stream.makeAsyncIterator()

        if case .battery(let b) = await iterator.next() {
            #expect(b.level == 4200)
            #expect(b.usedStorageKB == 1024)
            #expect(b.totalStorageKB == 4096)
        } else {
            Issue.record("Expected battery event")
        }

        if case .contactMessageReceived(let m) = await iterator.next() {
            #expect(m.text == "Test")
            #expect(m.snr == -5.25)
            #expect(m.pathLength == 2)
        } else {
            Issue.record("Expected contactMessageReceived event")
        }
    }

    @Test("Many events can be dispatched")
    func manyEventsDispatched() async {
        let dispatcher = EventDispatcher()
        let stream = await dispatcher.subscribe()

        let eventCount = 100

        // Dispatch many events
        for i in 0..<eventCount {
            await dispatcher.dispatch(.ok(value: UInt32(i)))
        }

        // Verify first several events
        var iterator = stream.makeAsyncIterator()
        for expected in 0..<10 {
            let event = await iterator.next()
            if case .ok(let value) = event {
                #expect(value == UInt32(expected))
            }
        }
    }
}

// MARK: - MockClock Tests

@Suite("MockClock Tests")
struct MockClockTests {

    @Test("MockClock advances time correctly")
    func mockClockAdvances() {
        let clock = MockClock()
        let start = clock.now

        clock.advance(by: .seconds(5))

        let elapsed = start.duration(to: clock.now)
        #expect(elapsed == .seconds(5))
    }

    @Test("MockClock can advance by various durations")
    func mockClockAdvancesVariousDurations() {
        let clock = MockClock()
        let start = clock.now

        clock.advance(by: .milliseconds(100))
        clock.advance(by: .milliseconds(200))
        clock.advance(by: .milliseconds(700))

        let elapsed = start.duration(to: clock.now)
        #expect(elapsed == .seconds(1))
    }

    @Test("MockClock sleep completes when time advances past deadline")
    func mockClockSleepCompletes() async throws {
        let clock = MockClock(spinSleepInterval: .zero)

        // Start a sleep task
        let sleepTask = Task {
            try await clock.sleep(for: .seconds(10))
            return true
        }

        // Give it a moment to start
        try await Task.sleep(for: .milliseconds(10))

        // Advance time past the deadline
        clock.advance(by: .seconds(15))

        // Wait for sleep to complete
        let completed = try await sleepTask.value
        #expect(completed == true)
    }

    @Test("MockClock respects cancellation")
    func mockClockCancellation() async {
        let clock = MockClock(spinSleepInterval: .zero)

        let sleepTask = Task {
            try await clock.sleep(for: .seconds(1000))
        }

        // Give it a moment to start
        try? await Task.sleep(for: .milliseconds(10))

        // Cancel immediately
        sleepTask.cancel()

        do {
            try await sleepTask.value
            Issue.record("Expected cancellation error")
        } catch {
            // Expected - should throw CancellationError
            #expect(error is CancellationError)
        }
    }

    @Test("Multiple MockClock instances are independent")
    func multipleClockInstances() {
        let clock1 = MockClock()
        let clock2 = MockClock()

        let start1 = clock1.now
        let start2 = clock2.now

        clock1.advance(by: .seconds(5))

        // clock1 should have advanced by 5 seconds, clock2 should not have moved
        #expect(start1.duration(to: clock1.now) == .seconds(5))
        #expect(start2.duration(to: clock2.now) == .zero)
    }
}
