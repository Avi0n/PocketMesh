import CoreLocation
import MapKit
import SwiftUI

struct RepeaterRowView: View {
    var viewModel: LineOfSightViewModel
    @Binding var copyHapticTrigger: Int
    @Binding var editingPoint: PointID?
    let onRelocate: () -> Void

    @ScaledMetric(relativeTo: .body) private var iconButtonSize: CGFloat = 16

    private var isEditing: Bool { editingPoint == .repeater }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack {
                // Repeater marker (purple)
                Circle()
                    .fill(.purple)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Text("R")
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.Tools.Tools.LineOfSight.repeater)
                        .font(.subheadline)
                        .lineLimit(1)

                    if let elevation = viewModel.repeaterGroundElevation {
                        let totalHeight = Int(elevation) + (viewModel.repeaterPoint?.additionalHeight ?? 0)
                        Text("\(totalHeight)m")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Share menu
                Menu {
                    if let coord = viewModel.repeaterPoint?.coordinate {
                        Button(L10n.Tools.Tools.LineOfSight.openInMaps, systemImage: "map") {
                            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coord))
                            mapItem.name = L10n.Tools.Tools.LineOfSight.repeaterLocation
                            mapItem.openInMaps()
                        }

                        Button(L10n.Tools.Tools.LineOfSight.copyCoordinates, systemImage: "doc.on.doc") {
                            copyHapticTrigger += 1
                            UIPasteboard.general.string = coord.formattedString
                        }

                        ShareLink(item: coord.formattedString) {
                            Label(L10n.Tools.Tools.LineOfSight.share, systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Label(L10n.Tools.Tools.LineOfSight.shareLabel, systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                        .frame(width: iconButtonSize, height: iconButtonSize)
                }
                .liquidGlassSecondaryButtonStyle()
                .sensoryFeedback(.success, trigger: copyHapticTrigger)
                .controlSize(.small)

                // Relocate button (toggles on/off)
                Button {
                    if viewModel.relocatingPoint == .repeater {
                        viewModel.relocatingPoint = nil
                    } else {
                        viewModel.relocatingPoint = .repeater
                        onRelocate()
                    }
                } label: {
                    Label(L10n.Tools.Tools.LineOfSight.relocate, systemImage: "mappin")
                        .labelStyle(.iconOnly)
                        .frame(width: iconButtonSize, height: iconButtonSize)
                }
                .liquidGlassSecondaryButtonStyle()
                .controlSize(.small)
                .disabled(viewModel.relocatingPoint != nil && viewModel.relocatingPoint != .repeater)

                // Edit/Done toggle
                Button {
                    withAnimation {
                        editingPoint = isEditing ? nil : .repeater
                    }
                } label: {
                    Group {
                        if isEditing {
                            Label(L10n.Tools.Tools.LineOfSight.done, systemImage: "checkmark")
                                .labelStyle(.iconOnly)
                        } else {
                            Label(L10n.Tools.Tools.LineOfSight.edit, systemImage: "ruler")
                                .labelStyle(.iconOnly)
                                .rotationEffect(.degrees(90))
                        }
                    }
                    .frame(width: iconButtonSize, height: iconButtonSize)
                }
                .liquidGlassSecondaryButtonStyle()
                .controlSize(.small)

                // Clear button
                Button {
                    viewModel.clearRepeater()
                } label: {
                    Label(L10n.Tools.Tools.LineOfSight.clear, systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .frame(width: iconButtonSize, height: iconButtonSize)
                }
                .liquidGlassSecondaryButtonStyle()
                .controlSize(.small)
            }

            // Expanded editor
            if isEditing, let repeaterPoint = viewModel.repeaterPoint {
                Divider()
                RepeaterHeightEditorView(viewModel: viewModel, repeaterPoint: repeaterPoint)
            }
        }
        .padding(12)
        .animation(.easeInOut(duration: 0.2), value: isEditing)
    }
}
