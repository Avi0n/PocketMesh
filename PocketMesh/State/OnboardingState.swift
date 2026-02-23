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

    /// Whether onboarding is complete (persisted to UserDefaults)
    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }

    /// Navigation path for onboarding flow
    var onboardingPath: [OnboardingStep] = []

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
