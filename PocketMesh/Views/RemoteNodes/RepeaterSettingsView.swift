import SwiftUI
import PocketMeshServices
import CoreLocation

private enum SettingsField: Hashable {
    case frequency
    case txPower
    case advertInterval
    case floodAdvertInterval
    case floodMaxHops
    case identityName
    case contactInfo
}

struct RepeaterSettingsView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: SettingsField?

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
            SettingsHeaderSection(publicKey: session.publicKey, name: session.name)
            makeRadioSettingsSection()
            makeIdentitySection()
            makeContactInfoSection()
            makeBehaviorSection()
            makeSecuritySection()
            makeDeviceInfoSection()
            makeActionsSection()
        }
        .navigationTitle(L10n.RemoteNodes.RemoteNodes.Settings.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L10n.RemoteNodes.RemoteNodes.Settings.done) {
                    focusedField = nil
                }
            }
        }
        .task {
            await viewModel.configure(appState: appState, session: session)
        }
        .onDisappear {
            Task {
                await viewModel.cleanup()
            }
        }
        .alert(L10n.RemoteNodes.RemoteNodes.Settings.success, isPresented: $viewModel.showSuccessAlert) {
            Button(L10n.RemoteNodes.RemoteNodes.Settings.ok, role: .cancel) { }
        } message: {
            Text(viewModel.successMessage ?? L10n.RemoteNodes.RemoteNodes.Settings.settingsApplied)
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

    // MARK: - Subviews

    private func makeDeviceInfoSection() -> some View {
        DeviceInfoSection(viewModel: viewModel)
    }

    private func makeRadioSettingsSection() -> some View {
        RadioSettingsSection(
            viewModel: viewModel,
            focusedField: $focusedField,
            bandwidthOptionsKHz: bandwidthOptionsKHz
        )
    }

    private func makeIdentitySection() -> some View {
        IdentitySection(
            viewModel: viewModel,
            focusedField: $focusedField,
            onPickLocation: { showingLocationPicker = true }
        )
    }

    private func makeContactInfoSection() -> some View {
        ContactInfoSection(viewModel: viewModel, focusedField: $focusedField)
    }

    private func makeBehaviorSection() -> some View {
        BehaviorSection(viewModel: viewModel, focusedField: $focusedField)
    }

    private func makeSecuritySection() -> some View {
        SecuritySection(viewModel: viewModel)
    }

    private func makeActionsSection() -> some View {
        ActionsSection(
            viewModel: viewModel,
            showRebootConfirmation: $showRebootConfirmation
        )
    }
}

// MARK: - Settings Header Section

private struct SettingsHeaderSection: View {
    let publicKey: Data
    let name: String

    var body: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    NodeAvatar(publicKey: publicKey, role: .repeater, size: 60)
                    Text(name)
                        .font(.headline)
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }
}

// MARK: - Device Info Section

private struct DeviceInfoSection: View {
    @Bindable var viewModel: RepeaterSettingsViewModel

    var body: some View {
        ExpandableSettingsSection(
            title: L10n.RemoteNodes.RemoteNodes.Settings.deviceInfo,
            icon: "info.circle",
            isExpanded: $viewModel.isDeviceInfoExpanded,
            isLoaded: { viewModel.deviceInfoLoaded },
            isLoading: $viewModel.isLoadingDeviceInfo,
            error: $viewModel.deviceInfoError,
            onLoad: { await viewModel.fetchDeviceInfo() },
            footer: L10n.RemoteNodes.RemoteNodes.Settings.deviceInfoFooter
        ) {
            LabeledContent(L10n.RemoteNodes.RemoteNodes.Settings.firmware, value: viewModel.firmwareVersion ?? "\u{2014}")
            LabeledContent(L10n.RemoteNodes.RemoteNodes.Settings.deviceTime, value: viewModel.deviceTime ?? "\u{2014}")
        }
    }
}

// MARK: - Radio Settings Section

private struct RadioSettingsSection: View {
    @Bindable var viewModel: RepeaterSettingsViewModel
    var focusedField: FocusState<SettingsField?>.Binding
    let bandwidthOptionsKHz: [Double]

    var body: some View {
        ExpandableSettingsSection(
            title: L10n.RemoteNodes.RemoteNodes.Settings.radioParameters,
            icon: "antenna.radiowaves.left.and.right",
            isExpanded: $viewModel.isRadioExpanded,
            isLoaded: { viewModel.radioLoaded },
            isLoading: $viewModel.isLoadingRadio,
            error: $viewModel.radioError,
            onLoad: { await viewModel.fetchRadioSettings() },
            footer: L10n.RemoteNodes.RemoteNodes.Settings.radioFooter
        ) {
            if viewModel.radioSettingsModified {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(L10n.RemoteNodes.RemoteNodes.Settings.radioRestartWarning)
                        .font(.subheadline)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.yellow.opacity(0.1))
                .clipShape(.rect(cornerRadius: 8))
            }

            HStack {
                Text(L10n.RemoteNodes.RemoteNodes.Settings.frequencyMHz)
                Spacer()
                if let frequency = viewModel.frequency {
                    TextField(L10n.RemoteNodes.RemoteNodes.Settings.mhz, value: Binding(
                        get: { frequency },
                        set: { viewModel.frequency = $0 }
                    ), format: .number.precision(.fractionLength(3)).locale(.posix))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .focused(focusedField, equals: .frequency)
                        .onChange(of: viewModel.frequency) { _, _ in
                            viewModel.radioSettingsModified = true
                        }
                } else {
                    Text(viewModel.isLoadingRadio ? L10n.RemoteNodes.RemoteNodes.Settings.loading : (viewModel.radioError != nil ? L10n.RemoteNodes.RemoteNodes.Settings.failedToLoad : "—"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)
                }
            }

            if let bandwidth = viewModel.bandwidth {
                Picker(L10n.RemoteNodes.RemoteNodes.Settings.bandwidthKHz, selection: Binding(
                    get: { bandwidth },
                    set: { viewModel.bandwidth = $0 }
                )) {
                    ForEach(bandwidthOptionsKHz, id: \.self) { bwKHz in
                        Text(RadioOptions.formatBandwidth(UInt32(bwKHz * 1000)))
                            .tag(bwKHz)
                            .accessibilityLabel(L10n.RemoteNodes.RemoteNodes.Settings.Accessibility.bandwidthLabel(RadioOptions.formatBandwidth(UInt32(bwKHz * 1000))))
                    }
                }
                .pickerStyle(.menu)
                .tint(.primary)
                .accessibilityHint(L10n.RemoteNodes.RemoteNodes.Settings.bandwidthHint)
                .onChange(of: viewModel.bandwidth) { _, _ in
                    viewModel.radioSettingsModified = true
                }
            } else {
                HStack {
                    Text(L10n.RemoteNodes.RemoteNodes.Settings.bandwidthKHz)
                    Spacer()
                    Text(viewModel.isLoadingRadio ? L10n.RemoteNodes.RemoteNodes.Settings.loading : (viewModel.radioError != nil ? L10n.RemoteNodes.RemoteNodes.Settings.failedToLoad : "—"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let spreadingFactor = viewModel.spreadingFactor {
                Picker(L10n.RemoteNodes.RemoteNodes.Settings.spreadingFactor, selection: Binding(
                    get: { spreadingFactor },
                    set: { viewModel.spreadingFactor = $0 }
                )) {
                    ForEach(RadioOptions.spreadingFactors, id: \.self) { sf in
                        Text(sf, format: .number)
                            .tag(sf)
                            .accessibilityLabel(L10n.RemoteNodes.RemoteNodes.Settings.Accessibility.spreadingFactorLabel(sf))
                    }
                }
                .pickerStyle(.menu)
                .tint(.primary)
                .accessibilityHint(L10n.RemoteNodes.RemoteNodes.Settings.spreadingFactorHint)
                .onChange(of: viewModel.spreadingFactor) { _, _ in
                    viewModel.radioSettingsModified = true
                }
            } else {
                HStack {
                    Text(L10n.RemoteNodes.RemoteNodes.Settings.spreadingFactor)
                    Spacer()
                    Text(viewModel.isLoadingRadio ? L10n.RemoteNodes.RemoteNodes.Settings.loading : (viewModel.radioError != nil ? L10n.RemoteNodes.RemoteNodes.Settings.failedToLoad : "—"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let codingRate = viewModel.codingRate {
                Picker(L10n.RemoteNodes.RemoteNodes.Settings.codingRate, selection: Binding(
                    get: { codingRate },
                    set: { viewModel.codingRate = $0 }
                )) {
                    ForEach(RadioOptions.codingRates, id: \.self) { cr in
                        Text("\(cr)")
                            .tag(cr)
                            .accessibilityLabel(L10n.RemoteNodes.RemoteNodes.Settings.Accessibility.codingRateLabel(cr))
                    }
                }
                .pickerStyle(.menu)
                .tint(.primary)
                .accessibilityHint(L10n.RemoteNodes.RemoteNodes.Settings.codingRateHint)
                .onChange(of: viewModel.codingRate) { _, _ in
                    viewModel.radioSettingsModified = true
                }
            } else {
                HStack {
                    Text(L10n.RemoteNodes.RemoteNodes.Settings.codingRate)
                    Spacer()
                    Text(viewModel.isLoadingRadio ? L10n.RemoteNodes.RemoteNodes.Settings.loading : (viewModel.radioError != nil ? L10n.RemoteNodes.RemoteNodes.Settings.failedToLoad : "—"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(L10n.RemoteNodes.RemoteNodes.Settings.txPowerDbm)
                Spacer()
                if let txPower = viewModel.txPower {
                    TextField(L10n.RemoteNodes.RemoteNodes.Settings.dbm, value: Binding(
                        get: { txPower },
                        set: { viewModel.txPower = $0 }
                    ), format: .number)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .focused(focusedField, equals: .txPower)
                        .onChange(of: viewModel.txPower) { _, _ in
                            viewModel.radioSettingsModified = true
                        }
                } else {
                    Text(viewModel.isLoadingRadio ? L10n.RemoteNodes.RemoteNodes.Settings.loading : (viewModel.radioError != nil ? L10n.RemoteNodes.RemoteNodes.Settings.failedToLoad : "—"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
            }

            Button {
                Task { await viewModel.applyRadioSettings() }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isApplying {
                        ProgressView()
                    } else {
                        Text(L10n.RemoteNodes.RemoteNodes.Settings.applyRadioSettings)
                            .foregroundStyle(viewModel.radioSettingsModified ? Color.accentColor : .secondary)
                    }
                    Spacer()
                }
            }
            .disabled(viewModel.isApplying || !viewModel.radioSettingsModified)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
    }
}

// MARK: - Identity Section

private struct IdentitySection: View {
    @Bindable var viewModel: RepeaterSettingsViewModel
    var focusedField: FocusState<SettingsField?>.Binding
    let onPickLocation: () -> Void

    var body: some View {
        ExpandableSettingsSection(
            title: L10n.RemoteNodes.RemoteNodes.Settings.identityLocation,
            icon: "person.text.rectangle",
            isExpanded: $viewModel.isIdentityExpanded,
            isLoaded: { viewModel.identityLoaded },
            isLoading: $viewModel.isLoadingIdentity,
            error: $viewModel.identityError,
            onLoad: { await viewModel.fetchIdentity() },
            footer: L10n.RemoteNodes.RemoteNodes.Settings.identityFooter
        ) {
            if viewModel.isLoadingIdentity && viewModel.name == nil {
                HStack {
                    Text(L10n.RemoteNodes.RemoteNodes.name)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(L10n.RemoteNodes.RemoteNodes.Settings.loading)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                TextField(L10n.RemoteNodes.RemoteNodes.name, text: Binding(
                    get: { viewModel.name ?? "" },
                    set: { viewModel.name = $0 }
                ))
                    .textContentType(.name)
                    .submitLabel(.done)
                    .focused(focusedField, equals: .identityName)
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            }

            HStack {
                Text(L10n.RemoteNodes.RemoteNodes.Settings.latitude)
                Spacer()
                if let latitude = viewModel.latitude {
                    TextField(L10n.RemoteNodes.RemoteNodes.Settings.lat, value: Binding(
                        get: { latitude },
                        set: { viewModel.latitude = $0 }
                    ), format: .number.precision(.fractionLength(6)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                } else {
                    Text(viewModel.isLoadingIdentity ? L10n.RemoteNodes.RemoteNodes.Settings.loading : (viewModel.identityError != nil ? L10n.RemoteNodes.RemoteNodes.Settings.failedToLoad : "—"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .trailing)
                }
            }

            HStack {
                Text(L10n.RemoteNodes.RemoteNodes.Settings.longitude)
                Spacer()
                if let longitude = viewModel.longitude {
                    TextField(L10n.RemoteNodes.RemoteNodes.Settings.lon, value: Binding(
                        get: { longitude },
                        set: { viewModel.longitude = $0 }
                    ), format: .number.precision(.fractionLength(6)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                } else {
                    Text(viewModel.isLoadingIdentity ? L10n.RemoteNodes.RemoteNodes.Settings.loading : (viewModel.identityError != nil ? L10n.RemoteNodes.RemoteNodes.Settings.failedToLoad : "—"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .trailing)
                }
            }

            Button {
                onPickLocation()
            } label: {
                Label(L10n.RemoteNodes.RemoteNodes.Settings.pickOnMap, systemImage: "mappin.and.ellipse")
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }

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
                        Text(L10n.RemoteNodes.RemoteNodes.Settings.applyIdentitySettings)
                            .foregroundStyle(viewModel.identitySettingsModified ? Color.accentColor : .secondary)
                            .transition(.opacity)
                    }
                    Spacer()
                }
                .animation(.default, value: viewModel.identityApplySuccess)
            }
            .disabled(viewModel.isApplying || viewModel.identityApplySuccess || !viewModel.identitySettingsModified)
        }
    }
}

// MARK: - Contact Info Section

private struct ContactInfoSection: View {
    @Bindable var viewModel: RepeaterSettingsViewModel
    var focusedField: FocusState<SettingsField?>.Binding

    private static let maxCharacters = 119

    var body: some View {
        ExpandableSettingsSection(
            title: L10n.RemoteNodes.RemoteNodes.Settings.contactInfo,
            icon: "person.crop.rectangle",
            isExpanded: $viewModel.isContactInfoExpanded,
            isLoaded: { viewModel.contactInfoLoaded },
            isLoading: $viewModel.isLoadingContactInfo,
            error: $viewModel.contactInfoError,
            onLoad: { await viewModel.fetchContactInfo() },
            footer: L10n.RemoteNodes.RemoteNodes.Settings.contactInfoFooter
        ) {
            TextField(
                L10n.RemoteNodes.RemoteNodes.Settings.contactInfoPlaceholder,
                text: Binding(
                    get: { viewModel.ownerInfo ?? "" },
                    set: { viewModel.ownerInfo = $0 }
                ),
                axis: .vertical
            )
            .lineLimit(3...6)
            .focused(focusedField, equals: .contactInfo)
            .overlay(alignment: .bottomTrailing) {
                let count = viewModel.ownerInfoCharCount
                Text(L10n.RemoteNodes.RemoteNodes.Settings.contactInfoCharCount(count))
                    .font(.caption2)
                    .foregroundStyle(count > Self.maxCharacters ? Color.red : Color.secondary.opacity(0.6))
                    .padding(4)
            }

            Button {
                Task { await viewModel.applyContactInfoSettings() }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isApplying {
                        ProgressView()
                    } else if viewModel.contactInfoApplySuccess {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text(L10n.RemoteNodes.RemoteNodes.Settings.applyContactInfo)
                            .foregroundStyle(viewModel.contactInfoSettingsModified ? Color.accentColor : .secondary)
                            .transition(.opacity)
                    }
                    Spacer()
                }
                .animation(.default, value: viewModel.contactInfoApplySuccess)
            }
            .disabled(viewModel.isApplying || viewModel.contactInfoApplySuccess || !viewModel.contactInfoSettingsModified || viewModel.ownerInfoCharCount > Self.maxCharacters)
        }
    }
}

// MARK: - Behavior Section

private struct BehaviorSection: View {
    @Bindable var viewModel: RepeaterSettingsViewModel
    var focusedField: FocusState<SettingsField?>.Binding

    var body: some View {
        ExpandableSettingsSection(
            title: L10n.RemoteNodes.RemoteNodes.Settings.behavior,
            icon: "slider.horizontal.3",
            isExpanded: $viewModel.isBehaviorExpanded,
            isLoaded: { viewModel.behaviorLoaded },
            isLoading: $viewModel.isLoadingBehavior,
            error: $viewModel.behaviorError,
            onLoad: { await viewModel.fetchBehaviorSettings() },
            footer: L10n.RemoteNodes.RemoteNodes.Settings.behaviorFooter
        ) {
            Toggle(L10n.RemoteNodes.RemoteNodes.Settings.repeaterMode, isOn: Binding(
                get: { viewModel.repeaterEnabled ?? false },
                set: { viewModel.repeaterEnabled = $0 }
            ))
                .overlay(alignment: .trailing) {
                    if viewModel.repeaterEnabled == nil && viewModel.isLoadingBehavior {
                        Text(L10n.RemoteNodes.RemoteNodes.Settings.loading)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 60)
                    }
                }

            HStack {
                Text(L10n.RemoteNodes.RemoteNodes.Settings.advertInterval0Hop)
                Spacer()
                if let interval = viewModel.advertIntervalMinutes {
                    TextField(L10n.RemoteNodes.RemoteNodes.Settings.min, value: Binding(
                        get: { interval },
                        set: { viewModel.advertIntervalMinutes = $0 }
                    ), format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .focused(focusedField, equals: .advertInterval)
                    Text(L10n.RemoteNodes.RemoteNodes.Settings.min)
                        .foregroundStyle(.secondary)
                } else {
                    Text(viewModel.isLoadingBehavior ? L10n.RemoteNodes.RemoteNodes.Settings.loading : (viewModel.behaviorError != nil ? L10n.RemoteNodes.RemoteNodes.Settings.failedToLoad : "—"))
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
                Text(L10n.RemoteNodes.RemoteNodes.Settings.advertIntervalFlood)
                Spacer()
                if let interval = viewModel.floodAdvertIntervalHours {
                    TextField(L10n.RemoteNodes.RemoteNodes.Settings.hrs, value: Binding(
                        get: { interval },
                        set: { viewModel.floodAdvertIntervalHours = $0 }
                    ), format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .focused(focusedField, equals: .floodAdvertInterval)
                    Text(L10n.RemoteNodes.RemoteNodes.Settings.hrs)
                        .foregroundStyle(.secondary)
                } else {
                    Text(viewModel.isLoadingBehavior ? L10n.RemoteNodes.RemoteNodes.Settings.loading : (viewModel.behaviorError != nil ? L10n.RemoteNodes.RemoteNodes.Settings.failedToLoad : "—"))
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
                Text(L10n.RemoteNodes.RemoteNodes.Settings.maxFloodHops)
                Spacer()
                if let hops = viewModel.floodMaxHops {
                    TextField(L10n.RemoteNodes.RemoteNodes.Settings.hops, value: Binding(
                        get: { hops },
                        set: { viewModel.floodMaxHops = $0 }
                    ), format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .focused(focusedField, equals: .floodMaxHops)
                    Text(L10n.RemoteNodes.RemoteNodes.Settings.hops)
                        .foregroundStyle(.secondary)
                } else {
                    Text(viewModel.isLoadingBehavior ? L10n.RemoteNodes.RemoteNodes.Settings.loading : (viewModel.behaviorError != nil ? L10n.RemoteNodes.RemoteNodes.Settings.failedToLoad : "—"))
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
                        Text(L10n.RemoteNodes.RemoteNodes.Settings.applyBehaviorSettings)
                            .foregroundStyle(viewModel.behaviorSettingsModified ? Color.accentColor : .secondary)
                            .transition(.opacity)
                    }
                    Spacer()
                }
                .animation(.default, value: viewModel.behaviorApplySuccess)
            }
            .disabled(viewModel.isApplying || viewModel.behaviorApplySuccess || !viewModel.behaviorSettingsModified)
        }
    }
}

// MARK: - Security Section

private struct SecuritySection: View {
    @Bindable var viewModel: RepeaterSettingsViewModel

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $viewModel.isSecurityExpanded) {
                SecureField(L10n.RemoteNodes.RemoteNodes.Settings.newPassword, text: $viewModel.newPassword)
                SecureField(L10n.RemoteNodes.RemoteNodes.Settings.confirmPassword, text: $viewModel.confirmPassword)

                Button(L10n.RemoteNodes.RemoteNodes.Settings.changePassword) {
                    Task { await viewModel.changePassword() }
                }
                .disabled(viewModel.isApplying || viewModel.newPassword.isEmpty || viewModel.newPassword != viewModel.confirmPassword)
            } label: {
                Label(L10n.RemoteNodes.RemoteNodes.Settings.security, systemImage: "lock")
            }
        } footer: {
            Text(L10n.RemoteNodes.RemoteNodes.Settings.securityFooter)
        }
    }
}

// MARK: - Actions Section

private struct ActionsSection: View {
    let viewModel: RepeaterSettingsViewModel
    @Binding var showRebootConfirmation: Bool

    var body: some View {
        Section(L10n.RemoteNodes.RemoteNodes.Settings.deviceActions) {
            Button(L10n.RemoteNodes.RemoteNodes.Settings.sendAdvert) {
                Task { await viewModel.forceAdvert() }
            }

            Button(L10n.RemoteNodes.RemoteNodes.Settings.syncTime) {
                Task { await viewModel.syncTime() }
            }
            .disabled(viewModel.isApplying)

            Button(L10n.RemoteNodes.RemoteNodes.Settings.rebootDevice, role: .destructive) {
                showRebootConfirmation = true
            }
            .disabled(viewModel.isRebooting)
            .confirmationDialog(L10n.RemoteNodes.RemoteNodes.Settings.rebootConfirmTitle, isPresented: $showRebootConfirmation) {
                Button(L10n.RemoteNodes.RemoteNodes.Settings.reboot, role: .destructive) {
                    Task { await viewModel.reboot() }
                }
                Button(L10n.RemoteNodes.RemoteNodes.cancel, role: .cancel) { }
            } message: {
                Text(L10n.RemoteNodes.RemoteNodes.Settings.rebootMessage)
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
        .environment(\.appState, AppState())
    }
}
