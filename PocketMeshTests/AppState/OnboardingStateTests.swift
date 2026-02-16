import Testing
import Foundation
@testable import PocketMesh

@Suite("Onboarding State Tests")
@MainActor
struct OnboardingStateTests {

    private let onboardingKey = "hasCompletedOnboarding"

    private func cleanupUserDefaults() {
        UserDefaults.standard.removeObject(forKey: onboardingKey)
    }

    // MARK: - completeOnboarding

    @Test("completeOnboarding sets flag to true")
    func completeOnboardingSetsFlag() {
        cleanupUserDefaults()
        defer { cleanupUserDefaults() }

        let appState = AppState()
        appState.onboarding.hasCompletedOnboarding = false

        appState.completeOnboarding()

        #expect(appState.onboarding.hasCompletedOnboarding == true)
    }

    @Test("completeOnboarding persists to UserDefaults")
    func completeOnboardingPersists() {
        cleanupUserDefaults()
        defer { cleanupUserDefaults() }

        let appState = AppState()
        appState.onboarding.hasCompletedOnboarding = false

        appState.completeOnboarding()

        #expect(UserDefaults.standard.bool(forKey: onboardingKey) == true)
    }

    // MARK: - resetOnboarding

    @Test("resetOnboarding clears flag")
    func resetOnboardingClearsFlag() {
        cleanupUserDefaults()
        defer { cleanupUserDefaults() }

        let appState = AppState()
        appState.onboarding.hasCompletedOnboarding = true

        appState.onboarding.resetOnboarding()

        #expect(appState.onboarding.hasCompletedOnboarding == false)
    }

    @Test("resetOnboarding clears onboarding path")
    func resetOnboardingClearsPath() {
        cleanupUserDefaults()
        defer { cleanupUserDefaults() }

        let appState = AppState()
        appState.onboarding.onboardingPath = [.welcome, .permissions]

        appState.onboarding.resetOnboarding()

        #expect(appState.onboarding.onboardingPath.isEmpty)
    }

    @Test("resetOnboarding persists false to UserDefaults")
    func resetOnboardingPersists() {
        cleanupUserDefaults()
        defer { cleanupUserDefaults() }

        let appState = AppState()
        appState.onboarding.hasCompletedOnboarding = true
        appState.onboarding.resetOnboarding()

        #expect(UserDefaults.standard.bool(forKey: onboardingKey) == false)
    }

    // MARK: - onboardingPath

    @Test("onboardingPath starts empty")
    func onboardingPathDefault() {
        let appState = AppState()
        #expect(appState.onboarding.onboardingPath.isEmpty)
    }

    @Test("onboardingPath can be appended to")
    func onboardingPathAppend() {
        let appState = AppState()

        appState.onboarding.onboardingPath.append(.welcome)
        appState.onboarding.onboardingPath.append(.permissions)

        #expect(appState.onboarding.onboardingPath == [.welcome, .permissions])
    }

    // MARK: - donateDeviceMenuTipIfOnValidTab

    @Test("donateDeviceMenuTipIfOnValidTab on Chats tab clears pending")
    func donateOnChatsTab() async {
        let appState = AppState()
        appState.navigation.selectedTab = 0
        appState.navigation.pendingDeviceMenuTipDonation = true

        await appState.donateDeviceMenuTipIfOnValidTab()

        #expect(appState.navigation.pendingDeviceMenuTipDonation == false)
    }

    @Test("donateDeviceMenuTipIfOnValidTab on Contacts tab clears pending")
    func donateOnContactsTab() async {
        let appState = AppState()
        appState.navigation.selectedTab = 1
        appState.navigation.pendingDeviceMenuTipDonation = true

        await appState.donateDeviceMenuTipIfOnValidTab()

        #expect(appState.navigation.pendingDeviceMenuTipDonation == false)
    }

    @Test("donateDeviceMenuTipIfOnValidTab on Map tab clears pending")
    func donateOnMapTab() async {
        let appState = AppState()
        appState.navigation.selectedTab = 2
        appState.navigation.pendingDeviceMenuTipDonation = true

        await appState.donateDeviceMenuTipIfOnValidTab()

        #expect(appState.navigation.pendingDeviceMenuTipDonation == false)
    }

    @Test("donateDeviceMenuTipIfOnValidTab on Settings tab sets pending")
    func donateOnSettingsTab() async {
        let appState = AppState()
        appState.navigation.selectedTab = 3
        appState.navigation.pendingDeviceMenuTipDonation = false

        await appState.donateDeviceMenuTipIfOnValidTab()

        #expect(appState.navigation.pendingDeviceMenuTipDonation == true)
    }

    @Test("donateDeviceMenuTipIfOnValidTab on Tools tab sets pending")
    func donateOnToolsTab() async {
        let appState = AppState()
        appState.navigation.selectedTab = 4
        appState.navigation.pendingDeviceMenuTipDonation = false

        await appState.donateDeviceMenuTipIfOnValidTab()

        #expect(appState.navigation.pendingDeviceMenuTipDonation == true)
    }

    // MARK: - hasCompletedOnboarding didSet

    @Test("hasCompletedOnboarding syncs to UserDefaults on set")
    func hasCompletedOnboardingDidSet() {
        cleanupUserDefaults()
        defer { cleanupUserDefaults() }

        let appState = AppState()

        appState.onboarding.hasCompletedOnboarding = true
        #expect(UserDefaults.standard.bool(forKey: onboardingKey) == true)

        appState.onboarding.hasCompletedOnboarding = false
        #expect(UserDefaults.standard.bool(forKey: onboardingKey) == false)
    }
}
