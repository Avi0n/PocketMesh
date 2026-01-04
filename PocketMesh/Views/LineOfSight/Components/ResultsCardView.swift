import SwiftUI

/// Expandable card showing analysis results with progressive disclosure
struct ResultsCardView: View {
    let result: PathAnalysisResult
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Results")
                .font(.headline)

            VStack(alignment: .leading, spacing: 0) {
                // Collapsed summary (always visible)
                collapsedContent

                // Expanded details
                if isExpanded {
                    Divider()
                        .padding(.vertical, 12)

                    expandedContent
                }
            }
            .padding()
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        }
    }

    // MARK: - Collapsed Content

    private var collapsedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    ClearanceStatusView(
                        status: result.clearanceStatus,
                        clearancePercent: result.worstClearancePercent
                    )

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            // Blocked subtitle
            if result.clearanceStatus == .blocked {
                Text(ClearanceStatus.blockedSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text(LOSFormatters.formatDistance(result.distanceMeters))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(LOSFormatters.formatPathLoss(result.totalPathLoss) + " loss")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            pathLossBreakdown
            clearanceDetails
            assumptionsFootnote
        }
    }

    // MARK: - Path Loss Breakdown

    private var pathLossBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Path Loss Breakdown")
                .font(.subheadline)
                .bold()

            Grid(alignment: .leading, verticalSpacing: 6) {
                GridRow {
                    Text("Free space loss")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(LOSFormatters.formatPathLoss(result.freeSpacePathLoss))
                        .monospacedDigit()
                }

                if let diffractionText = LOSFormatters.formatDiffractionLoss(result.additionalDiffractionLoss) {
                    GridRow {
                        Text("Diffraction loss")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(diffractionText)
                            .monospacedDigit()
                    }
                }

                Divider()
                    .gridCellColumns(2)

                GridRow {
                    Text("Total")
                        .bold()
                    Spacer()
                    Text(LOSFormatters.formatPathLoss(result.totalPathLoss))
                        .monospacedDigit()
                        .bold()
                }
            }
            .font(.subheadline)
        }
    }

    // MARK: - Clearance Details

    private var clearanceDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Clearance")
                .font(.subheadline)
                .bold()

            Grid(alignment: .leading, verticalSpacing: 6) {
                GridRow {
                    Text("Worst clearance (% of 1st Fresnel)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(LOSFormatters.formatClearancePercent(result.worstClearancePercent))%")
                        .monospacedDigit()
                }

                GridRow {
                    Text("Obstructions found")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(result.obstructionPoints.count)")
                        .monospacedDigit()
                }
            }
            .font(.subheadline)
        }
    }

    // MARK: - Assumptions Footnote

    private var assumptionsFootnote: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)

            Text(LOSFormatters.formatAssumptions(
                frequencyMHz: result.frequencyMHz,
                k: result.refractionK
            ))
            .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
    }
}

// MARK: - Preview

#Preview("Clear Path") {
    let result = PathAnalysisResult(
        distanceMeters: 12400,
        freeSpacePathLoss: 118.2,
        additionalDiffractionLoss: 0,
        totalPathLoss: 118.2,
        clearanceStatus: .clear,
        worstClearancePercent: 92,
        obstructionPoints: [],
        frequencyMHz: 906,
        refractionK: 1.33
    )

    return ResultsCardView(result: result, isExpanded: .constant(false))
        .padding()
}

#Preview("Partial Obstruction - Expanded") {
    let result = PathAnalysisResult(
        distanceMeters: 12400,
        freeSpacePathLoss: 118.2,
        additionalDiffractionLoss: 8.4,
        totalPathLoss: 126.6,
        clearanceStatus: .partialObstruction,
        worstClearancePercent: 47,
        obstructionPoints: [
            ObstructionPoint(distanceFromAMeters: 5000, obstructionHeightMeters: 12, fresnelClearancePercent: 47),
            ObstructionPoint(distanceFromAMeters: 7200, obstructionHeightMeters: 8, fresnelClearancePercent: 55)
        ],
        frequencyMHz: 906,
        refractionK: 1.33
    )

    return ResultsCardView(result: result, isExpanded: .constant(true))
        .padding()
}

#Preview("Blocked - Expanded") {
    let result = PathAnalysisResult(
        distanceMeters: 8500,
        freeSpacePathLoss: 112.5,
        additionalDiffractionLoss: 22.3,
        totalPathLoss: 134.8,
        clearanceStatus: .blocked,
        worstClearancePercent: -15,
        obstructionPoints: [
            ObstructionPoint(distanceFromAMeters: 4200, obstructionHeightMeters: 35, fresnelClearancePercent: -15)
        ],
        frequencyMHz: 915,
        refractionK: 1.33
    )

    return ResultsCardView(result: result, isExpanded: .constant(true))
        .padding()
}
