import MapKit
import SwiftUI

/// Shared toolbar for map control buttons with liquid glass styling.
/// Provides location and layers buttons with slots for top and bottom custom content.
struct MapControlsToolbar<TopContent: View, CustomContent: View>: View {
    /// MapScope for SwiftUI Map's MapUserLocationButton. Mutually exclusive with onLocationTap.
    var mapScope: Namespace.ID?

    /// Custom action for location button. Used when MapScope isn't available (e.g., MapLibre views).
    var onLocationTap: (() -> Void)?

    /// Binding to control layers menu visibility. Parent view handles menu presentation.
    @Binding var showingLayersMenu: Bool

    /// Custom buttons to display above the standard buttons.
    @ViewBuilder var topContent: () -> TopContent

    /// Custom buttons to display below the standard buttons.
    @ViewBuilder var customContent: () -> CustomContent

    var body: some View {
        VStack(spacing: 0) {
            CustomContentStack {
                topContent()
            }

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
            Button(L10n.Map.Map.Controls.centerOnMyLocation, systemImage: "location.fill", action: onLocationTap)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
                .buttonStyle(.plain)
                .labelStyle(.iconOnly)
        }
    }

    // MARK: - Layers Button

    private var layersButton: some View {
        Button(L10n.Map.Map.Controls.layers, systemImage: "square.3.layers.3d.down.right") {
            withAnimation(.spring(response: 0.3)) {
                showingLayersMenu.toggle()
            }
        }
        .font(.body.weight(.medium))
        .foregroundStyle(.primary)
        .frame(width: 44, height: 44)
        .contentShape(.rect)
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
    }
}

extension MapControlsToolbar where TopContent == EmptyView {
    init(
        mapScope: Namespace.ID? = nil,
        onLocationTap: (() -> Void)? = nil,
        showingLayersMenu: Binding<Bool>,
        @ViewBuilder customContent: @escaping () -> CustomContent
    ) {
        self.mapScope = mapScope
        self.onLocationTap = onLocationTap
        self._showingLayersMenu = showingLayersMenu
        self.topContent = { EmptyView() }
        self.customContent = customContent
    }
}

// MARK: - Custom Content Stack

/// Wraps custom content and inserts dividers before each child view.
private struct CustomContentStack<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Group(subviews: content) { subviews in
            ForEach(subviews) { subview in
                Divider()
                    .frame(width: 36)
                subview
            }
        }
    }
}
