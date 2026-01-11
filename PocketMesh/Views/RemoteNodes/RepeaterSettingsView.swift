import SwiftUI
import PocketMeshServices
import CoreLocation

struct RepeaterSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case frequency
        case txPower
        case advertInterval
        case floodAdvertInterval
        case floodMaxHops
    }

    let session: RemoteNodeSessionDTO
    @State private var viewModel = RepeaterSettingsViewModel()
    @State private var showRebootConfirmation = false
    @State private var showingLocationPicker = false

    /// Bandwidth options in kHz for CLI protocol (derived from RadioOptions.bandwidthsHz)
    private var bandwidthOptionsKHz: [Double] {
        RadioOptions.bandwidthsHz.map { Double($0) / 1000.0 }
    }

    var body: some View {
        Form {
            headerSection
            radioSettingsSection
            identitySection
            behaviorSection
            securitySection
            deviceInfoSection
            actionsSection
        }
        .navigationTitle("Repeater Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
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
        .sheet(isPresented: $showingLocationPicker) {
            LocationPickerView(
                initialCoordinate: CLLocationCoordinate2D(
                    latitude: viewModel.latitude ?? 0,
                    longitude: viewModel.longitude ?? 0
                )
            ) { coordinate in
                viewModel.setLocationFromPicker(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    NodeAvatar(publicKey: session.publicKey, role: .repeater, size: 60)
                    Text(session.name)
                        .font(.headline)
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
                    Text("Applying these changes will restart the repeater")
                        .font(.subheadline)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.yellow.opacity(0.1))
                .clipShape(.rect(cornerRadius: 8))
            }

            HStack {
                Text("Frequency (MHz)")
                Spacer()
                if let frequency = viewModel.frequency {
                    TextField("MHz", value: Binding(
                        get: { frequency },
                        set: { viewModel.frequency = $0 }
                    ), format: .number.precision(.fractionLength(3)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .focused($focusedField, equals: .frequency)
                        .onChange(of: viewModel.frequency) { _, _ in
                            viewModel.radioSettingsModified = true
                        }
                } else {
                    Text("loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)
                }
            }

            Picker("Bandwidth (kHz)", selection: Binding(
                get: { viewModel.bandwidth ?? 125.0 },
                set: { viewModel.bandwidth = $0 }
            )) {
                ForEach(bandwidthOptionsKHz, id: \.self) { bwKHz in
                    Text("\(RadioOptions.formatBandwidth(UInt32(bwKHz * 1000))) kHz")
                        .tag(bwKHz)
                        .accessibilityLabel("\(RadioOptions.formatBandwidth(UInt32(bwKHz * 1000))) kilohertz")
                }
            }
            .pickerStyle(.menu)
            .tint(.primary)
            .accessibilityHint("Lower values increase range but decrease speed")
            .onChange(of: viewModel.bandwidth) { _, _ in
                viewModel.radioSettingsModified = true
            }

            Picker("Spreading Factor", selection: Binding(
                get: { viewModel.spreadingFactor ?? 10 },
                set: { viewModel.spreadingFactor = $0 }
            )) {
                ForEach(RadioOptions.spreadingFactors, id: \.self) { sf in
                    Text("SF\(sf)")
                        .tag(sf)
                        .accessibilityLabel("Spreading factor \(sf)")
                }
            }
            .pickerStyle(.menu)
            .tint(.primary)
            .accessibilityHint("Higher values increase range but decrease speed")
            .onChange(of: viewModel.spreadingFactor) { _, _ in
                viewModel.radioSettingsModified = true
            }

            Picker("Coding Rate", selection: Binding(
                get: { viewModel.codingRate ?? 8 },
                set: { viewModel.codingRate = $0 }
            )) {
                ForEach(RadioOptions.codingRates, id: \.self) { cr in
                    Text("\(cr)")
                        .tag(cr)
                        .accessibilityLabel("Coding rate \(cr)")
                }
            }
            .pickerStyle(.menu)
            .tint(.primary)
            .accessibilityHint("Higher values add error correction but decrease speed")
            .onChange(of: viewModel.codingRate) { _, _ in
                viewModel.radioSettingsModified = true
            }

            HStack {
                Text("TX Power (dBm)")
                Spacer()
                if let txPower = viewModel.txPower {
                    TextField("dBm", value: Binding(
                        get: { txPower },
                        set: { viewModel.txPower = $0 }
                    ), format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .focused($focusedField, equals: .txPower)
                        .onChange(of: viewModel.txPower) { _, _ in
                            viewModel.radioSettingsModified = true
                        }
                } else {
                    Text("loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
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
            .disabled(viewModel.isApplying || !viewModel.radioSettingsModified)
        }
    }

    // MARK: - Identity Section

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
            if let name = viewModel.name {
                TextField("Name", text: Binding(
                    get: { name },
                    set: { viewModel.name = $0 }
                ))
                    .textContentType(.name)
            } else if viewModel.isLoadingIdentity {
                HStack {
                    Text("Name")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                TextField("Name", text: Binding(
                    get: { "" },
                    set: { viewModel.name = $0 }
                ))
                    .textContentType(.name)
            }

            HStack {
                Text("Latitude")
                Spacer()
                if let latitude = viewModel.latitude {
                    TextField("Lat", value: Binding(
                        get: { latitude },
                        set: { viewModel.latitude = $0 }
                    ), format: .number.precision(.fractionLength(6)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                } else {
                    Text("loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .trailing)
                }
            }

            HStack {
                Text("Longitude")
                Spacer()
                if let longitude = viewModel.longitude {
                    TextField("Lon", value: Binding(
                        get: { longitude },
                        set: { viewModel.longitude = $0 }
                    ), format: .number.precision(.fractionLength(6)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                } else {
                    Text("loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .trailing)
                }
            }

            Button {
                showingLocationPicker = true
            } label: {
                Label("Pick on Map", systemImage: "mappin.and.ellipse")
            }

            Button {
                Task { await viewModel.applyIdentitySettings() }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isApplying {
                        ProgressView()
                    } else if viewModel.identityApplySuccess {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text("Apply Identity Settings")
                            .transition(.opacity)
                    }
                    Spacer()
                }
                .animation(.default, value: viewModel.identityApplySuccess)
            }
            .disabled(viewModel.isApplying || viewModel.identityApplySuccess || !viewModel.identitySettingsModified)
        }
    }

    // MARK: - Behavior Section

    private var behaviorSection: some View {
        ExpandableSettingsSection(
            title: "Behavior",
            icon: "slider.horizontal.3",
            isExpanded: $viewModel.isBehaviorExpanded,
            isLoaded: { viewModel.behaviorLoaded },
            isLoading: $viewModel.isLoadingBehavior,
            error: $viewModel.behaviorError,
            onLoad: { await viewModel.fetchBehaviorSettings() }
        ) {
            Toggle("Repeater Mode", isOn: Binding(
                get: { viewModel.repeaterEnabled ?? false },
                set: { viewModel.repeaterEnabled = $0 }
            ))
                .overlay(alignment: .trailing) {
                    if viewModel.repeaterEnabled == nil && viewModel.isLoadingBehavior {
                        Text("loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 60)
                    }
                }

            HStack {
                Text("Advert Interval (0-hop)")
                Spacer()
                if let interval = viewModel.advertIntervalMinutes {
                    TextField("min", value: Binding(
                        get: { interval },
                        set: { viewModel.advertIntervalMinutes = $0 }
                    ), format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .focused($focusedField, equals: .advertInterval)
                    Text("min")
                        .foregroundStyle(.secondary)
                } else {
                    Text("loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = viewModel.advertIntervalError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Text("Advert Interval (flood)")
                Spacer()
                if let interval = viewModel.floodAdvertIntervalHours {
                    TextField("hrs", value: Binding(
                        get: { interval },
                        set: { viewModel.floodAdvertIntervalHours = $0 }
                    ), format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .focused($focusedField, equals: .floodAdvertInterval)
                    Text("hrs")
                        .foregroundStyle(.secondary)
                } else {
                    Text("loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = viewModel.floodAdvertIntervalError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Text("Max Flood Hops")
                Spacer()
                if let hops = viewModel.floodMaxHops {
                    TextField("hops", value: Binding(
                        get: { hops },
                        set: { viewModel.floodMaxHops = $0 }
                    ), format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .focused($focusedField, equals: .floodMaxHops)
                    Text("hops")
                        .foregroundStyle(.secondary)
                } else {
                    Text("loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = viewModel.floodMaxHopsError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await viewModel.applyBehaviorSettings() }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isApplying {
                        ProgressView()
                    } else if viewModel.behaviorApplySuccess {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text("Apply Behavior Settings")
                            .transition(.opacity)
                    }
                    Spacer()
                }
                .animation(.default, value: viewModel.behaviorApplySuccess)
            }
            .disabled(viewModel.isApplying || viewModel.behaviorApplySuccess || !viewModel.behaviorSettingsModified)
        }
    }

    // MARK: - Security Section

    private var securitySection: some View {
        Section {
            DisclosureGroup(isExpanded: $viewModel.isSecurityExpanded) {
                SecureField("New Password", text: $viewModel.newPassword)
                SecureField("Confirm Password", text: $viewModel.confirmPassword)

                Button("Change Password") {
                    Task { await viewModel.changePassword() }
                }
                .disabled(viewModel.isApplying || viewModel.newPassword.isEmpty || viewModel.newPassword != viewModel.confirmPassword)

                Text("Change the admin authentication password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } label: {
                Label("Security", systemImage: "lock")
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        Section("Device Actions") {
            Button("Send Advert") {
                Task { await viewModel.forceAdvert() }
            }

            Button("Sync Time") {
                Task { await viewModel.syncTime() }
            }
            .disabled(viewModel.isApplying)

            Button("Reboot Device", role: .destructive) {
                showRebootConfirmation = true
            }
            .disabled(viewModel.isRebooting)
            .confirmationDialog("Reboot Repeater?", isPresented: $showRebootConfirmation) {
                Button("Reboot", role: .destructive) {
                    Task { await viewModel.reboot() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The repeater will restart and be temporarily unavailable.")
            }

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
