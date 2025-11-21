import PocketMeshKit
import SwiftUI

struct OnboardingFlow: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var currentStep: OnboardingStep = .welcome
    @State private var hasBluetoothPermission = false
    @State private var hasNotificationPermission = false
    @State private var hasLocationPermission = false

    var body: some View {
        NavigationStack {
            ZStack {
                switch currentStep {
                case .welcome:
                    WelcomeView(onContinue: {
                        currentStep = .permissions
                    })

                case .permissions:
                    PermissionsView(
                        hasBluetoothPermission: $hasBluetoothPermission,
                        hasNotificationPermission: $hasNotificationPermission,
                        hasLocationPermission: $hasLocationPermission,
                        onContinue: {
                            currentStep = .deviceScanning
                        },
                    )

                case .deviceScanning:
                    DeviceScanningView(
                        onDeviceSelected: { device in
                            currentStep = .devicePairing(device)
                        },
                        onSkip: {
                            // Complete onboarding without a device
                            coordinator.completeOnboarding(device: nil)
                        },
                    )

                case let .devicePairing(device):
                    DevicePairingView(device: device)
                }
            }
            .animation(.easeInOut, value: currentStep)
        }
    }
}

enum OnboardingStep: Equatable {
    case welcome
    case permissions
    case deviceScanning
    case devicePairing(MeshCoreDevice)
}
