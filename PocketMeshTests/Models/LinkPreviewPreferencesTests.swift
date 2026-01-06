import Testing
import Foundation
@testable import PocketMesh

@Suite("LinkPreviewPreferences Tests")
struct LinkPreviewPreferencesTests {

    // Clean up UserDefaults before tests
    init() {
        UserDefaults.standard.removeObject(forKey: "linkPreviewsEnabled")
        UserDefaults.standard.removeObject(forKey: "linkPreviewsAutoResolveDM")
        UserDefaults.standard.removeObject(forKey: "linkPreviewsAutoResolveChannels")
    }

    @Test("Defaults to enabled for all settings")
    func defaultsToEnabled() {
        let prefs = LinkPreviewPreferences()
        #expect(prefs.previewsEnabled == true)
        #expect(prefs.autoResolveDM == true)
        #expect(prefs.autoResolveChannels == true)
    }

    @Test("shouldAutoResolve for DM respects settings")
    func shouldAutoResolveForDM() {
        var prefs = LinkPreviewPreferences()

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
        var prefs = LinkPreviewPreferences()

        prefs.previewsEnabled = true
        prefs.autoResolveChannels = true
        #expect(prefs.shouldAutoResolve(isChannelMessage: true) == true)

        prefs.autoResolveChannels = false
        #expect(prefs.shouldAutoResolve(isChannelMessage: true) == false)
    }

    @Test("shouldShowPreview reflects master toggle")
    func shouldShowPreview() {
        var prefs = LinkPreviewPreferences()

        prefs.previewsEnabled = true
        #expect(prefs.shouldShowPreview == true)

        prefs.previewsEnabled = false
        #expect(prefs.shouldShowPreview == false)
    }
}
