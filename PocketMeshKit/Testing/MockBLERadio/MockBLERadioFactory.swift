import Foundation

/// Factory for creating configured mock radios
public enum MockBLERadioFactory {
    /// Create a default mock radio for testing
    @MainActor
    public static func createDefault() -> (radio: MockBLERadio, manager: MockBLEManager) {
        let radio = MockBLERadio(
            deviceName: "MockMeshCore-Test",
            config: .default,
        )
        let manager = MockBLEManager(radio: radio)
        return (radio, manager)
    }

    /// Create a mock radio with error simulation
    @MainActor
    public static func createWithErrors() -> (radio: MockBLERadio, manager: MockBLEManager) {
        let radio = MockBLERadio(
            deviceName: "MockMeshCore-ErrorTest",
            config: .errorTesting,
        )
        let manager = MockBLEManager(radio: radio)
        return (radio, manager)
    }

    /// Create a mock radio with custom configuration
    @MainActor
    public static func create(config: MockRadioConfig) -> (radio: MockBLERadio, manager: MockBLEManager) {
        let radio = MockBLERadio(
            deviceName: "MockMeshCore-Custom",
            config: config,
        )
        let manager = MockBLEManager(radio: radio)
        return (radio, manager)
    }
}
