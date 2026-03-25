import SwiftUI

struct HeightEditorGrid: View {
    let groundElevation: Double?
    @Binding var additionalHeight: Int
    let range: ClosedRange<Int>
    var onHeightChanged: (() -> Void)?

    var body: some View {
        Grid(alignment: .leading, verticalSpacing: 8) {
            if let groundElevation {
                GridRow {
                    Text(L10n.Tools.Tools.LineOfSight.groundElevation)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(Int(groundElevation)) m")
                        .font(.caption)
                        .monospacedDigit()
                }
            } else {
                GridRow {
                    Text(L10n.Tools.Tools.LineOfSight.groundElevation)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    ProgressView()
                        .controlSize(.mini)
                }
            }

            GridRow {
                Text(L10n.Tools.Tools.LineOfSight.additionalHeight)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Stepper(value: $additionalHeight, in: range) {
                    Text("\(additionalHeight) m")
                        .font(.caption)
                        .monospacedDigit()
                }
                .controlSize(.small)
                .onChange(of: additionalHeight) {
                    onHeightChanged?()
                }
            }

            if let groundElevation {
                Divider()
                    .gridCellColumns(2)

                GridRow {
                    Text(L10n.Tools.Tools.LineOfSight.totalHeight)
                        .font(.caption)
                        .bold()

                    Spacer()

                    Text("\(Int(groundElevation) + additionalHeight) m")
                        .font(.caption)
                        .monospacedDigit()
                        .bold()
                }
            }
        }
    }
}
