import Foundation

/// User preferences for link preview behavior
struct LinkPreviewPreferences: @unchecked Sendable {
    private static let enabledKey = "linkPreviewsEnabled"
    private static let autoResolveDMKey = "linkPreviewsAutoResolveDM"
    private static let autoResolveChannelsKey = "linkPreviewsAutoResolveChannels"

    private let defaults: UserDefaults

    var previewsEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
    }
    var autoResolveDM: Bool {
        get { defaults.object(forKey: Self.autoResolveDMKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.autoResolveDMKey) }
    }
    var autoResolveChannels: Bool {
        get { defaults.object(forKey: Self.autoResolveChannelsKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.autoResolveChannelsKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether previews should be shown at all
    var shouldShowPreview: Bool {
        previewsEnabled
    }

    /// Whether to auto-resolve based on message type
    func shouldAutoResolve(isChannelMessage: Bool) -> Bool {
        guard previewsEnabled else { return false }
        return isChannelMessage ? autoResolveChannels : autoResolveDM
    }
}
