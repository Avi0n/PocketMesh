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
    /// Internal subscription storage with optional filter predicate
    private struct Subscription: Sendable {
        let continuation: AsyncStream<MeshEvent>.Continuation
        let filter: (@Sendable (MeshEvent) -> Bool)?
    }

    private var subscriptions: [UUID: Subscription] = [:]

    /// Subscribe to all events using modern AsyncStream.makeStream() API.
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

    /// Subscribe to events matching a filter predicate.
    ///
    /// Only events for which the filter returns `true` will be yielded to the stream.
    /// If no filter is provided (nil), all events are yielded.
    ///
    /// - Parameter filter: Optional predicate to filter events. Pass `nil` for all events.
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

    /// Dispatch an event to all subscribers, applying filters.
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

    private func removeSubscription(id: UUID) {
        subscriptions.removeValue(forKey: id)
    }
}
