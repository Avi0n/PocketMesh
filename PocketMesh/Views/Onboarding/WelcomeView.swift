import SwiftUI

/// First screen of onboarding - introduces the app
struct WelcomeView: View {
    @Environment(\.appState) private var appState

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Animated mesh visualization
            MeshAnimationView()
                .padding(.horizontal)

            // App title
            VStack(spacing: 16) {
                Text(L10n.Onboarding.Welcome.title)
                    .font(.largeTitle)
                    .bold()

                Text(L10n.Onboarding.Welcome.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Features list
            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(
                    icon: "arrow.trianglehead.branch",
                    title: L10n.Onboarding.Welcome.Feature.MultiHop.title,
                    description: L10n.Onboarding.Welcome.Feature.MultiHop.description
                )

                FeatureRow(
                    icon: "person.3.fill",
                    title: L10n.Onboarding.Welcome.Feature.Community.title,
                    description: L10n.Onboarding.Welcome.Feature.Community.description
                )
            }
            .padding(.horizontal)

            Spacer()

            // Continue button
            Button {
                appState.onboardingPath.append(.permissions)
            } label: {
                Text(L10n.Onboarding.Welcome.getStarted)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .liquidGlassProminentButtonStyle()
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(.tint.opacity(0.1), in: .circle)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

#Preview {
    WelcomeView()
        .environment(\.appState, AppState())
}
