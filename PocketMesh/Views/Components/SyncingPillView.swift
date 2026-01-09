import SwiftUI
import PocketMeshServices

/// A pill-shaped indicator that appears at the top of the app during sync operations
struct SyncingPillView: View {
    var phase: SyncPhase?

    private var displayText: String {
        switch phase {
        case .contacts:
            return "Syncing contacts..."
        case .channels:
            return "Syncing channels..."
        default:
            return "Syncing..."
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text(displayText)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()

        VStack {
            SyncingPillView()
            Spacer()
        }
        .padding(.top, 60)
    }
}
