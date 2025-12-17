import Foundation

/// A subscription to events - immutable value type
/// Unsubscribe via dispatcher.unsubscribe(subscription.id)
public struct MeshEventSubscription: Sendable {
    /// Unique ID for this subscription
    public let id: UUID

    /// Event type to subscribe to (nil = all events)
    public let eventType: MeshEventType?

    /// Attribute filters - all must match for callback to fire
    public let attributeFilters: [String: String]

    /// The callback to invoke (internal, not exposed)
    let callback: @Sendable (MeshEvent) async -> Void

    init(
        eventType: MeshEventType?,
        attributeFilters: [String: String],
        callback: @escaping @Sendable (MeshEvent) async -> Void
    ) {
        self.id = UUID()
        self.eventType = eventType
        self.attributeFilters = attributeFilters
        self.callback = callback
    }
}
