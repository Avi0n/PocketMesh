import SwiftUI

/// First screen of onboarding - introduces the app
struct WelcomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // App icon and title
            VStack(spacing: 16) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 80))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse.wholeSymbol, options: .repeating)

                Text("PocketMesh")
                    .font(.largeTitle)
                    .bold()

                Text("Unofficial MeshCore client for iOS")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Features list
            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(
                    icon: "message.fill",
                    title: "Mesh Messaging",
                    description: "Send messages without cellular or WiFi"
                )

                FeatureRow(
                    icon: "person.2.fill",
                    title: "Contact Discovery",
                    description: "Find other mesh users nearby"
                )
            }
            .padding(.horizontal)

            Spacer()

            // Continue button
            Button {
                appState.onboardingPath.append(.permissions)
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
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
        .environment(AppState())
}
