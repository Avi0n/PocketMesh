import MapKit
import PocketMeshKit
import SwiftUI

struct ContactDetailView: View {
    let contact: Contact
    @EnvironmentObject private var appCoordinator: AppCoordinator

    @State private var region: MKCoordinateRegion
    @State private var isLoggedIn = false
    @State private var showLoginSheet = false
    @State private var authenticationError: Error?

    private let passwordManager = PasswordManager()

    init(contact: Contact) {
        self.contact = contact

        if let lat = contact.latitude, let lon = contact.longitude {
            _region = State(initialValue: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1),
            ))
        } else {
            _region = State(initialValue: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10),
            ))
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Name")
                    Spacer()
                    Text(contact.name)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Type")
                    Spacer()
                    Text(contact.type.rawValue)
                        .foregroundStyle(.secondary)
                }

                if let lastAdvert = contact.lastAdvertisement {
                    HStack {
                        Text("Last Advertisement")
                        Spacer()
                        Text(lastAdvert, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let latitude = contact.latitude, let longitude = contact.longitude {
                Section("Location") {
                    Map(coordinateRegion: $region, annotationItems: [ContactAnnotation(contact: contact)]) { annotation in
                        MapMarker(
                            coordinate: annotation.coordinate,
                            tint: .blue,
                        )
                    }
                    .frame(height: 200)
                    .listRowInsets(EdgeInsets())
                }
            }

            // Authentication section for repeaters and sensors
            if contact.type == .repeater || contact.type == .sensor {
                Section("Authentication") {
                    if isLoggedIn {
                        Label("Authenticated", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)

                        Button("Logout", role: .destructive) {
                            Task {
                                await logout()
                            }
                        }
                    } else {
                        Button("Login") {
                            showLoginSheet = true
                        }
                    }
                }
            }

            // ACL section for repeaters only
            if contact.type == .repeater {
                Section("Security") {
                    NavigationLink("Access Control List") {
                        ACLView(repeater: contact)
                    }
                    .disabled(!isLoggedIn) // Require authentication to access ACL
                }
            }

            Section("Public Key") {
                Text(contact.publicKey.hexString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(contact.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLoginSheet) {
            LoginView(contact: contact) { password in
                await performLogin(password: password)
            }
        }
        .alert("Authentication Error", isPresented: .constant(authenticationError != nil)) {
            Button("OK") {
                authenticationError = nil
            }
        } message: {
            Text(authenticationError?.localizedDescription ?? "Unknown authentication error")
        }
        .onAppear {
            Task {
                await checkAuthenticationStatus()
            }
        }
    }
}

// MARK: - Authentication Helpers

extension ContactDetailView {
    private func performLogin(password: String) async {
        guard let meshProtocol = appCoordinator.meshProtocol else {
            authenticationError = AuthenticationError.notAuthenticated
            return
        }

        do {
            // Store password for future use
            try await passwordManager.storePassword(password, for: contact.publicKey)

            // Perform login
            let contactData = try contact.toContactData()
            try await meshProtocol.login(to: contactData, password: password)

            await MainActor.run {
                isLoggedIn = true
            }
        } catch {
            await MainActor.run {
                authenticationError = error
            }
        }
    }

    private func logout() async {
        guard let meshProtocol = appCoordinator.meshProtocol else {
            authenticationError = AuthenticationError.notAuthenticated
            return
        }

        do {
            let contactData = try contact.toContactData()
            try await meshProtocol.logout(from: contactData)

            await MainActor.run {
                isLoggedIn = false
            }
        } catch {
            await MainActor.run {
                authenticationError = error
            }
        }
    }

    private func checkAuthenticationStatus() async {
        // Check if we have a stored password
        do {
            let storedPassword = try await passwordManager.getPassword(for: contact.publicKey)
            await MainActor.run {
                isLoggedIn = storedPassword != nil
            }
        } catch {
            await MainActor.run {
                isLoggedIn = false
            }
        }
    }
}

struct ContactAnnotation: Identifiable {
    let id = UUID()
    let contact: Contact

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: contact.latitude ?? 0,
            longitude: contact.longitude ?? 0,
        )
    }
}
