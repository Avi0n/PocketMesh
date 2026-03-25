import SwiftUI
import MC1Services

/// Canvas wrapping the map content with offline badge, floating controls, and layers menu overlay
struct MapCanvasView: View {
    @Environment(\.appState) private var appState
    @Bindable var viewModel: MapViewModel
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
                showingLayersMenu: $viewModel.showingLayersMenu,
                topContent: {
                    NorthLockButton(isNorthLocked: $viewModel.isNorthLocked)
                }
            ) {
                LabelsToggleButton(showLabels: $viewModel.showLabels)
                CenterAllButton(
                    isEmpty: viewModel.contactsWithLocation.isEmpty,
                    onClearSelection: onClearSelection,
                    onCenterAll: { viewModel.centerOnAllContacts() }
                )
            }
        }
    }
}

// MARK: - Control Buttons

private struct NorthLockButton: View {
    @Binding var isNorthLocked: Bool

    var body: some View {
        Button(
            isNorthLocked ? L10n.Map.Map.Controls.unlockNorth : L10n.Map.Map.Controls.lockNorth,
            systemImage: isNorthLocked ? "location.north.line.fill" : "location.north.line"
        ) {
            withAnimation {
                isNorthLocked.toggle()
            }
        }
        .font(.body.weight(.medium))
        .foregroundStyle(isNorthLocked ? .blue : .primary)
        .frame(width: 44, height: 44)
        .contentShape(.rect)
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
    }
}

private struct CenterAllButton: View {
    let isEmpty: Bool
    let onClearSelection: () -> Void
    let onCenterAll: () -> Void

    var body: some View {
        Button(L10n.Map.Map.Controls.centerAll, systemImage: "arrow.up.left.and.arrow.down.right") {
            onClearSelection()
            onCenterAll()
        }
        .font(.body.weight(.medium))
        .foregroundStyle(isEmpty ? .secondary : .primary)
        .frame(width: 44, height: 44)
        .contentShape(.rect)
        .buttonStyle(.plain)
        .disabled(isEmpty)
        .labelStyle(.iconOnly)
    }
}
