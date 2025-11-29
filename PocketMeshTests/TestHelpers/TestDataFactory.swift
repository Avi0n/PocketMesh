import Foundation
@testable import PocketMeshKit

public enum TestDataFactory {
    // MARK: - Public Keys

    public static func randomPublicKey() -> Data {
        Data((0 ..< 32).map { _ in UInt8.random(in: 0 ... 255) })
    }

    public static let alicePublicKey = Data(repeating: 0xA1, count: 32)
    public static let bobPublicKey = Data(repeating: 0xB2, count: 32)
    public static let charliePublicKey = Data(repeating: 0xC3, count: 32)

    // MARK: - Device Info

    public static func deviceInfo(
        firmwareVersionCode: UInt8 = 8,
        maxContacts: UInt8 = 50,
        maxGroupChannels: UInt8 = 8,
        blePin: UInt32 = 0,
    ) -> DeviceInfo {
        DeviceInfo(
            firmwareVersionCode: firmwareVersionCode,
            maxContacts: maxContacts,
            maxGroupChannels: maxGroupChannels,
            blePin: blePin,
            buildDate: "2025-01-24",
            manufacturer: "MockRadio",
            firmwareVersion: "v1.10.0",
        )
    }

    // MARK: - Self Info

    public static func selfInfo(
        publicKey: Data = Data(repeating: 0x01, count: 32),
        latitude: Int32 = 37_774_900,
        longitude: Int32 = -122_419_400,
    ) -> SelfInfo {
        SelfInfo(
            advertisementType: 0,
            txPower: 20,
            maxTxPower: 30,
            publicKey: publicKey,
            latitude: latitude,
            longitude: longitude,
            multiAcks: 1,
            advertLocationPolicy: 1,
            telemetryModes: 1,
            manualAddContacts: 0,
            frequency: 915_000_000,
            bandwidth: 125_000,
            spreadingFactor: 7,
            codingRate: 5,
            nodeName: "TestNode",
        )
    }

    // MARK: - Contact Data

    public static func contactData(
        publicKey: Data = Data(repeating: 0x02, count: 32),
        name: String = "Test Contact",
        type: ContactType = .chat,
    ) -> ContactData {
        ContactData(
            publicKey: publicKey,
            name: name,
            type: type,
            flags: 0,
            outPathLength: 0,
            outPath: nil,
            lastAdvertisement: Date(),
            latitude: 37.7749,
            longitude: -122.4194,
            lastModified: Date(),
        )
    }

    // MARK: - Messages

    public static func messageText(length: Int = 100) -> String {
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 "
        return String((0 ..< length).map { _ in characters.randomElement()! })
    }

    // MARK: - Mock Configurations

    public static let standardTesting = MockRadioConfig(
        packetLossRate: 0.0,
        maxRandomDelay: 0.1,
        verboseLogging: true,
    )

    public static let floodAdvertisementTesting = MockRadioConfig(
        packetLossRate: 0.1,
        maxRandomDelay: 0.2,
        forcedMTU: 64,
        verboseLogging: true,
    )

    public static let highLatencyTesting = MockRadioConfig(
        packetLossRate: 0.0,
        maxRandomDelay: 1.0,
        verboseLogging: true,
    )

    public static let unreliableNetworkTesting = MockRadioConfig(
        packetLossRate: 0.25,
        maxRandomDelay: 0.5,
        forcedMTU: 32,
        verboseLogging: true,
    )

    public static let connectionDropTesting = MockRadioConfig(
        packetLossRate: 0.0,
        maxRandomDelay: 0.1,
        disconnectAfterFrames: 10,
        verboseLogging: true,
    )
}
