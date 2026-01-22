import MapKit
import SwiftUI
import PocketMeshServices
import os.log

private let logger = Logger(subsystem: "com.pocketmesh", category: "TracePathMapView")

/// Map-based view for building and visualizing trace paths
struct TracePathMapView: View {
    @Environment(\.appState) private var appState
    @Bindable var traceViewModel: TracePathViewModel
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
            floatingButtons

            // Map controls toolbar
            mapToolbar
        }
        .onAppear {
            mapViewModel.configure(
                traceViewModel: traceViewModel,
                userLocation: appState.locationService.currentLocation
            )
            mapViewModel.rebuildOverlays()
            mapViewModel.centerOnAllRepeaters()
        }
        .onChange(of: appState.locationService.currentLocation) { _, newLocation in
            mapViewModel.updateUserLocation(newLocation)
        }
        .onChange(of: traceViewModel.availableRepeaters.isEmpty) { wasEmpty, isEmpty in
            if wasEmpty && !isEmpty {
                mapViewModel.centerOnAllRepeaters()
            }
        }
        .onChange(of: traceViewModel.resultID) { _, _ in
            mapViewModel.updateOverlaysWithResults()
        }
        .alert("Save Path", isPresented: $showingSavePrompt) {
            TextField("Path name", text: $saveName)
            Button("Cancel", role: .cancel) {
                saveName = ""
            }
            Button("Save") {
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
            Text("Enter a name for this path")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: pinTapHaptic)
        .sensoryFeedback(.warning, trigger: rejectedTapHaptic)
        .alert("Path Saved", isPresented: $showingSaveSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The path has been saved successfully.")
        }
        .alert("Save Failed", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Failed to save the path. Please try again.")
        }
    }

    // MARK: - Map Content

    private var mapContent: some View {
        TracePathMKMapView(
            repeaters: mapViewModel.repeatersWithLocation,
            lineOverlays: mapViewModel.lineOverlays,
            badgeAnnotations: mapViewModel.badgeAnnotations,
            mapType: mapViewModel.mapType,
            showLabels: mapViewModel.showLabels,
            cameraRegion: $mapViewModel.cameraRegion,
            isRepeaterInPath: { mapViewModel.isRepeaterInPath($0) },
            hopIndex: { mapViewModel.hopIndex(for: $0) },
            isLastHop: { mapViewModel.isLastHop($0) },
            onRepeaterTap: { repeater in
                let result = mapViewModel.handleRepeaterTap(repeater)
                if result == .rejectedMiddleHop {
                    rejectedTapHaptic += 1
                } else {
                    pinTapHaptic += 1
                }
            },
            onCenterOnUser: {
                if let location = appState.locationService.currentLocation {
                    mapViewModel.cameraRegion = MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    )
                }
            }
        )
        .ignoresSafeArea()
    }

    // MARK: - Results Banner

    private func resultsBanner(result: TraceResult) -> some View {
        VStack {
            HStack {
                let hopCount = result.hops.count - 2
                Text("\(hopCount) hops")

                if let distance = traceViewModel.totalPathDistance {
                    Text("•")
                    let miles = distance / 1609.34
                    Text("\(miles, format: .number.precision(.fractionLength(1))) mi")
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
                "No Repeaters with Location",
                systemImage: "map",
                description: Text("Use List view to build paths with repeaters that don't have location data.")
            )
            Spacer()
        }
        .background(.regularMaterial)
    }

    // MARK: - Floating Buttons

    private var floatingButtons: some View {
        VStack {
            Spacer()

            LiquidGlassContainer(spacing: 12) {
                HStack(spacing: 12) {
                    if mapViewModel.hasPath {
                        // Clear button
                        Button {
                            showingClearConfirmation = true
                        } label: {
                            Text("Clear")
                        }
                        .liquidGlassButtonStyle()
                        .liquidGlassID("clear", in: buttonNamespace)
                        .confirmationDialog(
                            "Clear Path",
                            isPresented: $showingClearConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Clear Path", role: .destructive) {
                                mapViewModel.clearPath()
                            }
                        } message: {
                            Text("Remove all repeaters from the path?")
                        }

                        // Run Trace button
                        Button {
                            Task {
                                await mapViewModel.runTrace()
                            }
                        } label: {
                            if mapViewModel.isRunning {
                                HStack {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Running Trace")
                                }
                            } else {
                                Text("Run Trace")
                            }
                        }
                        .liquidGlassProminentButtonStyle()
                        .liquidGlassID("trace", in: buttonNamespace)
                        .disabled(!mapViewModel.canRunTrace)
                    }
                }
            }
            .animation(.spring(response: 0.3), value: mapViewModel.hasPath)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Map Toolbar

    private var mapToolbar: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                MapControlsToolbar(
                    onLocationTap: {
                        if let location = appState.locationService.currentLocation {
                            mapViewModel.cameraRegion = MKCoordinateRegion(
                                center: location.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                            )
                        }
                    },
                    showingLayersMenu: $mapViewModel.showingLayersMenu
                ) {
                    // Labels toggle
                    Button {
                        mapViewModel.showLabels.toggle()
                    } label: {
                        Image(systemName: "character.textbox")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(mapViewModel.showLabels ? .blue : .primary)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mapViewModel.showLabels ? "Hide labels" : "Show labels")

                    // Center on path
                    if mapViewModel.hasPath {
                        Button {
                            mapViewModel.centerOnPath()
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if mapViewModel.showingLayersMenu {
                LayersMenu(
                    selection: $mapViewModel.mapStyleSelection,
                    isPresented: $mapViewModel.showingLayersMenu
                )
                .padding(.trailing, 16)
                .padding(.bottom, 160)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: mapViewModel.showingLayersMenu)
    }
}
