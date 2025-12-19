import Foundation

// MARK: - BLE Service UUIDs

/// Nordic UART Service UUIDs for MeshCore device communication
public enum BLEServiceUUID {
    /// Nordic UART Service UUID
    public static let nordicUART = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    /// TX Characteristic (write to device)
    public static let txCharacteristic = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    /// RX Characteristic (read from device)
    public static let rxCharacteristic = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
}
