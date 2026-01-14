import SwiftUI
import PocketMeshServices

/// A pill-shaped indicator that appears at the top of the app during sync and connection operations
struct SyncingPillView: View {
    var phase: SyncPhase?
    var connectionState: ConnectionState = .disconnected
    var isFailure: Bool = false
    var failureText: String = "Sync Failed"

    private var displayText: String {
        // Failure takes priority
        if isFailure {
            return failureText
        }
        // Connecting takes priority over sync phases
        if connectionState == .connecting {
            return "Connecting..."
        }
        switch phase {
        case .contacts:
            return "Syncing contacts"
        case .channels:
            return "Syncing channels"
        default:
            return "Syncing"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if isFailure {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            Text(displayText)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(isFailure ? AnyShapeStyle(.red.opacity(0.15)) : AnyShapeStyle(.regularMaterial))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(displayText)
        .accessibilityAddTraits(isFailure ? .updatesFrequently : [])
    }
}

#Preview("Syncing") {
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

#Preview("Sync Failed") {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()

        VStack {
            SyncingPillView(isFailure: true)
            Spacer()
        }
        .padding(.top, 60)
    }
}
