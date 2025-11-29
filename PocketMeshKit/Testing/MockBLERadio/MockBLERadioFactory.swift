import Foundation

/// Factory for creating configured mock radios
@MainActor
public struct MockBLERadioFactory {
    /// Create a default mock radio for testing
    public static func createDefault() -> (radio: MockBLERadio, manager: MockBLEManager) {
        let radio = MockBLERadio(
            deviceName: "MockMeshCore-Test",
            config: .default,
        )
        let manager = MockBLEManager(radio: radio)
        return (radio, manager)
    }

    /// Create a mock radio with error simulation
    public static func createWithErrors() -> (radio: MockBLERadio, manager: MockBLEManager) {
        let radio = MockBLERadio(
            deviceName: "MockMeshCore-ErrorTest",
            config: .errorTesting,
        )
        let manager = MockBLEManager(radio: radio)
        return (radio, manager)
    }

    /// Create a mock radio with custom configuration
    public static func create(config: MockRadioConfig) -> (radio: MockBLERadio, manager: MockBLEManager) {
        let radio = MockBLERadio(
            deviceName: "MockMeshCore-Custom",
            config: config,
        )
        let manager = MockBLEManager(radio: radio)
        return (radio, manager)
    }

    /// Create a mock radio with pre-populated test contacts
    public static func createWithSampleContacts() -> (radio: MockBLERadio, manager: MockBLEManager) {
        let radio = MockBLERadio(
            deviceName: "MockMeshCore-SampleContacts",
            config: .default,
        )

        // Pre-populate with sample contacts
        Task {
            await radio.populateSampleContacts()
        }

        let manager = MockBLEManager(radio: radio)
        return (radio, manager)
    }

    /// Create a mock radio with custom initial contacts
    public static func createWithContacts(
        _ contacts: [(publicKey: Data, name: String, type: ContactType)],
    ) -> (radio: MockBLERadio, manager: MockBLEManager) {
        let radio = MockBLERadio(
            deviceName: "MockMeshCore-CustomContacts",
            config: .default,
        )

        // Add custom contacts
        Task {
            for contact in contacts {
                await radio.addTestContact(
                    publicKey: contact.publicKey,
                    name: contact.name,
                    type: contact.type,
                )
            }
        }

        let manager = MockBLEManager(radio: radio)
        return (radio, manager)
    }
}
