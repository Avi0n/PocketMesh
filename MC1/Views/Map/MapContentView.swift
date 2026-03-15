import SwiftUI
import MapKit
import MC1Services

/// Map content displaying MC1MapView with contact points and popover callouts
struct MapContentView: View {
    @Bindable var viewModel: MapViewModel
    let colorScheme: ColorScheme
    let mapPoints: [MapPoint]
    @Binding var selectedCalloutContact: ContactDTO?
    @Binding var selectedPointScreenPosition: CGPoint?
    @Binding var isStyleLoaded: Bool
    let onShowContactDetail: (ContactDTO) -> Void
    let onNavigateToChat: (ContactDTO) -> Void

    var body: some View {
        if viewModel.contactsWithLocation.isEmpty && !viewModel.isLoading {
            emptyState
        } else {
            MC1MapView(
                points: mapPoints,
                lines: [],
                mapStyle: viewModel.mapStyleSelection,
                isDarkMode: colorScheme == .dark,
                showLabels: viewModel.showLabels,
                showsUserLocation: true,
                isInteractive: true,
                showsScale: true,
                cameraRegion: $viewModel.cameraRegion,
                cameraRegionVersion: viewModel.cameraRegionVersion,
                onPointTap: { point, screenPosition in
                    selectedCalloutContact = viewModel.contactsWithLocation.first { $0.id == point.id }
                    selectedPointScreenPosition = screenPosition
                },
                onMapTap: { _ in
                    selectedCalloutContact = nil
                    selectedPointScreenPosition = nil
                },
                onCameraRegionChange: { region in
                    viewModel.cameraRegion = region
                    selectedCalloutContact = nil
                    selectedPointScreenPosition = nil
                },
                isStyleLoaded: $isStyleLoaded
            )
            .popover(
                item: $selectedCalloutContact,
                attachmentAnchor: .rect(.rect(CGRect(
                    origin: selectedPointScreenPosition ?? .zero,
                    size: CGSize(width: 1, height: 1)
                ))),
                arrowEdge: .bottom
            ) { contact in
                ContactCalloutContent(
                    contact: contact,
                    onDetail: { onShowContactDetail(contact) },
                    onMessage: { onNavigateToChat(contact) }
                )
                .presentationCompactAdaptation(.popover)
            }
            .overlay {
                if !isStyleLoaded {
                    ProgressView()
                        .scaleEffect(1.5)
                } else if viewModel.isLoading {
                    loadingOverlay
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(L10n.Map.Map.EmptyState.title, systemImage: "map")
        } description: {
            Text(L10n.Map.Map.EmptyState.description)
        } actions: {
            Button(L10n.Map.Map.Common.refresh) {
                Task {
                    await viewModel.loadContactsWithLocation()
                }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.1)
            ProgressView()
                .padding()
                .background(.regularMaterial, in: .rect(cornerRadius: 8))
        }
    }
}
