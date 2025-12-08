import SwiftUI
import AVFoundation
import PocketMeshKit

/// View for scanning a channel QR code to join
struct ScanChannelQRView: View {
    @Environment(AppState.self) private var appState

    let availableSlots: [UInt8]
    let onComplete: () -> Void

    @State private var scannedChannel: ScannedChannel?
    @State private var selectedSlot: UInt8
    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var cameraPermissionDenied = false

    struct ScannedChannel {
        let name: String
        let secret: Data
    }

    init(availableSlots: [UInt8], onComplete: @escaping () -> Void) {
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
            QRScannerView { result in
                handleScanResult(result)
            } onPermissionDenied: {
                cameraPermissionDenied = true
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
                        Text(channel.secret.hexString)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Picker("Channel Slot", selection: $selectedSlot) {
                        ForEach(availableSlots, id: \.self) { slot in
                            Text("Slot \(slot)").tag(slot)
                        }
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
        // Parse URL: pocketmesh://channel?name=<name>&secret=<hex>
        guard let url = URL(string: result),
              url.scheme == "pocketmesh",
              url.host == "channel",
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
            try await appState.channelService.setChannelWithSecret(
                deviceID: deviceID,
                index: selectedSlot,
                name: channel.name,
                secret: channel.secret
            )

            onComplete()
        } catch {
            errorMessage = error.localizedDescription
        }

        isJoining = false
    }
}

// MARK: - QR Scanner UIViewRepresentable

struct QRScannerView: UIViewRepresentable {
    let onScan: (String) -> Void
    let onPermissionDenied: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        let captureSession = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            onPermissionDenied()
            return view
        }

        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            onPermissionDenied()
            return view
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            onPermissionDenied()
            return view
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(context.coordinator, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            onPermissionDenied()
            return view
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        context.coordinator.previewLayer = previewLayer

        Task {
            captureSession.startRunning()
        }

        context.coordinator.captureSession = captureSession

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onScan: (String) -> Void
        var captureSession: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?
        var hasScanned = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !hasScanned,
                  let metadataObject = metadataObjects.first,
                  let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
                  let stringValue = readableObject.stringValue else {
                return
            }

            hasScanned = true
            captureSession?.stopRunning()

            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            onScan(stringValue)
        }
    }
}

#Preview {
    NavigationStack {
        ScanChannelQRView(availableSlots: [1, 2, 3], onComplete: {})
    }
    .environment(AppState())
}
