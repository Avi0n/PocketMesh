import SwiftUI

struct PointHeightEditorView: View {
    var viewModel: LineOfSightViewModel
    let point: SelectedPoint
    let pointID: PointID

    var body: some View {
        Grid(alignment: .leading, verticalSpacing: 8) {
            // Ground elevation row
            GridRow {
                Text(L10n.Tools.Tools.LineOfSight.groundElevation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if let elevation = point.groundElevation {
                    Text("\(Int(elevation)) m")
                        .font(.caption)
                        .monospacedDigit()
                } else {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            // Additional height row
            GridRow {
                Text(L10n.Tools.Tools.LineOfSight.additionalHeight)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Stepper(
                    value: Binding(
                        get: { point.additionalHeight },
                        set: { viewModel.updateAdditionalHeight(for: pointID, meters: $0) }
                    ),
                    in: 0...200
                ) {
                    Text("\(point.additionalHeight) m")
                        .font(.caption)
                        .monospacedDigit()
                }
                .controlSize(.small)
            }

            // Total row
            if let elevation = point.groundElevation {
                Divider()
                    .gridCellColumns(2)

                GridRow {
                    Text(L10n.Tools.Tools.LineOfSight.totalHeight)
                        .font(.caption)
                        .bold()

                    Spacer()

                    Text("\(Int(elevation) + point.additionalHeight) m")
                        .font(.caption)
                        .monospacedDigit()
                        .bold()
                }
            }
        }
    }
}
