import CoreBluetooth
import CoreLocation
import SwiftUI
import UserNotifications

struct PermissionsView: View {
    @Binding var hasBluetoothPermission: Bool
    @Binding var hasNotificationPermission: Bool
    @Binding var hasLocationPermission: Bool

    let onContinue: () -> Void

    @StateObject private var bluetoothManager = BluetoothPermissionManager()
    @StateObject private var locationManager = LocationPermissionManager()

    var body: some View {
        VStack(spacing: 24) {
            Text("Permissions")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("PocketMesh needs a few permissions to work")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                PermissionRow(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Bluetooth",
                    description: "Connect to MeshCore devices",
                    isGranted: hasBluetoothPermission,
                    action: {
                        bluetoothManager.requestPermission()
                    },
                )

                PermissionRow(
                    icon: "bell.fill",
                    title: "Notifications",
                    description: "Alert you of new messages",
                    isGranted: hasNotificationPermission,
                    action: requestNotificationPermission,
                )

                PermissionRow(
                    icon: "location.fill",
                    title: "Location",
                    description: "Share your location with contacts",
                    isGranted: hasLocationPermission,
                    action: {
                        locationManager.requestPermission()
                        hasLocationPermission = locationManager.hasPermission
                    },
                )
            }

            Spacer()

            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(allPermissionsGranted ? Color.blue : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(!allPermissionsGranted)
            .padding(.horizontal, 40)
        }
        .padding()
        .onChange(of: bluetoothManager.hasPermission) { _, newValue in
            hasBluetoothPermission = newValue
        }
        .onChange(of: locationManager.hasPermission) { _, newValue in
            hasLocationPermission = newValue
        }
        .onAppear {
            hasBluetoothPermission = bluetoothManager.hasPermission
            hasLocationPermission = locationManager.hasPermission
        }
    }

    private var allPermissionsGranted: Bool {
        hasBluetoothPermission && hasNotificationPermission && hasLocationPermission
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                hasNotificationPermission = granted
            }
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow", action: action)
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

@MainActor
final class BluetoothPermissionManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    private var centralManager: CBCentralManager?
    @Published var hasPermission = false

    #if DEBUG

        // MARK: - Simulator Bypass Properties

        private var allowButtonTapCount = 0
        private var lastTapTime: Date?
        private let tapTimeout: TimeInterval = 2.0 // Reset counter after 2 seconds
        private let requiredTapCount = 3

        // MARK: - Simulator Detection

        private var isRunningInSimulator: Bool {
            #if targetEnvironment(simulator)
                return true
            #else
                return false
            #endif
        }
    #endif

    override init() {
        super.init()
        // Start with permission = false
        // Only grant after user taps "Allow" and Bluetooth scan is initiated
    }

    func requestPermission() {
        #if DEBUG
            if isRunningInSimulator {
                handleSimulatorPermissionRequest()
            } else {
                handleDevicePermissionRequest()
            }
        #else
            handleDevicePermissionRequest()
        #endif
    }

    #if DEBUG
        private func handleSimulatorPermissionRequest() {
            // In simulator, increment tap counter and check for bypass
            incrementTapCounter()

            // Still attempt to create CBCentralManager for consistency
            // This will always fail with .unsupported state in simulator
            if centralManager == nil {
                centralManager = CBCentralManager(delegate: self, queue: .main)
            }
        }
    #endif

    private func handleDevicePermissionRequest() {
        // Original device permission logic
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: .main)
        }
    }

    #if DEBUG
        private func incrementTapCounter() {
            let now = Date()

            // Reset counter if too much time has passed
            if let lastTap = lastTapTime, now.timeIntervalSince(lastTap) > tapTimeout {
                allowButtonTapCount = 0
            }

            allowButtonTapCount += 1
            lastTapTime = now

            // Check for bypass condition
            if allowButtonTapCount >= requiredTapCount {
                enableSimulatorBypass()
            }
        }

        private func enableSimulatorBypass() {
            hasPermission = true
            allowButtonTapCount = 0

            // Log bypass activation for debugging
            print("🔧 Bluetooth permission bypass enabled for simulator testing")
        }
    #endif

    private func startScanToTriggerPermission() {
        // Start scanning for any BLE devices
        // This triggers iOS to show the Bluetooth permission prompt
        centralManager?.scanForPeripherals(withServices: nil, options: nil)

        // Stop scanning after a short delay - we just need to trigger the permission
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.centralManager?.stopScan()
        }
    }

    private func updatePermissionStatus() {
        guard let manager = centralManager else {
            hasPermission = false
            return
        }

        #if DEBUG
            if isRunningInSimulator {
                // In simulator, only update if we haven't already enabled bypass
                if hasPermission {
                    return // Keep bypass state
                }
            }
        #endif

        switch manager.state {
        case .poweredOn:
            // Bluetooth is powered on and ready
            // Start scan to trigger iOS permission prompt
            startScanToTriggerPermission()
            // Mark as permitted
            hasPermission = true
        case .poweredOff, .resetting:
            // Bluetooth is off or restarting
            hasPermission = false
        case .unauthorized:
            // App is not authorized to use Bluetooth
            hasPermission = false
        case .unsupported:
            #if DEBUG
                // In simulator, this is expected - don't change permission state
                if !isRunningInSimulator {
                    hasPermission = false
                }
            #else
                // Device doesn't support Bluetooth
                hasPermission = false
            #endif
        case .unknown:
            // State not determined yet - wait
            hasPermission = false
        @unknown default:
            hasPermission = false
        }
    }

    nonisolated func centralManagerDidUpdateState(_: CBCentralManager) {
        Task { @MainActor in
            updatePermissionStatus()
        }
    }
}

@MainActor
final class LocationPermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var hasPermission = false

    override init() {
        super.init()
        manager.delegate = self
        checkPermission()
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    private func checkPermission() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            hasPermission = true
        default:
            hasPermission = false
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        Task { @MainActor in
            checkPermission()
        }
    }
}
