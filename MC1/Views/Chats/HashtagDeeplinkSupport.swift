import Foundation
import PocketMeshServices

struct HashtagJoinRequest: Identifiable, Hashable {
    let id: String
}

enum HashtagDeeplinkSupport {
    static let scheme = "pocketmesh-hashtag"

    static func channelNameFromURL(_ url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        return url.host
    }

    static func fullChannelName(from rawName: String) -> String? {
        let normalizedName = HashtagUtilities.normalizeHashtagName(rawName)
        guard HashtagUtilities.isValidHashtagName(normalizedName) else { return nil }
        return "#\(normalizedName)"
    }

    static func findChannelByName(
        _ name: String,
        deviceID: UUID,
        fetchChannels: @Sendable (UUID) async throws -> [ChannelDTO]
    ) async throws -> ChannelDTO? {
        let channels = try await fetchChannels(deviceID)
        return channels.first(where: { channel in
            channel.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        })
    }
}
