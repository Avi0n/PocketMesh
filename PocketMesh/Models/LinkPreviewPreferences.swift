import SwiftUI

/// User preferences for link preview behavior
struct LinkPreviewPreferences {
    @AppStorage("linkPreviewsEnabled") var previewsEnabled = false
    @AppStorage("linkPreviewsAutoResolveDM") var autoResolveDM = true
    @AppStorage("linkPreviewsAutoResolveChannels") var autoResolveChannels = true

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
