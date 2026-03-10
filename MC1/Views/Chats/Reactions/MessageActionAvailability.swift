import PocketMeshServices

/// Determines which message actions are available based on message state.
/// Extracted for testability and reuse across UI components.
struct MessageActionAvailability {
    let canReply: Bool
    let canCopy: Bool
    let canSendAgain: Bool
    let canBlockSender: Bool
    let canShowRepeatDetails: Bool
    let canViewPath: Bool
    let canDelete: Bool

    init(message: MessageDTO) {
        canReply = !message.isOutgoing
        canCopy = true
        canSendAgain = message.isOutgoing
        canBlockSender = message.isChannelMessage && !message.isOutgoing && message.senderNodeName != nil
        canShowRepeatDetails = message.isOutgoing && message.heardRepeats > 0
        canViewPath = !message.isOutgoing
            && message.pathNodes != nil
            && message.pathLength != 0
            && message.pathLength != 0xFF
        canDelete = true
    }
}
