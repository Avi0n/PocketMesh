import SwiftUI

/// Inline editor for adjusting a point's additional height
struct PointEditorView: View {
    let point: SelectedPoint
    let pointID: PointID
    let onHeightChange: (Int) -> Void
    let onDone: () -> Void

    @State private var additionalHeight: Int

    // MARK: - Initialization

    init(
        point: SelectedPoint,
        pointID: PointID,
        onHeightChange: @escaping (Int) -> Void,
        onDone: @escaping () -> Void
    ) {
        self.point = point
        self.pointID = pointID
        self.onHeightChange = onHeightChange
        self.onDone = onDone
        self._additionalHeight = State(initialValue: point.additionalHeight)
    }

    // MARK: - Computed Properties

    private var totalHeight: Double? {
        guard let groundElevation = point.groundElevation else { return nil }
        return groundElevation + Double(additionalHeight)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            pointNameHeadline

            elevationGrid

            doneButtonRow
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
    }

    // MARK: - Subviews

    private var pointNameHeadline: some View {
        Text(point.displayName)
            .font(.headline)
    }

    private var elevationGrid: some View {
        Grid(alignment: .leading, verticalSpacing: 8) {
            // Ground elevation row
            GridRow {
                Text("Ground elevation")
                    .foregroundStyle(.secondary)

                Spacer()

                groundElevationValue
            }

            // Additional height row
            GridRow {
                Text("Additional height")
                    .foregroundStyle(.secondary)

                Spacer()

                heightStepper
            }

            // Total row (only shown if elevation is available)
            if let total = totalHeight {
                Divider()
                    .gridCellColumns(3)

                GridRow {
                    Text("Total")
                        .bold()

                    Spacer()

                    Text(total, format: .number.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .bold()
                    + Text(" m")
                        .bold()
                }
            }
        }
    }

    @ViewBuilder
    private var groundElevationValue: some View {
        if let elevation = point.groundElevation {
            Text(elevation, format: .number.precision(.fractionLength(0)))
                .monospacedDigit()
            + Text(" m")
        } else {
            ProgressView()
        }
    }

    private var heightStepper: some View {
        Stepper(value: $additionalHeight, in: 0...200) {
            Text("\(additionalHeight) m")
                .monospacedDigit()
        }
        .onChange(of: additionalHeight) { _, newValue in
            onHeightChange(newValue)
        }
    }

    private var doneButtonRow: some View {
        HStack {
            Spacer()
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Preview

#Preview("With Elevation") {
    PointEditorView(
        point: SelectedPoint(
            coordinate: .init(latitude: 37.7749, longitude: -122.4194),
            contact: nil,
            groundElevation: 150,
            additionalHeight: 10
        ),
        pointID: .pointA,
        onHeightChange: { height in
            print("Height changed to: \(height)")
        },
        onDone: {
            print("Done tapped")
        }
    )
    .padding()
}

#Preview("Loading Elevation") {
    PointEditorView(
        point: SelectedPoint(
            coordinate: .init(latitude: 37.7749, longitude: -122.4194),
            contact: nil,
            groundElevation: nil
        ),
        pointID: .pointB,
        onHeightChange: { _ in },
        onDone: { }
    )
    .padding()
}
