import SwiftUI

struct MutedIndicator: View {
    let isMuted: Bool

    var body: some View {
        if isMuted {
            Image(systemName: "bell.slash")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Muted")
        }
    }
}
