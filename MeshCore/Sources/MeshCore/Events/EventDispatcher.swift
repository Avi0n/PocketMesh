import Foundation

/// Dispatches MeshEvents to subscribers via AsyncStream.
///
/// `EventDispatcher` is an actor that manages event subscriptions and dispatches
/// events to all active subscribers. It supports both unfiltered and filtered subscriptions.
///
/// ## Usage
///
/// ```swift
/// let dispatcher = EventDispatcher()
///
/// // Subscribe to all events
/// let allEvents = await dispatcher.subscribe()
///
/// // Subscribe with a filter
/// let ackEvents = await dispatcher.subscribe { event in
///     if case .acknowledgement = event { return true }
///     return false
/// }
/// ```
public actor EventDispatcher {
    /// Represents an internal subscription storage with an optional filter predicate.
    private struct Subscription: Sendable {
        /// The continuation used to yield events to the async stream.
        let continuation: AsyncStream<MeshEvent>.Continuation
        /// The optional predicate used to filter events before yielding.
        let filter: (@Sendable (MeshEvent) -> Bool)?
    }

    /// Stores active subscriptions keyed by a unique identifier.
    private var subscriptions: [UUID: Subscription] = [:]

    /// Subscribes to all events using modern AsyncStream API.
    ///
    /// Uses bounded buffering to prevent memory issues with high-throughput events.
    ///
    /// - Returns: An async stream of all mesh events.
    ///
    /// - Important: Uses `.bufferingNewest(100)` which means if a subscriber processes
    ///   events slower than they arrive, older events may be dropped. For critical event
    ///   processing (e.g., debugging with `parseFailure` events), ensure your handler is
    ///   fast or process events asynchronously.
    public func subscribe() -> AsyncStream<MeshEvent> {
        subscribe(filter: nil)
    }

    /// Subscribes to events matching a filter predicate.
    ///
    /// Only events for which the filter returns `true` will be yielded to the stream.
    /// If no filter is provided (nil), all events are yielded.
    ///
    /// - Parameter filter: An optional predicate to filter events. Pass `nil` for all events.
    /// - Returns: An async stream of matching events.
    ///
    /// - Important: Uses `.bufferingNewest(100)` which means if a subscriber processes
    ///   events slower than they arrive, older events may be dropped.
    public func subscribe(
        filter: (@Sendable (MeshEvent) -> Bool)?
    ) -> AsyncStream<MeshEvent> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: MeshEvent.self,
            bufferingPolicy: .bufferingNewest(100)
        )
        let id = UUID()

        subscriptions[id] = Subscription(
            continuation: continuation,
            filter: filter
        )

        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in
                await self?.removeSubscription(id: id)
            }
        }

        return stream
    }

    /// Dispatches an event to all subscribers, applying filters.
    ///
    /// Each subscription's filter (if any) is evaluated. The event is only
    /// yielded to subscribers whose filter returns `true` or who have no filter.
    ///
    /// - Parameter event: The event to dispatch.
    public func dispatch(_ event: MeshEvent) {
        for (_, subscription) in subscriptions {
            // If no filter or filter passes, yield the event
            if subscription.filter?(event) ?? true {
                subscription.continuation.yield(event)
            }
        }
    }

    /// Removes a subscription from the dispatcher.
    /// 
    /// - Parameter id: The unique identifier of the subscription to remove.
    private func removeSubscription(id: UUID) {
        subscriptions.removeValue(forKey: id)
    }
}
