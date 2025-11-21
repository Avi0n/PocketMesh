import PocketMeshKit
import SwiftUI

struct LoginView: View {
    let contact: Contact
    let onLogin: (String) async -> Void

    @State private var password = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Password", text: $password)
                } header: {
                    Text("Enter password for \(contact.name)")
                }
            }
            .navigationTitle("Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Login") {
                        Task {
                            await onLogin(password)
                            dismiss()
                        }
                    }
                    .disabled(password.isEmpty)
                }
            }
        }
    }
}
