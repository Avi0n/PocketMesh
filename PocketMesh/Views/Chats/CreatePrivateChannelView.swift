import SwiftUI
import PocketMeshServices
import CoreImage.CIFilterBuiltins

/// View for creating a private channel with auto-generated secret and QR code
struct CreatePrivateChannelView: View {
    @Environment(AppState.self) private var appState

    let availableSlots: [UInt8]
    let onComplete: () -> Void

    @State private var channelName = ""
    @State private var selectedSlot: UInt8
    @State private var generatedSecret: Data?
    @State private var isCreating = false
    @State private var isCreated = false
    @State private var errorMessage: String?

    init(availableSlots: [UInt8], onComplete: @escaping () -> Void) {
        self.availableSlots = availableSlots
        self.onComplete = onComplete
        self._selectedSlot = State(initialValue: availableSlots.first ?? 1)
    }

    var body: some View {
        Form {
            if !isCreated {
                createChannelForm
            } else {
                shareChannelView
            }
        }
        .navigationTitle(isCreated ? "Share Private Channel" : "Create Private Channel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isCreated {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onComplete()
                    }
                }
            }
        }
        .onAppear {
            generateSecret()
        }
    }

    // MARK: - Create Form

    private var createChannelForm: some View {
        Group {
            Section {
                TextField("Channel Name", text: $channelName)
                    .textContentType(.name)
            } header: {
                Text("Channel Details")
            }

            Section {
                if let secret = generatedSecret {
                    LabeledContent("Secret Key") {
                        Text(secret.hexString())
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Generated Secret")
            } footer: {
                Text("A random secret key has been generated. You'll be able to share it via QR code after creating the channel.")
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
                        await createChannel()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create Channel")
                        }
                        Spacer()
                    }
                }
                .disabled(channelName.isEmpty || isCreating || generatedSecret == nil)
            }
        }
    }

    // MARK: - Share View

    private var shareChannelView: some View {
        Group {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 16) {
                        if let qrImage = generateQRCode() {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 200, height: 200)
                        }

                        Text(channelName)
                            .font(.headline)

                        Text("Scan to join this channel")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    Spacer()
                }
            }

            Section {
                if let secret = generatedSecret {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Secret Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text(secret.hexString())
                                .font(.system(.body, design: .monospaced))

                            Spacer()

                            Button("Copy", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = secret.hexString()
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                }
            } header: {
                Text("Share Manually")
            } footer: {
                Text("Share the channel name and this secret key with others. They'll need both to join.")
            }
        }
    }

    // MARK: - Private Methods

    private func generateSecret() {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        generatedSecret = Data(bytes)
    }

    private func createChannel() async {
        guard let deviceID = appState.connectedDevice?.id,
              let secret = generatedSecret else {
            errorMessage = "No device connected"
            return
        }

        isCreating = true
        errorMessage = nil

        do {
            guard let channelService = appState.services?.channelService else {
                errorMessage = "Services not available"
                return
            }
            try await channelService.setChannelWithSecret(
                deviceID: deviceID,
                index: selectedSlot,
                name: channelName,
                secret: secret
            )

            isCreated = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isCreating = false
    }

    private func generateQRCode() -> UIImage? {
        guard let secret = generatedSecret else { return nil }

        // Format: meshcore://channel/add?name=<name>&secret=<hex>
        let urlString = "meshcore://channel/add?name=\(channelName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&secret=\(secret.hexString())"

        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(urlString.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up for better quality
        let scale = 10.0
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}


#Preview {
    NavigationStack {
        CreatePrivateChannelView(availableSlots: [1, 2, 3], onComplete: {})
    }
    .environment(AppState())
}
