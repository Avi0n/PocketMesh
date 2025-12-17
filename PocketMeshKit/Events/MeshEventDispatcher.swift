import Foundation
import OSLog

/// Central event dispatcher for MeshCore protocol events
/// Uses AsyncStream for efficient event processing
public actor MeshEventDispatcher {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.pocketmesh", category: "EventDispatcher")

    /// All active subscriptions keyed by ID
    private var subscriptions: [UUID: MeshEventSubscription] = [:]

    /// AsyncStream continuation for event dispatch
    private var eventContinuation: AsyncStream<MeshEvent>.Continuation?

    /// The event stream (lazily initialized)
    private var eventStream: AsyncStream<MeshEvent>?

    /// Whether the dispatcher is running
    private var isRunning = false

    /// Processing task
    private var processingTask: Task<Void, Never>?

    // MARK: - Lifecycle

    public init() {}

    /// Start processing events
    public func start() {
        guard !isRunning else { return }
        isRunning = true

        // Create the async stream using makeStream() for immediate continuation availability
        // This avoids timing issues where dispatch() could be called before the continuation is set
        // Use bufferingNewest(100) for production resilience under extreme load
        let (stream, continuation) = AsyncStream<MeshEvent>.makeStream(bufferingPolicy: .bufferingNewest(100))
        self.eventStream = stream
        self.eventContinuation = continuation

        // Start processing task
        processingTask = Task {
            await processEvents(from: stream)
        }

        logger.info("EventDispatcher started")
    }

    /// Stop processing events
    public func stop() {
        guard isRunning else { return }
        isRunning = false

        eventContinuation?.finish()
        eventContinuation = nil
        processingTask?.cancel()
        processingTask = nil

        logger.info("EventDispatcher stopped")
    }

    // MARK: - Subscription

    /// Subscribe to events with optional type and attribute filtering
    /// - Parameters:
    ///   - eventType: Event type to subscribe to (nil for all events)
    ///   - attributeFilters: Attribute key-value pairs that must match
    ///   - callback: Async callback invoked for matching events
    /// - Returns: Subscription ID that can be used to unsubscribe
    ///
    /// Example with MainActor callback for UI updates:
    /// ```swift
    /// let id = await dispatcher.subscribe(to: .advertisement) { @MainActor event in
    ///     self.updateUI(with: event.asContactFrame)
    /// }
    /// ```
    @discardableResult
    public func subscribe(
        to eventType: MeshEventType? = nil,
        attributeFilters: [String: String] = [:],
        callback: @escaping @Sendable (MeshEvent) async -> Void
    ) -> UUID {
        let subscription = MeshEventSubscription(
            eventType: eventType,
            attributeFilters: attributeFilters,
            callback: callback
        )
        subscriptions[subscription.id] = subscription
        logger.debug("Added subscription \(subscription.id) for \(eventType?.rawValue ?? "all")")
        return subscription.id
    }

    /// Remove a subscription by ID
    public func unsubscribe(_ subscriptionID: UUID) {
        subscriptions.removeValue(forKey: subscriptionID)
        logger.debug("Removed subscription \(subscriptionID)")
    }

    // MARK: - Dispatch

    /// Queue an event for dispatch
    public func dispatch(_ event: MeshEvent) {
        guard isRunning else {
            logger.warning("Dispatch called but dispatcher not running")
            return
        }
        eventContinuation?.yield(event)
        logger.trace("Queued event: \(event.type.rawValue)")
    }

    // MARK: - Wait for Event

    /// Wait for a specific event with optional filtering
    /// Uses AsyncStream.makeStream() for race-safe subscription registration
    /// - Parameters:
    ///   - eventType: The event type to wait for
    ///   - attributeFilters: Attribute key-value pairs that must match
    ///   - timeout: Maximum time to wait
    /// - Returns: The matching event, or nil if timeout
    public func waitForEvent(
        _ eventType: MeshEventType,
        attributeFilters: [String: String] = [:],
        timeout: Duration
    ) async -> MeshEvent? {
        // Register subscription FIRST, synchronously within actor isolation
        // This prevents race conditions where events could be dispatched before registration
        let subscriptionID = UUID()

        return await withTaskGroup(of: MeshEvent?.self) { group in
            // Create a stream to receive the event (makeStream gives us immediate continuation)
            let (stream, streamContinuation) = AsyncStream<MeshEvent>.makeStream()

            // Create and register subscription synchronously - no async boundary here!
            let subscription = MeshEventSubscription(
                eventType: eventType,
                attributeFilters: attributeFilters,
                callback: { event in
                    streamContinuation.yield(event)
                    streamContinuation.finish()
                }
            )
            subscriptions[subscriptionID] = subscription

            // Listener task - waits for event from stream
            group.addTask {
                for await event in stream {
                    return event
                }
                return nil
            }

            // Timeout task
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }

            // Return first result (event or nil from timeout)
            let result = await group.next() ?? nil
            group.cancelAll()

            // Clean up subscription and stream
            subscriptions.removeValue(forKey: subscriptionID)
            streamContinuation.finish()

            return result
        }
    }

    // MARK: - Processing

    private func processEvents(from stream: AsyncStream<MeshEvent>) async {
        for await event in stream {
            guard isRunning else { break }
            await dispatchToSubscribers(event)
        }
    }

    private func dispatchToSubscribers(_ event: MeshEvent) async {
        logger.trace("Dispatching \(event.type.rawValue) to \(self.subscriptions.count) subscribers")

        // Copy subscriptions to avoid mutation during iteration
        let currentSubscriptions = Array(subscriptions.values)

        for subscription in currentSubscriptions {
            // Check event type filter
            if let subscriptionType = subscription.eventType,
               subscriptionType != event.type {
                continue
            }

            // Check attribute filters - all must match
            if !subscription.attributeFilters.isEmpty {
                let allMatch = subscription.attributeFilters.allSatisfy { key, value in
                    event.attributes[key] == value
                }
                if !allMatch { continue }
            }

            // Fire callback asynchronously (don't block dispatch)
            // NOTE: Callbacks execute on the global concurrent executor, not on this actor.
            // If subscribers need MainActor isolation, they must handle it themselves.
            Task {
                await subscription.callback(event)
            }
        }
    }

    // MARK: - Stats

    /// Number of active subscriptions
    public var subscriptionCount: Int {
        subscriptions.count
    }
}
