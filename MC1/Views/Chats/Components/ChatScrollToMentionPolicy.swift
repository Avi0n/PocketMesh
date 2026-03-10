enum ChatScrollToMentionPolicy {
    static func shouldScrollToBottom(mentionTargetID: AnyHashable?, newestItemID: AnyHashable?) -> Bool {
        guard let mentionTargetID, let newestItemID else { return false }
        return mentionTargetID == newestItemID
    }
}
