import SwiftUI
import MapKit

/// Vertical stack of map control buttons
struct MapControlsStack: View {
    @Binding var showingLayersMenu: Bool
    @Binding var showLabels: Bool
    let mapScope: Namespace.ID
    let onCenterAll: () -> Void
    let centerAllDisabled: Bool

    var body: some View {
        VStack(spacing: 0) {
            // User location button
            MapUserLocationButton(scope: mapScope)
                .frame(width: 44, height: 44)
                .contentShape(.rect)

            Divider()
                .frame(width: 36)

            // Layers button
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showingLayersMenu.toggle()
                }
            } label: {
                Image(systemName: "square.3.layers.3d.down.right")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Map layers")

            Divider()
                .frame(width: 36)

            // Labels toggle button
            Button {
                withAnimation {
                    showLabels.toggle()
                }
            } label: {
                Image(systemName: "textformat")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(showLabels ? .blue : .primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showLabels ? "Hide labels" : "Show labels")

            Divider()
                .frame(width: 36)

            // Center on all button
            Button(action: onCenterAll) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(centerAllDisabled ? .secondary : .primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(centerAllDisabled)
            .accessibilityLabel("Center on all contacts")
        }
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Map controls")
    }
}
