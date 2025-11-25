import Foundation

/// Radio connection states matching firmware behavior
public enum RadioConnectionState: Sendable {
    case advertising
    case connected
    case disconnected
}

/// Advertising modes
public enum AdvertisingMode: Sendable {
    case connectable
    case nonConnectable
}

/// Radio configuration constants (from MyMesh.h)
public enum RadioConstants {
    public static let maxFrameSize: Int = 256 // MAX_FRAME_SIZE
    public static let offlineQueueSize: Int = 16 // OFFLINE_QUEUE_SIZE
    public static let expectedAckTableSize: Int = 8 // EXPECTED_ACK_TABLE_SIZE
    public static let advertPathTableSize: Int = 16 // ADVERT_PATH_TABLE_SIZE
    public static let firmwareVersionCode: UInt8 = 8 // FIRMWARE_VER_CODE
    public static let defaultMTU: Int = 185 // Typical BLE MTU
    public static let maxContacts: UInt16 = 100 // MAX_CONTACTS
}
