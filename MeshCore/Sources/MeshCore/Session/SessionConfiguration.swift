import Foundation

/// Configuration for MeshCoreSession
public struct SessionConfiguration: Sendable {
    public let defaultTimeout: TimeInterval
    public let clientIdentifier: String

    public init(
        defaultTimeout: TimeInterval = 5.0,
        clientIdentifier: String = "MeshCore-Swift"
    ) {
        self.defaultTimeout = defaultTimeout
        self.clientIdentifier = clientIdentifier
    }

    public static let `default` = SessionConfiguration()
}

public enum MeshCoreError: Error, Sendable {
    case timeout
    case deviceError(code: UInt8)
    case parseError(String)
    case notConnected
    case commandFailed(CommandCode, reason: String)
    case invalidResponse(expected: String, got: String)
    case contactNotFound(publicKeyPrefix: Data)
    case dataTooLarge(maxSize: Int, actualSize: Int)
    case signingFailed(reason: String)
    case invalidInput(String)
    case unknown(String)

    case bluetoothUnavailable
    case bluetoothUnauthorized
    case bluetoothPoweredOff
    case connectionLost(underlying: Error?)
    case sessionNotStarted
}

public enum MessageResult: Sendable {
    case contactMessage(ContactMessage)
    case channelMessage(ChannelMessage)
    case noMoreMessages
}
