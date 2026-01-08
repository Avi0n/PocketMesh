// PocketMeshServices/Sources/PocketMeshServices/Services/MessageDeduplicationCache.swift
import CryptoKit
import Foundation

/// In-memory cache for detecting duplicate incoming messages.
/// Uses per-conversation FIFO caches to filter retried messages from firmware.
public actor MessageDeduplicationCache {

    /// Sentinel UUID for unknown contacts (all unknowns share same dedup bucket)
    public static let unknownContactID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// Cache of recent message keys per contact (direct messages)
    private var directMessageKeys: [UUID: [String]] = [:]

    /// Cache of recent message keys per channel
    private var channelMessageKeys: [UInt8: [String]] = [:]

    /// Maximum entries per contact for direct messages
    private let directLimit = 5

    /// Maximum entries per channel
    private let channelLimit = 10

    public init() {}

    /// Check if a direct message is a duplicate.
    /// If not a duplicate, registers it in the cache.
    /// - Returns: `true` if this message was already seen
    public func isDuplicateDirectMessage(
        contactID: UUID,
        timestamp: UInt32,
        content: String
    ) -> Bool {
        let key = makeKey(timestamp: timestamp, content: content)
        return checkAndRegister(key: key, in: &directMessageKeys, for: contactID, limit: directLimit)
    }

    /// Check if a channel message is a duplicate.
    /// If not a duplicate, registers it in the cache.
    /// - Returns: `true` if this message was already seen
    public func isDuplicateChannelMessage(
        channelIndex: UInt8,
        timestamp: UInt32,
        username: String,
        content: String
    ) -> Bool {
        let key = makeKey(timestamp: timestamp, username: username, content: content)
        return checkAndRegister(key: key, in: &channelMessageKeys, for: channelIndex, limit: channelLimit)
    }

    /// Clear all cached entries (call on disconnect)
    public func clear() {
        directMessageKeys.removeAll()
        channelMessageKeys.removeAll()
    }

    // MARK: - Private Helpers

    private func makeKey(timestamp: UInt32, content: String) -> String {
        let contentHash = SHA256.hash(data: Data(content.utf8))
        let hashPrefix = contentHash.prefix(4).map { String(format: "%02X", $0) }.joined()
        return "\(timestamp)-\(hashPrefix)"
    }

    private func makeKey(timestamp: UInt32, username: String, content: String) -> String {
        let contentHash = SHA256.hash(data: Data(content.utf8))
        let hashPrefix = contentHash.prefix(4).map { String(format: "%02X", $0) }.joined()
        return "\(timestamp)-\(username)-\(hashPrefix)"
    }

    private func checkAndRegister<K: Hashable>(
        key: String,
        in cache: inout [K: [String]],
        for identifier: K,
        limit: Int
    ) -> Bool {
        var keys = cache[identifier] ?? []

        // Check if already seen
        if keys.contains(key) {
            return true
        }

        // Not seen - register it
        keys.append(key)

        // Evict oldest if over limit
        if keys.count > limit {
            keys.removeFirst()
        }

        cache[identifier] = keys
        return false
    }
}
