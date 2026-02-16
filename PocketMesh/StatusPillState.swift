/// Represents the current state of the status pill UI component
enum StatusPillState: Hashable {
    case hidden
    case connecting
    case syncing
    case ready
    case disconnected
    case failed(message: String)
}
