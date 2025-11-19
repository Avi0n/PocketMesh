import SwiftUI
import PocketMeshKit

struct ContactDetailSheet: View {
    let contact: Contact
    @Environment(\.dismiss) private var dismiss
    @State private var isDataLoaded = false

    var body: some View {
        NavigationStack {
            Group {
                if isDataLoaded {
                    contactDetailsContent
                } else {
                    ProgressView("Loading contact details...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(contact.name.isEmpty ? "Contact" : contact.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Simulate data loading/validation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isDataLoaded = true
            }
        }
    }

    private var contactDetailsContent: some View {
        List {
            Section("Contact Information") {
                HStack {
                    Text("Name")
                    Spacer()
                    Text(contact.name.isEmpty ? "Unknown" : contact.name)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Type")
                    Spacer()
                    Text(contactTypeDisplay)
                        .foregroundStyle(.secondary)
                }

                if let lastAdvert = contact.lastAdvertisement {
                    HStack {
                        Text("Last Advertisement")
                        Spacer()
                        Text(lastAdvert.relativeTimeStringMinutesOnly())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let latitude = contact.latitude, let longitude = contact.longitude,
               latitude != 0 && longitude != 0 {
                Section("Location") {
                    HStack {
                        Text("Latitude")
                        Spacer()
                        Text(String(format: "%.6f", latitude))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Longitude")
                        Spacer()
                        Text(String(format: "%.6f", longitude))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let pathLength = contact.outPathLength, pathLength > 0 {
                Section("Network Path") {
                    if let pathLength = contact.outPathLength {
                        HStack {
                            Text("Hop Count")
                            Spacer()
                            Text("\(pathLength)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let outPath = contact.outPath {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Path Data")
                                .font(.headline)
                            Text(outPath.hexString)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            Section("Public Key") {
                Text(contact.publicKey.isEmpty ? "Not Available" : contact.publicKey.hexString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var contactTypeDisplay: String {
        switch contact.type {
        case .none:
            return "None"
        case .chat:
            return "Chat"
        case .repeater:
            return "Repeater"
        case .room:
            return "Room"
        }
    }
}