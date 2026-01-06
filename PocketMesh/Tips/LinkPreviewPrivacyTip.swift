import SwiftUI
import TipKit

/// Tip shown the first time a link preview loads, educating about privacy
struct LinkPreviewPrivacyTip: Tip {
    static let previewLoaded = Tips.Event(id: "linkPreviewLoaded")

    var title: Text {
        Text("Link Previews & Privacy")
    }

    var message: Text? {
        Text("Previews fetch data from the web, which may reveal your IP address. You can disable this in Settings.")
    }

    var image: Image? {
        Image(systemName: "link.badge.plus")
    }

    var options: [TipOption] {
        [Tips.MaxDisplayCount(1)]
    }

    var rules: [Rule] {
        #Rule(Self.previewLoaded) { $0.donations.count >= 1 }
    }

    var actions: [Action] {
        [Action(id: "settings", title: "Go to Settings")]
    }
}
