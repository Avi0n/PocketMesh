import SwiftUI

struct RepeaterHeightEditorView: View {
    var viewModel: LineOfSightViewModel
    let repeaterPoint: RepeaterPoint

    var body: some View {
        Grid(alignment: .leading, verticalSpacing: 8) {
            if let groundElevation = viewModel.repeaterGroundElevation {
                GridRow {
                    Text(L10n.Tools.Tools.LineOfSight.groundElevation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(groundElevation)) m")
                        .font(.caption)
                        .monospacedDigit()
                }
            }

            GridRow {
                Text(L10n.Tools.Tools.LineOfSight.additionalHeight)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper(
                    value: Binding(
                        get: { repeaterPoint.additionalHeight },
                        set: {
                            viewModel.updateRepeaterHeight(meters: $0)
                            viewModel.analyzeWithRepeater()
                        }
                    ),
                    in: 0...200
                ) {
                    Text("\(repeaterPoint.additionalHeight) m")
                        .font(.caption)
                        .monospacedDigit()
                }
                .controlSize(.small)
            }

            if let groundElevation = viewModel.repeaterGroundElevation {
                Divider()
                    .gridCellColumns(2)

                GridRow {
                    Text(L10n.Tools.Tools.LineOfSight.totalHeight)
                        .font(.caption)
                        .bold()
                    Spacer()
                    Text("\(Int(groundElevation) + repeaterPoint.additionalHeight) m")
                        .font(.caption)
                        .monospacedDigit()
                        .bold()
                }
            }
        }
    }
}
