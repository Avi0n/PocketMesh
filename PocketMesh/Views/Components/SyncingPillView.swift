import SwiftUI

/// A pill-shaped indicator that appears at the top of the app during sync and connection operations
struct SyncingPillView: View {
    let state: StatusPillState
    var onDisconnectedTap: (() -> Void)?

    var body: some View {
        if case .disconnected = state, let onDisconnectedTap {
            Button(action: onDisconnectedTap) {
                pillBody
            }
            .buttonStyle(.plain)
            .accessibilityHint("Double tap to connect device")
        } else {
            pillBody
        }
    }

    private var pillBody: some View {
        HStack(spacing: 8) {
            icon
            Text(displayText)
                .font(.subheadline)
                .fontWeight(isFailure ? .bold : .medium)
                .foregroundStyle(textColor)
                .contentTransition(.identity)
        }
        .geometryGroup()
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(backgroundStyle)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(displayText)
        .accessibilityAddTraits(isFailure ? [] : .updatesFrequently)
    }

    @ViewBuilder
    private var icon: some View {
        Group {
            switch state {
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            case .disconnected:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            case .ready:
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
            case .connecting, .syncing:
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .symbolEffect(.rotate, isActive: true)
            case .hidden:
                EmptyView()
            }
        }
        .font(.subheadline)
        .frame(width: 16, height: 16)
    }

    private var displayText: String {
        switch state {
        case .failed(let message):
            message
        case .syncing:
            "Syncing"
        case .connecting:
            "Connecting"
        case .ready:
            "Ready"
        case .disconnected:
            "Disconnected"
        case .hidden:
            ""
        }
    }

    private var isFailure: Bool {
        if case .failed = state { return true }
        return false
    }

    private var textColor: Color {
        if isFailure { return .red }
        if case .disconnected = state { return .orange }
        return .primary
    }

    private var backgroundStyle: AnyShapeStyle {
        if isFailure {
            AnyShapeStyle(.red.opacity(0.15))
        } else {
            AnyShapeStyle(.regularMaterial)
        }
    }
}

#Preview("All States") {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()

        VStack(spacing: 12) {
            SyncingPillView(state: .connecting)
            SyncingPillView(state: .syncing)
            SyncingPillView(state: .ready)
            SyncingPillView(state: .disconnected)
            SyncingPillView(state: .failed(message: "Sync Failed"))
            Spacer()
        }
        .padding(.top, 60)
    }
}
