import CoreLocation
import MapKit
import SwiftUI

struct PointRowButtonsView: View {
    var viewModel: LineOfSightViewModel
    let pointID: PointID
    let isEditing: Bool
    @Binding var copyHapticTrigger: Int
    @Binding var editingPoint: PointID?
    let onRelocate: () -> Void
    let onClear: () -> Void

    @ScaledMetric(relativeTo: .body) private var iconButtonSize: CGFloat = 16

    private var point: SelectedPoint? {
        pointID == .pointA ? viewModel.pointA : viewModel.pointB
    }

    var body: some View {
        // Share menu
        Menu {
            if let coord = point?.coordinate {
                Button(L10n.Tools.Tools.LineOfSight.openInMaps, systemImage: "map") {
                    let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coord))
                    mapItem.name = pointID == .pointA ? L10n.Tools.Tools.LineOfSight.pointA : L10n.Tools.Tools.LineOfSight.pointB
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
            if viewModel.relocatingPoint == pointID {
                viewModel.relocatingPoint = nil
            } else {
                viewModel.relocatingPoint = pointID
                onRelocate()
            }
        } label: {
            Label(L10n.Tools.Tools.LineOfSight.relocate, systemImage: "mappin")
                .labelStyle(.iconOnly)
                .frame(width: iconButtonSize, height: iconButtonSize)
        }
        .liquidGlassSecondaryButtonStyle()
        .controlSize(.small)
        .disabled(viewModel.relocatingPoint != nil && viewModel.relocatingPoint != pointID)

        // Edit/Done toggle
        Button {
            withAnimation {
                editingPoint = isEditing ? nil : pointID
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
        Button(action: onClear) {
            Label(L10n.Tools.Tools.LineOfSight.clear, systemImage: "xmark")
                .labelStyle(.iconOnly)
                .frame(width: iconButtonSize, height: iconButtonSize)
        }
        .liquidGlassSecondaryButtonStyle()
        .controlSize(.small)
    }
}
