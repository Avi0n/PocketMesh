import MapKit
import MapLibre
import SwiftUI

struct OfflineMapSettingsView: View {
    @Environment(\.appState) private var appState
    @State private var showingRegionPicker = false
    @State private var packToDelete: OfflinePack?

    var body: some View {
        List {
            if appState.offlineMapService.packs.isEmpty {
                ContentUnavailableView {
                    Label(L10n.Settings.OfflineMaps.emptyTitle, systemImage: "map")
                } description: {
                    Text(L10n.Settings.OfflineMaps.emptyDescription)
                } actions: {
                    Button(L10n.Settings.OfflineMaps.downloadRegion, systemImage: "arrow.down.circle") {
                        showingRegionPicker = true
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                PacksSection(packToDelete: $packToDelete)
                StorageSection()
            }
        }
        .navigationTitle(L10n.Settings.OfflineMaps.title)
        .toolbar {
            if !appState.offlineMapService.packs.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.Settings.OfflineMaps.downloadRegion, systemImage: "plus") {
                        showingRegionPicker = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingRegionPicker) {
            RegionPickerSheet()
        }
        .alert(
            L10n.Settings.OfflineMaps.deleteTitle,
            isPresented: .init(
                get: { packToDelete != nil },
                set: { if !$0 { packToDelete = nil } }
            )
        ) {
            Button(L10n.Settings.OfflineMaps.delete, role: .destructive) {
                if let pack = packToDelete {
                    Task { await appState.offlineMapService.deletePack(pack) }
                }
            }
            Button(L10n.Settings.OfflineMaps.cancel, role: .cancel) {}
        } message: {
            Text(L10n.Settings.OfflineMaps.deleteMessage)
        }
    }

}

// MARK: - Packs Section

private struct PacksSection: View {
    @Environment(\.appState) private var appState
    @Binding var packToDelete: OfflinePack?

    var body: some View {
        Section {
            ForEach(appState.offlineMapService.packs) { pack in
                OfflinePackRow(pack: pack)
            }
            .onDelete { indexSet in
                if let index = indexSet.first {
                    packToDelete = appState.offlineMapService.packs[index]
                }
            }
        } header: {
            Text(L10n.Settings.OfflineMaps.downloaded)
        }
    }
}

// MARK: - Storage Section

private struct StorageSection: View {
    @Environment(\.appState) private var appState

    var body: some View {
        Section {
            let totalBytes = appState.offlineMapService.packs.reduce(UInt64(0)) { $0 + $1.completedBytes }
            LabeledContent(L10n.Settings.OfflineMaps.storageUsed) {
                Text(Int64(totalBytes), format: .byteCount(style: .file))
            }
        } header: {
            Text(L10n.Settings.OfflineMaps.storage)
        }
    }
}

// MARK: - Offline Pack Row

private struct OfflinePackRow: View {
    let pack: OfflinePack

    var body: some View {
        VStack(alignment: .leading) {
            Text(pack.name)

            HStack {
                if pack.isComplete {
                    Text(L10n.Settings.OfflineMaps.complete)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L10n.Settings.OfflineMaps.downloading)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(Int64(pack.completedBytes), format: .byteCount(style: .file))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            if !pack.isComplete {
                ProgressView(value: pack.completedFraction)
            }
        }
    }
}

// MARK: - Region Picker Sheet

private struct RegionPickerSheet: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var regionName = ""
    @State private var cameraRegion: MKCoordinateRegion?
    @State private var isStyleLoaded = false
    @State private var isDownloading = false

    var body: some View {
        NavigationStack {
            ZStack {
                MC1MapView(
                    points: [],
                    lines: [],
                    mapStyle: .standard,
                    isDarkMode: colorScheme == .dark,
                    showLabels: false,
                    showsUserLocation: true,
                    isInteractive: true,
                    showsScale: false,
                    cameraRegion: $cameraRegion,
                    cameraRegionVersion: 0,
                    onPointTap: nil,
                    onMapTap: nil,
                    onCameraRegionChange: { region in
                        cameraRegion = region
                    },
                    isStyleLoaded: $isStyleLoaded
                )
                .ignoresSafeArea(edges: .bottom)

                // Selection rectangle overlay
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(40)
                    .allowsHitTesting(false)
            }
            .navigationTitle(L10n.Settings.OfflineMaps.pickRegion)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Settings.OfflineMaps.cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Settings.OfflineMaps.download) {
                        downloadRegion()
                    }
                    .disabled(regionName.isEmpty || isDownloading)
                }
            }
            .safeAreaInset(edge: .bottom) {
                TextField(L10n.Settings.OfflineMaps.regionName, text: $regionName)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                    .background(.regularMaterial)
            }
        }
    }

    // MARK: - Download

    private func downloadRegion() {
        guard let region = cameraRegion else { return }
        isDownloading = true

        // Approximate inset to match the 40pt padding on the selection rectangle
        let paddingFraction = 0.15
        let latInset = region.span.latitudeDelta * paddingFraction
        let lonInset = region.span.longitudeDelta * paddingFraction
        let bounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(
                latitude: region.center.latitude - (region.span.latitudeDelta / 2 - latInset),
                longitude: region.center.longitude - (region.span.longitudeDelta / 2 - lonInset)
            ),
            ne: CLLocationCoordinate2D(
                latitude: region.center.latitude + (region.span.latitudeDelta / 2 - latInset),
                longitude: region.center.longitude + (region.span.longitudeDelta / 2 - lonInset)
            )
        )

        Task {
            defer { isDownloading = false }
            do {
                try await appState.offlineMapService.downloadRegion(name: regionName, bounds: bounds)
                dismiss()
            } catch {
                OfflineMapService.logger.error("Failed to download region: \(error.localizedDescription)")
                dismiss()
            }
        }
    }
}

#Preview {
    NavigationStack {
        OfflineMapSettingsView()
            .environment(\.appState, AppState())
    }
}
