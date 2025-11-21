import PocketMeshKit
import SwiftUI

struct ACLView: View {
    let repeater: Contact
    @EnvironmentObject private var appCoordinator: AppCoordinator

    @State private var aclEntries: [ACLEntry] = []
    @State private var isLoading = false
    @State private var error: Error?

    var body: some View {
        List {
            if isLoading {
                ProgressView("Loading ACL...")
            } else if let error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
            } else {
                ForEach(aclEntries) { entry in
                    ACLEntryRow(entry: entry, repeater: repeater)
                }
            }
        }
        .navigationTitle("Access Control")
        .task {
            await loadACL()
        }
        .refreshable {
            await loadACL()
        }
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK") {
                error = nil
            }
        } message: {
            Text(error?.localizedDescription ?? "Unknown error")
        }
    }

    private func loadACL() async {
        isLoading = true
        defer { isLoading = false }

        guard let meshProtocol = appCoordinator.meshProtocol else {
            error = AuthenticationError.notAuthenticated
            return
        }

        do {
            let contactData = try repeater.toContactData()
            aclEntries = try await meshProtocol.requestACL(from: contactData)
        } catch {
            self.error = error
        }
    }
}

struct ACLEntryRow: View {
    let entry: ACLEntry
    let repeater: Contact
    @EnvironmentObject private var appCoordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.publicKeyPrefix.hexString)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Label("Read", systemImage: entry.canRead ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(entry.canRead ? .green : .gray)
                    .font(.caption)

                Label("Write", systemImage: entry.canWrite ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(entry.canWrite ? .green : .gray)
                    .font(.caption)

                Label("Execute", systemImage: entry.canExecute ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(entry.canExecute ? .green : .gray)
                    .font(.caption)
            }

            Text("Permissions: \(String(entry.permissions, radix: 2))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
