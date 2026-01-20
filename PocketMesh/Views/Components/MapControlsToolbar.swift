import MapKit
import SwiftUI

/// Shared toolbar for map control buttons with liquid glass styling.
/// Provides location and layers buttons with a slot for custom content.
struct MapControlsToolbar<CustomContent: View>: View {
    /// MapScope for SwiftUI Map's MapUserLocationButton. Mutually exclusive with onLocationTap.
    var mapScope: Namespace.ID?

    /// Custom action for location button. Used when MapScope isn't available (e.g., MKMapViewRepresentable).
    var onLocationTap: (() -> Void)?

    /// Binding to control layers menu visibility. Parent view handles menu presentation.
    @Binding var showingLayersMenu: Bool

    /// Custom buttons to display below the standard buttons.
    @ViewBuilder var customContent: () -> CustomContent

    var body: some View {
        VStack(spacing: 0) {
            locationButton

            Divider()
                .frame(width: 36)

            layersButton

            CustomContentStack {
                customContent()
            }
        }
        .liquidGlass(in: .rect(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .padding()
    }

    // MARK: - Location Button

    @ViewBuilder
    private var locationButton: some View {
        if let mapScope {
            MapUserLocationButton(scope: mapScope)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        } else if let onLocationTap {
            Button(action: onLocationTap) {
                Image(systemName: "location.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Center on my location")
        }
    }

    // MARK: - Layers Button

    private var layersButton: some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                showingLayersMenu.toggle()
            }
        } label: {
            Image(systemName: "square.3.layers.3d.down.right")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Map layers")
    }
}

// MARK: - Custom Content Stack

/// Wraps custom content and inserts dividers before each child view.
private struct CustomContentStack<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        _VariadicView.Tree(DividerLayout()) {
            content
        }
    }
}

/// Layout that prepends a divider before each child view.
private struct DividerLayout: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        ForEach(children) { child in
            Divider()
                .frame(width: 36)
            child
        }
    }
}
