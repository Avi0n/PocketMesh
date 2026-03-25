import MapKit
import SwiftUI
import MC1Services
import os.log

private let logger = Logger(subsystem: "com.mc1", category: "TracePathMapView")

/// Map-based view for building and visualizing trace paths
struct TracePathMapView: View {
    @Environment(\.appState) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var traceViewModel: TracePathViewModel
    @Binding var presentedResult: TraceResult?
    @State private var mapViewModel = TracePathMapViewModel()

    @State private var showingSavePrompt = false
    @State private var saveName = ""
    @State private var showingClearConfirmation = false
    @State private var showingSaveSuccess = false
    @State private var showingSaveError = false
    @State private var pinTapHaptic = 0
    @State private var rejectedTapHaptic = 0

    @Namespace private var buttonNamespace

    var body: some View {
        ZStack {
            mapContent

            // Results banner at top
            if let result = mapViewModel.result, result.success {
                resultsBanner(result: result)
            }

            // Empty state
            if mapViewModel.repeatersWithLocation.isEmpty {
                emptyState
            }

            // Floating buttons
            TracePathFloatingButtonsView(
                mapViewModel: mapViewModel,
                showingClearConfirmation: $showingClearConfirmation,
                presentedResult: $presentedResult,
                buttonNamespace: buttonNamespace
            )

            // Map controls toolbar
            TracePathMapToolbarView(mapViewModel: mapViewModel)
        }
        .onAppear {
            mapViewModel.configure(
                traceViewModel: traceViewModel,
                userLocation: appState.locationService.currentLocation
            )
            mapViewModel.rebuildOverlays()
            mapViewModel.performInitialCentering()
        }
        .onChange(of: appState.locationService.currentLocation) { _, newLocation in
            mapViewModel.updateUserLocation(newLocation)
        }
        .onChange(of: traceViewModel.availableNodes) { _, _ in
            mapViewModel.rebuildPathState()
            if !mapViewModel.hasInitiallyCenteredOnRepeaters && !mapViewModel.repeatersWithLocation.isEmpty {
                mapViewModel.performInitialCentering()
            }
        }
        .onChange(of: traceViewModel.resultID) { _, _ in
            mapViewModel.updateOverlaysWithResults()
        }
        .alert(L10n.Contacts.Contacts.Trace.Map.saveTitle, isPresented: $showingSavePrompt) {
            TextField(L10n.Contacts.Contacts.Trace.Map.pathName, text: $saveName)
            Button(L10n.Contacts.Contacts.Common.cancel, role: .cancel) {
                saveName = ""
            }
            Button(L10n.Contacts.Contacts.Common.save) {
                Task {
                    let success = await mapViewModel.savePath(name: saveName)
                    saveName = ""
                    if success {
                        showingSaveSuccess = true
                    } else {
                        showingSaveError = true
                    }
                }
            }
        } message: {
            Text(L10n.Contacts.Contacts.Trace.Map.saveMessage)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: pinTapHaptic)
        .sensoryFeedback(.warning, trigger: rejectedTapHaptic)
        .alert(L10n.Contacts.Contacts.Trace.Map.savedTitle, isPresented: $showingSaveSuccess) {
            Button(L10n.Contacts.Contacts.Common.ok, role: .cancel) {}
        } message: {
            Text(L10n.Contacts.Contacts.Trace.Map.savedMessage)
        }
        .alert(L10n.Contacts.Contacts.Trace.Map.saveFailedTitle, isPresented: $showingSaveError) {
            Button(L10n.Contacts.Contacts.Common.ok, role: .cancel) {}
        } message: {
            Text(L10n.Contacts.Contacts.Trace.Map.saveFailedMessage)
        }
    }

    // MARK: - Map Content

    private var mapContent: some View {
        MC1MapView(
            points: mapViewModel.mapPoints,
            lines: mapViewModel.mapLines,
            mapStyle: mapViewModel.mapStyleSelection,
            isDarkMode: colorScheme == .dark,
            showLabels: mapViewModel.showLabels,
            showsUserLocation: true,
            isInteractive: true,
            showsScale: true,
            cameraRegion: $mapViewModel.cameraRegion,
            cameraRegionVersion: mapViewModel.cameraRegionVersion,
            cameraBottomSheetFraction: 0,
            onPointTap: { point, _ in
                if let repeater = mapViewModel.repeatersWithLocation.first(where: { $0.id == point.id }) {
                    let result = mapViewModel.handleRepeaterTap(repeater)
                    if result == .rejectedMiddleHop {
                        rejectedTapHaptic += 1
                    } else {
                        pinTapHaptic += 1
                    }
                }
            },
            onMapTap: nil,
            onCameraRegionChange: { region in
                mapViewModel.cameraRegion = region
            },
        )
        .ignoresSafeArea()
    }

    // MARK: - Results Banner

    private func resultsBanner(result: TraceResult) -> some View {
        VStack {
            HStack {
                let hopCount = result.hops.count - 2
                Text(L10n.Contacts.Contacts.Trace.Map.hops(hopCount))

                if let distance = traceViewModel.totalPathDistance {
                    Text("•")
                    Text(Measurement(value: distance, unit: UnitLength.meters),
                         format: .measurement(width: .abbreviated, usage: .road))
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .liquidGlass(in: .capsule)

            Spacer()
        }
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.3), value: result.id)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack {
            Spacer()
            ContentUnavailableView(
                L10n.Contacts.Contacts.Trace.Map.Empty.title,
                systemImage: "map",
                description: Text(L10n.Contacts.Contacts.Trace.Map.Empty.description)
            )
            Spacer()
        }
        .background(.regularMaterial)
    }

}
