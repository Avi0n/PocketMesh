import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App logo/icon
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            VStack(spacing: 16) {
                Text("Welcome to PocketMesh")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Off-grid messaging via MeshCore BLE devices")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "message.fill", text: "Simple iMessage-style messaging")
                FeatureRow(icon: "antenna.radiowaves.left.and.right", text: "Connect to MeshCore radios via Bluetooth")
                FeatureRow(icon: "person.2.fill", text: "Discover contacts in your mesh network")
                FeatureRow(icon: "map.fill", text: "Share location with mesh contacts")
            }
            .padding(.horizontal, 40)

            Spacer()

            Button(action: onContinue) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
        }
    }
}
