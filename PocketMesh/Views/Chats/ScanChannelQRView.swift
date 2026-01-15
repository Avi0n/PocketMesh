import SwiftUI
import VisionKit
import AudioToolbox
import PocketMeshServices

/// View for scanning a channel QR code to join
struct ScanChannelQRView: View {
    @Environment(AppState.self) private var appState

    let availableSlots: [UInt8]
    let onComplete: (ChannelDTO?) -> Void

    @State private var scannedChannel: ScannedChannel?
    @State private var selectedSlot: UInt8
    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var cameraPermissionDenied = false

    struct ScannedChannel {
        let name: String
        let secret: Data
    }

    init(availableSlots: [UInt8], onComplete: @escaping (ChannelDTO?) -> Void) {
        self.availableSlots = availableSlots
        self.onComplete = onComplete
        self._selectedSlot = State(initialValue: availableSlots.first ?? 1)
    }

    var body: some View {
        Group {
            if scannedChannel != nil {
                confirmationView
            } else if cameraPermissionDenied {
                cameraPermissionDeniedView
            } else {
                scannerView
            }
        }
        .navigationTitle("Scan QR Code")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Scanner View

    private var scannerView: some View {
        ZStack {
            if QRDataScannerView.isSupported && QRDataScannerView.isAvailable {
                QRDataScannerView { result in
                    handleScanResult(result)
                } onPermissionDenied: {
                    cameraPermissionDenied = true
                }
            } else {
                // Fallback for unsupported devices
                ContentUnavailableView(
                    "Scanner Not Available",
                    systemImage: "qrcode.viewfinder",
                    description: Text("QR scanning is not supported on this device")
                )
            }

            // Overlay with scan frame
            VStack {
                Spacer()

                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white, lineWidth: 3)
                    .frame(width: 250, height: 250)

                Spacer()

                Text("Point your camera at a channel QR code")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding()
                    .background(.black.opacity(0.6), in: .capsule)
                    .padding(.bottom, 50)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Confirmation View

    private var confirmationView: some View {
        Form {
            if let channel = scannedChannel {
                Section {
                    LabeledContent("Channel Name", value: channel.name)

                    LabeledContent("Secret Key") {
                        Text(channel.secret.hexString())
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Channel Details")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task {
                            await joinChannel()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isJoining {
                                ProgressView()
                            } else {
                                Text("Join Channel")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isJoining)

                    Button("Scan Again") {
                        scannedChannel = nil
                        errorMessage = nil
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Permission Denied View

    private var cameraPermissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Camera Access Required")
                .font(.title2)
                .bold()

            Text("Please enable camera access in Settings to scan QR codes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Private Methods

    private func handleScanResult(_ result: String) {
        // Parse URL: meshcore://channel/add?name=<name>&secret=<hex>
        guard let url = URL(string: result),
              url.scheme == "meshcore",
              url.host == "channel",
              url.path == "/add",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            errorMessage = "Invalid QR code format"
            return
        }

        let name = queryItems.first(where: { $0.name == "name" })?.value ?? ""
        let secretHex = queryItems.first(where: { $0.name == "secret" })?.value ?? ""

        guard !name.isEmpty, let secret = Data(hexString: secretHex), secret.count == 16 else {
            errorMessage = "Invalid channel data in QR code"
            return
        }

        scannedChannel = ScannedChannel(name: name, secret: secret)
    }

    private func joinChannel() async {
        guard let deviceID = appState.connectedDevice?.id,
              let channel = scannedChannel else {
            errorMessage = "No device connected"
            return
        }

        isJoining = true
        errorMessage = nil

        do {
            guard let channelService = appState.services?.channelService else {
                errorMessage = "Services not available"
                return
            }
            try await channelService.setChannelWithSecret(
                deviceID: deviceID,
                index: selectedSlot,
                name: channel.name,
                secret: channel.secret
            )

            // Fetch the joined channel to return it
            var joinedChannel: ChannelDTO?
            if let channels = try? await appState.services?.dataStore.fetchChannels(deviceID: deviceID) {
                joinedChannel = channels.first { $0.index == selectedSlot }
            }
            onComplete(joinedChannel)
        } catch {
            errorMessage = error.localizedDescription
        }

        isJoining = false
    }
}

// MARK: - QR Scanner using DataScannerViewController

struct QRDataScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onPermissionDenied: () -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported
    }

    static var isAvailable: Bool {
        DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        // Start scanning when view appears
        if !controller.isScanning {
            try? controller.startScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    @MainActor
    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var hasScanned = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            processItem(item, scanner: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            // Auto-capture first QR code detected
            guard !hasScanned, let item = addedItems.first else { return }
            processItem(item, scanner: dataScanner)
        }

        private func processItem(_ item: RecognizedItem, scanner: DataScannerViewController) {
            guard !hasScanned else { return }

            if case .barcode(let barcode) = item,
               let payload = barcode.payloadStringValue {
                hasScanned = true
                scanner.stopScanning()
                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                onScan(payload)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ScanChannelQRView(availableSlots: [1, 2, 3], onComplete: { _ in })
    }
    .environment(AppState())
}
