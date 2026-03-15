import SwiftUI
import MC1Services

/// Canvas wrapping the map content with offline badge, floating controls, and layers menu overlay
struct MapCanvasView: View {
    @Environment(\.appState) private var appState
    @Bindable var viewModel: MapViewModel
    let mapPoints: [MapPoint]
    let colorScheme: ColorScheme
    @Binding var selectedCalloutContact: ContactDTO?
    @Binding var selectedPointScreenPosition: CGPoint?
    @Binding var isStyleLoaded: Bool
    let onShowContactDetail: (ContactDTO) -> Void
    let onNavigateToChat: (ContactDTO) -> Void
    let onCenterOnUser: () -> Void
    let onClearSelection: () -> Void

    var body: some View {
        ZStack {
            MapContentView(
                viewModel: viewModel,
                colorScheme: colorScheme,
                mapPoints: mapPoints,
                selectedCalloutContact: $selectedCalloutContact,
                selectedPointScreenPosition: $selectedPointScreenPosition,
                isStyleLoaded: $isStyleLoaded,
                onShowContactDetail: onShowContactDetail,
                onNavigateToChat: onNavigateToChat
            )
            .ignoresSafeArea()

            // Offline badge
            if !appState.offlineMapService.isNetworkAvailable {
                OfflineBadge()
            }

            // Floating controls
            VStack {
                Spacer()
                mapControls
            }

            // Layers menu overlay
            if viewModel.showingLayersMenu {
                Button {
                    withAnimation {
                        viewModel.showingLayersMenu = false
                    }
                } label: {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                }
                .buttonStyle(.plain)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        LayersMenu(
                            selection: $viewModel.mapStyleSelection,
                            isPresented: $viewModel.showingLayersMenu
                        )
                        .padding(.trailing, 72)
                        .padding(.bottom)
                    }
                }
            }
        }
    }

    // MARK: - Map Controls

    private var mapControls: some View {
        HStack {
            Spacer()
            MapControlsToolbar(
                onLocationTap: { onCenterOnUser() },
                showingLayersMenu: $viewModel.showingLayersMenu
            ) {
                labelsToggleButton
                centerAllButton
            }
        }
    }

    private var labelsToggleButton: some View {
        Button(viewModel.showLabels ? L10n.Map.Map.Controls.hideLabels : L10n.Map.Map.Controls.showLabels, systemImage: "character.textbox") {
            withAnimation {
                viewModel.showLabels.toggle()
            }
        }
        .font(.body.weight(.medium))
        .foregroundStyle(viewModel.showLabels ? .blue : .primary)
        .frame(width: 44, height: 44)
        .contentShape(.rect)
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
    }

    private var centerAllButton: some View {
        Button(L10n.Map.Map.Controls.centerAll, systemImage: "arrow.up.left.and.arrow.down.right") {
            onClearSelection()
            viewModel.centerOnAllContacts()
        }
        .font(.body.weight(.medium))
        .foregroundStyle(viewModel.contactsWithLocation.isEmpty ? .secondary : .primary)
        .frame(width: 44, height: 44)
        .contentShape(.rect)
        .buttonStyle(.plain)
        .disabled(viewModel.contactsWithLocation.isEmpty)
        .labelStyle(.iconOnly)
    }
}
