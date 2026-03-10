import SwiftUI
import PocketMeshServices

/// Small label displaying contact name above map pins
struct ContactNameLabel: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption2)
            .fontWeight(.medium)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.regularMaterial, in: .capsule)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1.5)
    }
}

#Preview {
    VStack(spacing: 20) {
        ContactNameLabel(name: "Alice")
        ContactNameLabel(name: "Hilltop Repeater Station")
        ContactNameLabel(name: "Emergency Room")
    }
    .padding()
}
