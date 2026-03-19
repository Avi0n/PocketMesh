import Foundation

/// A channel message waiting to be sent via the queue processor.
struct QueuedChannelMessage {
    let messageID: UUID
}
