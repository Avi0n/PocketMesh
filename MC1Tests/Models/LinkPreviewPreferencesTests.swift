import Testing
import Foundation
@testable import MC1

@Suite("LinkPreviewPreferences Tests")
struct LinkPreviewPreferencesTests {

    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    @Test("Has expected defaults: previews off, auto-resolve on")
    func defaultsToEnabled() {
        let prefs = LinkPreviewPreferences(defaults: defaults)
        #expect(prefs.previewsEnabled == false)
        #expect(prefs.autoResolveDM == true)
        #expect(prefs.autoResolveChannels == true)
    }

    @Test("shouldAutoResolve for DM respects settings")
    func shouldAutoResolveForDM() {
        var prefs = LinkPreviewPreferences(defaults: defaults)

        // Master on, auto on -> true
        prefs.previewsEnabled = true
        prefs.autoResolveDM = true
        #expect(prefs.shouldAutoResolve(isChannelMessage: false) == true)

        // Master on, auto off -> false
        prefs.autoResolveDM = false
        #expect(prefs.shouldAutoResolve(isChannelMessage: false) == false)

        // Master off -> false regardless
        prefs.previewsEnabled = false
        prefs.autoResolveDM = true
        #expect(prefs.shouldAutoResolve(isChannelMessage: false) == false)
    }

    @Test("shouldAutoResolve for channel respects settings")
    func shouldAutoResolveForChannel() {
        var prefs = LinkPreviewPreferences(defaults: defaults)

        prefs.previewsEnabled = true
        prefs.autoResolveChannels = true
        #expect(prefs.shouldAutoResolve(isChannelMessage: true) == true)

        prefs.autoResolveChannels = false
        #expect(prefs.shouldAutoResolve(isChannelMessage: true) == false)
    }

    @Test("shouldShowPreview reflects master toggle")
    func shouldShowPreview() {
        var prefs = LinkPreviewPreferences(defaults: defaults)

        prefs.previewsEnabled = true
        #expect(prefs.shouldShowPreview == true)

        prefs.previewsEnabled = false
        #expect(prefs.shouldShowPreview == false)
    }
}
