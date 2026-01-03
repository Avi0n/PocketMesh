import SwiftUI

/// Displays clearance status with appropriate icon, color, and clearance percentage
struct ClearanceStatusView: View {
    let status: ClearanceStatus
    let clearancePercent: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.iconName)
                .foregroundStyle(status.color)
                .font(.body.weight(.semibold))

            Text(status.rawValue)
                .font(.headline)

            Text("(\(clampedPercent)%)")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    /// Clamp percent to 0-100 range for display
    private var clampedPercent: Int {
        Int(max(0, min(100, clearancePercent)))
    }
}

// MARK: - Preview

#Preview("Clear") {
    ClearanceStatusView(status: .clear, clearancePercent: 92)
}

#Preview("Marginal") {
    ClearanceStatusView(status: .marginal, clearancePercent: 72)
}

#Preview("Partial Obstruction") {
    ClearanceStatusView(status: .partialObstruction, clearancePercent: 47)
}

#Preview("Blocked") {
    ClearanceStatusView(status: .blocked, clearancePercent: -15)
}
