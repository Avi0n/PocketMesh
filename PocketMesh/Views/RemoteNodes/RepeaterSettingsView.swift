import SwiftUI
import PocketMeshKit
import CoreLocation

struct RepeaterSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let session: RemoteNodeSessionDTO
    @State private var viewModel = RepeaterSettingsViewModel()
    @State private var showRebootConfirmation = false
    @State private var showingLocationPicker = false

    var body: some View {
        Form {
            headerSection
            deviceInfoSection
            radioSettingsSection      // Moved up - primary reason users access this screen
            identitySection
            behaviorSection
            securitySection
            actionsSection
        }
        .navigationTitle("Repeater Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.configure(appState: appState, session: session)
            await viewModel.registerHandlers(appState: appState)
            // Device Info auto-loads because isDeviceInfoExpanded = true by default
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .alert("Success", isPresented: $viewModel.showSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.successMessage ?? "Settings applied")
        }
        .confirmationDialog("Reboot Repeater?", isPresented: $showRebootConfirmation) {
            Button("Reboot", role: .destructive) {
                Task { await viewModel.reboot() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The repeater will restart and be temporarily unavailable.")
        }
        .sheet(isPresented: $showingLocationPicker) {
            LocationPickerView(
                initialCoordinate: CLLocationCoordinate2D(
                    latitude: viewModel.latitude,
                    longitude: viewModel.longitude
                )
            ) { coordinate in
                try await viewModel.applyLocation(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }
        }
    }

    // MARK: - Header Section (with connection status)

    private var headerSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    NodeAvatar(publicKey: session.publicKey, role: .repeater, size: 60)
                    Text(session.name)
                        .font(.headline)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Device Info Section (auto-expands on appear)

    private var deviceInfoSection: some View {
        ExpandableSettingsSection(
            title: "Device Info",
            icon: "info.circle",
            isExpanded: $viewModel.isDeviceInfoExpanded,
            isLoaded: { viewModel.deviceInfoLoaded },
            isLoading: $viewModel.isLoadingDeviceInfo,
            error: $viewModel.deviceInfoError,
            onLoad: { await viewModel.fetchDeviceInfo() }
        ) {
            LabeledContent("Firmware", value: viewModel.firmwareVersion ?? "\u{2014}")
            LabeledContent("Device Time", value: viewModel.deviceTime ?? "\u{2014}")
        }
    }

    // MARK: - Radio Settings Section (with restart warning banner)

    private var radioSettingsSection: some View {
        ExpandableSettingsSection(
            title: "Radio Parameters",
            icon: "antenna.radiowaves.left.and.right",
            isExpanded: $viewModel.isRadioExpanded,
            isLoaded: { viewModel.radioLoaded },
            isLoading: $viewModel.isLoadingRadio,
            error: $viewModel.radioError,
            onLoad: { await viewModel.fetchRadioSettings() }
        ) {
            // Restart warning banner (prominent, not just caption text)
            if viewModel.radioSettingsModified {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Changes require device restart")
                        .font(.subheadline)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.yellow.opacity(0.1))
                .clipShape(.rect(cornerRadius: 8))
            }

            HStack {
                Text("Frequency")
                Spacer()
                TextField("MHz", value: $viewModel.frequency, format: .number.precision(.fractionLength(3)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .onChange(of: viewModel.frequency) { _, _ in
                        viewModel.radioSettingsModified = true
                    }
                Text("MHz")
                    .foregroundStyle(.secondary)
            }

            Picker("Bandwidth", selection: $viewModel.bandwidth) {
                Text("62.5 kHz").tag(62.5)
                Text("125 kHz").tag(125.0)
                Text("250 kHz").tag(250.0)
                Text("500 kHz").tag(500.0)
            }
            .onChange(of: viewModel.bandwidth) { _, _ in
                viewModel.radioSettingsModified = true
            }

            Picker("Spreading Factor", selection: $viewModel.spreadingFactor) {
                ForEach(7...12, id: \.self) { sf in
                    Text("SF\(sf)").tag(sf)
                }
            }
            .onChange(of: viewModel.spreadingFactor) { _, _ in
                viewModel.radioSettingsModified = true
            }

            Picker("Coding Rate", selection: $viewModel.codingRate) {
                ForEach(5...8, id: \.self) { cr in
                    Text("4/\(cr)").tag(cr)
                }
            }
            .onChange(of: viewModel.codingRate) { _, _ in
                viewModel.radioSettingsModified = true
            }

            Stepper("TX Power: \(viewModel.txPower) dBm", value: $viewModel.txPower, in: 2...22)
                .onChange(of: viewModel.txPower) { _, _ in
                    viewModel.radioSettingsModified = true
                }

            // Single Apply button for all radio settings
            Button {
                Task { await viewModel.applyRadioSettings() }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isApplying {
                        ProgressView()
                    } else {
                        Text("Apply Radio Settings")
                    }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isApplying || !viewModel.radioSettingsModified)
        }
    }

    // MARK: - Identity Section (immediate apply on change)

    private var identitySection: some View {
        ExpandableSettingsSection(
            title: "Identity & Location",
            icon: "person.text.rectangle",
            isExpanded: $viewModel.isIdentityExpanded,
            isLoaded: { viewModel.identityLoaded },
            isLoading: $viewModel.isLoadingIdentity,
            error: $viewModel.identityError,
            onLoad: { await viewModel.fetchIdentity() }
        ) {
            TextField("Name", text: $viewModel.name)
                .textContentType(.name)
                .onSubmit {
                    viewModel.applyNameImmediately()
                }

            HStack {
                Text("Latitude")
                Spacer()
                TextField("Lat", value: $viewModel.latitude, format: .number.precision(.fractionLength(6)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
                    .onSubmit {
                        viewModel.applyLatitudeImmediately()
                    }
            }

            HStack {
                Text("Longitude")
                Spacer()
                TextField("Lon", value: $viewModel.longitude, format: .number.precision(.fractionLength(6)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
                    .onSubmit {
                        viewModel.applyLongitudeImmediately()
                    }
            }

            Button {
                showingLocationPicker = true
            } label: {
                Label("Set Location", systemImage: "mappin.and.ellipse")
            }

            Text("Text fields apply on keyboard dismiss. Map picker applies immediately.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Behavior Section (immediate apply on change)

    private var behaviorSection: some View {
        ExpandableSettingsSection(
            title: "Behavior",
            icon: "arrow.triangle.2.circlepath",
            isExpanded: $viewModel.isBehaviorExpanded,
            isLoaded: { viewModel.behaviorLoaded },
            isLoading: $viewModel.isLoadingBehavior,
            error: $viewModel.behaviorError,
            onLoad: { await viewModel.fetchBehaviorSettings() }
        ) {
            Toggle("Repeater Mode", isOn: $viewModel.repeaterEnabled)
                .onChange(of: viewModel.repeaterEnabled) { _, _ in
                    viewModel.applyRepeaterModeImmediately()
                }

            Stepper("Advert Interval (0-hop): \(viewModel.advertIntervalMinutes) min", value: $viewModel.advertIntervalMinutes, in: 1...120)
                .onChange(of: viewModel.advertIntervalMinutes) { _, _ in
                    viewModel.applyAdvertIntervalImmediately()
                }

            Stepper("Advert Interval (flood): \(viewModel.floodAdvertIntervalHours) hours", value: $viewModel.floodAdvertIntervalHours, in: 1...168)
                .onChange(of: viewModel.floodAdvertIntervalHours) { _, _ in
                    viewModel.applyFloodAdvertIntervalImmediately()
                }

            Stepper("Max Flood Hops: \(viewModel.floodMaxHops)", value: $viewModel.floodMaxHops, in: 0...10)
                .onChange(of: viewModel.floodMaxHops) { _, _ in
                    viewModel.applyFloodMaxImmediately()
                }

            Text("Changes apply immediately")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Security Section

    private var securitySection: some View {
        Section {
            SecureField("New Password", text: $viewModel.newPassword)
            SecureField("Confirm Password", text: $viewModel.confirmPassword)

            Button("Change Password") {
                Task { await viewModel.changePassword() }
            }
            .disabled(viewModel.isApplying || viewModel.newPassword.isEmpty || viewModel.newPassword != viewModel.confirmPassword)
        } header: {
            Label("Security", systemImage: "lock")
        } footer: {
            Text("Change the admin authentication password.")
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        Section("Device Actions") {
            Button("Force Advertisement") {
                Task { await viewModel.forceAdvert() }
            }

            Button("Reboot Device", role: .destructive) {
                showRebootConfirmation = true
            }
            .disabled(viewModel.isRebooting)

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }
}

#Preview {
    NavigationStack {
        RepeaterSettingsView(
            session: RemoteNodeSessionDTO(
                id: UUID(),
                deviceID: UUID(),
                publicKey: Data(repeating: 0x42, count: 32),
                name: "Mountain Peak Repeater",
                role: .repeater,
                latitude: 37.7749,
                longitude: -122.4194,
                isConnected: true,
                permissionLevel: .admin
            )
        )
        .environment(AppState())
    }
}
