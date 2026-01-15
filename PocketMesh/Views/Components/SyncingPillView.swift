import SwiftUI
import PocketMeshServices

/// A pill-shaped indicator that appears at the top of the app during sync and connection operations
struct SyncingPillView: View {
    var phase: SyncPhase?
    var connectionState: ConnectionState = .disconnected
    var isFailure: Bool = false
    var failureText: String = "Sync Failed"
    var showsConnectedToast: Bool = false
    var showsDisconnectedWarning: Bool = false
    var onDisconnectedTap: (() -> Void)?

    static func shouldShowConnectedToast(
        phase: SyncPhase?,
        connectionState: ConnectionState,
        showsConnectedToast: Bool,
        showsDisconnectedWarning: Bool,
        isFailure: Bool
    ) -> Bool {
        guard !isFailure else { return false }
        guard showsConnectedToast else { return false }
        guard !showsDisconnectedWarning else { return false }
        guard phase == nil else { return false }

        switch connectionState {
        case .connecting, .connected:
            return false
        case .disconnected, .ready:
            return true
        }
    }

    static func displayText(
        phase: SyncPhase?,
        connectionState: ConnectionState,
        showsConnectedToast: Bool,
        showsDisconnectedWarning: Bool,
        isFailure: Bool,
        failureText: String
    ) -> String {
        // Failure takes priority
        if isFailure {
            return failureText
        }

        if showsDisconnectedWarning {
            return "Disconnected"
        }

        switch connectionState {
        case .connecting, .connected:
            return "Connecting..."
        case .disconnected, .ready:
            break
        }

        switch phase {
        case .contacts:
            return "Syncing contacts"
        case .channels:
            return "Syncing channels"
        case .messages:
            return "Syncing"
        case nil:
            break
        }

        if shouldShowConnectedToast(
            phase: phase,
            connectionState: connectionState,
            showsConnectedToast: showsConnectedToast,
            showsDisconnectedWarning: showsDisconnectedWarning,
            isFailure: isFailure
        ) {
            return "Connected"
        }

        return "Syncing"
    }

    private var shouldShowConnectedToast: Bool {
        Self.shouldShowConnectedToast(
            phase: phase,
            connectionState: connectionState,
            showsConnectedToast: showsConnectedToast,
            showsDisconnectedWarning: showsDisconnectedWarning,
            isFailure: isFailure
        )
    }

    private var displayText: String {
        Self.displayText(
            phase: phase,
            connectionState: connectionState,
            showsConnectedToast: showsConnectedToast,
            showsDisconnectedWarning: showsDisconnectedWarning,
            isFailure: isFailure,
            failureText: failureText
        )
    }

    var body: some View {
        if showsDisconnectedWarning, let onDisconnectedTap {
            Button(action: onDisconnectedTap) {
                pillBody()
            }
            .buttonStyle(.plain)
            .accessibilityHint("Double tap to connect device")
        } else {
            pillBody()
        }
    }

    @ViewBuilder
    private func pillBody() -> some View {
        HStack(spacing: 8) {
            if isFailure {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else if showsDisconnectedWarning {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else if shouldShowConnectedToast {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            Text(displayText)
                .font(.subheadline)
                .fontWeight(isFailure ? .bold : .medium)
                .foregroundStyle((isFailure || showsDisconnectedWarning) ? (isFailure ? .red : .orange) : .primary)
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
        .accessibilityAddTraits(isFailure ? [] : .updatesFrequently)
    }
}

#Preview("Syncing") {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()

        VStack(spacing: 12) {
            SyncingPillView(phase: .contacts)
            SyncingPillView(phase: nil, connectionState: .connecting)
            SyncingPillView(showsConnectedToast: true)
            SyncingPillView(showsDisconnectedWarning: true)
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
