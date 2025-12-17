import Foundation

/// A typed event with payload and filterable attributes
/// Payload types come from ProtocolFrames.swift - no new types needed
public struct MeshEvent: Sendable {
    /// The event type
    public let type: MeshEventType

    /// The event payload - uses existing ProtocolFrames types
    /// Cast to specific type using convenience accessors
    public let payload: any Sendable

    /// Attributes for filtering subscriptions (e.g., publicKeyPrefix, tag, ackCode)
    public let attributes: [String: String]

    /// Timestamp when event was created
    public let timestamp: Date

    public init(
        type: MeshEventType,
        payload: any Sendable,
        attributes: [String: String] = [:]
    ) {
        self.type = type
        self.payload = payload
        self.attributes = attributes
        self.timestamp = Date()
    }

    // MARK: - Type-Safe Payload Accessors

    /// Cast payload to MessageFrame (for .contactMessage)
    public var asMessageFrame: MessageFrame? { payload as? MessageFrame }

    /// Cast payload to ChannelMessageFrame (for .channelMessage)
    public var asChannelMessage: ChannelMessageFrame? { payload as? ChannelMessageFrame }

    /// Cast payload to RemoteNodeStatus (for .statusResponse)
    public var asStatusResponse: RemoteNodeStatus? { payload as? RemoteNodeStatus }

    /// Cast payload to LoginResult (for .loginSuccess, .loginFailed)
    public var asLoginResult: LoginResult? { payload as? LoginResult }

    /// Cast payload to SendConfirmation (for .sendConfirmed)
    public var asSendConfirmation: SendConfirmation? { payload as? SendConfirmation }

    /// Cast payload to SentResponse (for .messageSent)
    public var asSentResponse: SentResponse? { payload as? SentResponse }

    /// Cast payload to DeviceInfo (for .deviceInfo)
    public var asDeviceInfo: DeviceInfo? { payload as? DeviceInfo }

    /// Cast payload to SelfInfo (for .selfInfo)
    public var asSelfInfo: SelfInfo? { payload as? SelfInfo }

    /// Cast payload to ContactFrame (for .contact, .newContact, .advertisement)
    public var asContactFrame: ContactFrame? { payload as? ContactFrame }

    /// Cast payload to BinaryResponse (for .binaryResponse)
    public var asBinaryResponse: BinaryResponse? { payload as? BinaryResponse }

    /// Cast payload to NeighboursResponse (for .neighboursResponse)
    public var asNeighboursResponse: NeighboursResponse? { payload as? NeighboursResponse }

    /// Cast payload to TelemetryResponse (for .telemetryResponse)
    public var asTelemetryResponse: TelemetryResponse? { payload as? TelemetryResponse }

    /// Cast payload to TraceData (for .traceData)
    public var asTraceData: TraceData? { payload as? TraceData }

    /// Cast payload to ControlDataPacket (for .controlData)
    public var asControlData: ControlDataPacket? { payload as? ControlDataPacket }

    /// Cast payload to NodeDiscoverResponse (for .discoverResponse)
    public var asDiscoverResponse: NodeDiscoverResponse? { payload as? NodeDiscoverResponse }

    /// Cast payload to CoreStats (for .statsCore)
    public var asCoreStats: CoreStats? { payload as? CoreStats }

    /// Cast payload to RadioStats (for .statsRadio)
    public var asRadioStats: RadioStats? { payload as? RadioStats }

    /// Cast payload to PacketStats (for .statsPackets)
    public var asPacketStats: PacketStats? { payload as? PacketStats }

    /// Cast payload to ChannelInfo (for .channelInfo)
    public var asChannelInfo: ChannelInfo? { payload as? ChannelInfo }

    /// Cast payload to BatteryAndStorage (for .batteryAndStorage)
    public var asBatteryAndStorage: BatteryAndStorage? { payload as? BatteryAndStorage }

    /// Cast payload to PathDiscoveryResponse (for .pathDiscoveryResponse)
    public var asPathDiscoveryResponse: PathDiscoveryResponse? { payload as? PathDiscoveryResponse }

    /// Cast payload to BinaryResponse for MMA data (for .mmaResponse)
    /// Note: MMA response uses BinaryResponse payload, parse data field for min/max/avg values
    public var asMmaResponse: BinaryResponse? { payload as? BinaryResponse }

    /// Cast payload to BinaryResponse for ACL data (for .aclResponse)
    /// Note: ACL response uses BinaryResponse payload, parse data field for access control list
    public var asAclResponse: BinaryResponse? { payload as? BinaryResponse }
}

/// Empty payload for events with no data (e.g., .messagesWaiting, .noMoreMessages)
public struct EmptyPayload: Sendable, Equatable {}

/// Simple error payload for .error events
public struct ErrorPayload: Sendable, Equatable {
    public let errorCode: UInt8

    public init(errorCode: UInt8) {
        self.errorCode = errorCode
    }
}

/// Simple OK payload for .ok events
public struct OKPayload: Sendable, Equatable {
    public let value: UInt32?

    public init(value: UInt32? = nil) {
        self.value = value
    }
}

/// Payload for .currentTime events
public struct CurrentTimePayload: Sendable, Equatable {
    public let timestamp: UInt32

    public init(timestamp: UInt32) {
        self.timestamp = timestamp
    }
}

/// Payload for .privateKey events
public struct PrivateKeyPayload: Sendable, Equatable {
    public let privateKey: Data

    public init(privateKey: Data) {
        self.privateKey = privateKey
    }
}

/// Payload for .signStart events
public struct SignStartPayload: Sendable, Equatable {
    public let maxLength: UInt32

    public init(maxLength: UInt32) {
        self.maxLength = maxLength
    }
}

/// Payload for .signature events
public struct SignaturePayload: Sendable, Equatable {
    public let signature: Data

    public init(signature: Data) {
        self.signature = signature
    }
}
