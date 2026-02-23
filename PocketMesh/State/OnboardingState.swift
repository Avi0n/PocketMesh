import Foundation

enum OnboardingStep: Int, CaseIterable, Hashable {
    case welcome
    case permissions
    case deviceScan
    case radioPreset
}

/// Manages onboarding completion flag and navigation path.
@Observable
@MainActor
public final class OnboardingState {

    private let defaults: UserDefaults

    /// Whether onboarding is complete (persisted to UserDefaults)
    var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }

    /// Navigation path for onboarding flow
    var onboardingPath: [OnboardingStep] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
    }

    /// Mark onboarding as complete
    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    /// Reset onboarding state
    func resetOnboarding() {
        hasCompletedOnboarding = false
        onboardingPath = []
    }
}
