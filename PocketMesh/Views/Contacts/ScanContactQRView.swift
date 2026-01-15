import SwiftUI
import VisionKit
import PocketMeshServices
import os

/// View for scanning a contact QR code to import
struct ScanContactQRView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    let onScan: (String, Data) -> Void

    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var cameraPermissionDenied = false
    @State private var scanSuccessTrigger = false

    private let logger = Logger(subsystem: "com.pocketmesh", category: "ScanContactQRView")

    // MARK: - Constants

    private enum Constants {
        static let scanFrameSize: CGFloat = 250
        static let overlayOpacity: CGFloat = 0.6
        static let errorOpacity: CGFloat = 0.8
        static let bottomPadding: CGFloat = 50
    }

    var body: some View {
        Group {
            if cameraPermissionDenied {
                cameraPermissionDeniedView
            } else {
                scannerView
            }
        }
        .navigationTitle("Scan QR Code")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var unavailableView: some View {
        // Fallback for unsupported devices
        ContentUnavailableView(
            "Scanner Not Available",
            systemImage: "qrcode.viewfinder",
            description: Text("QR scanning is not supported on this device")
        )
    }
    
    // MARK: - Scanner View

    private var scannerView: some View {
        ZStack {
            #if !targetEnvironment(macCatalyst)
            if QRDataScannerView.isSupported && QRDataScannerView.isAvailable {
                QRDataScannerView { result in
                    handleScanResult(result)
                } onPermissionDenied: {
                    cameraPermissionDenied = true
                }
            } else {
               unavailableView
            }
            #else
            unavailableView
            #endif

            // Overlay with scan frame
            VStack {
                Spacer()

                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white, lineWidth: 3)
                    .frame(width: Constants.scanFrameSize, height: Constants.scanFrameSize)

                Spacer()

                if isImporting {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Importing contact...")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding()
                    .background(.black.opacity(Constants.overlayOpacity), in: .capsule)
                    .padding(.bottom, Constants.bottomPadding)
                } else if let errorMessage {
                    Button {
                        self.errorMessage = nil
                    } label: {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding()
                            .background(.red.opacity(Constants.errorOpacity), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, Constants.bottomPadding)
                } else {
                    Text("Point your camera at a contact QR code")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.black.opacity(Constants.overlayOpacity), in: .capsule)
                        .padding(.bottom, Constants.bottomPadding)
                }
            }
        }
        .sensoryFeedback(.success, trigger: scanSuccessTrigger)
        .ignoresSafeArea()
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
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Parsed Contact

    private struct ParsedContact {
        let name: String
        let publicKey: Data
        let type: ContactType
    }

    // MARK: - Private Methods

    private func handleScanResult(_ result: String) {
        guard !isImporting else { return }

        // Parse URL: meshcore://contact/add?name=<name>&public_key=<hex>&type=<1|2|3>
        guard let url = URL(string: result),
              url.scheme == "meshcore",
              url.host == "contact",
              url.path == "/add",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            logger.error("Invalid QR code format: \(result)")
            errorMessage = "Invalid QR code format"
            return
        }

        // Extract parameters
        // Note: URLQueryItem decodes %20 but not + (form-urlencoded space)
        guard let rawName = queryItems.first(where: { $0.name == "name" })?.value,
              !rawName.isEmpty else {
            logger.error("Missing or empty name parameter")
            errorMessage = "Invalid QR code: missing name"
            return
        }
        let name = rawName.replacing("+", with: " ")

        guard let publicKeyHex = queryItems.first(where: { $0.name == "public_key" })?.value,
              let publicKey = Data(hexString: publicKeyHex),
              publicKey.count == ProtocolLimits.publicKeySize else {
            logger.error("Invalid or missing public_key parameter")
            errorMessage = "Invalid QR code: invalid public key"
            return
        }

        let typeValue = queryItems.first(where: { $0.name == "type" })?.value.flatMap { Int($0) } ?? 1
        let contactType = ContactType(rawValue: UInt8(typeValue)) ?? .chat

        let parsed = ParsedContact(name: name, publicKey: publicKey, type: contactType)

        // Provide haptic feedback on successful QR scan
        scanSuccessTrigger.toggle()

        Task {
            await importContact(parsed)
        }
    }

    @MainActor
    private func importContact(_ contact: ParsedContact) async {
        guard let services = appState.services,
              let deviceID = appState.connectedDevice?.id else {
            logger.error("Services or device not available")
            errorMessage = "Not connected to device"
            return
        }

        isImporting = true
        errorMessage = nil

        do {
            let currentTimestamp = UInt32(Date().timeIntervalSince1970)

            let contactFrame = ContactFrame(
                publicKey: contact.publicKey,
                type: contact.type,
                flags: 0,
                outPathLength: -1,  // Flood routing
                outPath: Data(),
                name: contact.name,
                lastAdvertTimestamp: 0,
                latitude: 0,
                longitude: 0,
                lastModified: currentTimestamp
            )

            logger.info("Importing contact: \(contact.name) (\(contact.publicKey.hexString()))")
            try await services.contactService.addOrUpdateContact(deviceID: deviceID, contact: contactFrame)
            logger.info("Contact imported successfully")

            // Reset state and dismiss before calling completion handler
            isImporting = false
            dismiss()

            onScan(contact.name, contact.publicKey)
        } catch {
            logger.error("Failed to import contact: \(error.localizedDescription)")
            errorMessage = "Failed to import contact: \(error.localizedDescription)"
            isImporting = false
        }
    }
}

#Preview {
    NavigationStack {
        ScanContactQRView { _, _ in }
    }
    .environment(AppState())
}
