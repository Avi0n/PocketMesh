import Foundation
import SwiftData

/// SwiftData model for persisted debug log entries.
@Model
public final class DebugLogEntry {
    #Index<DebugLogEntry>([\.deviceID, \.timestamp])

    @Attribute(.unique)
    public var id: UUID

    public var deviceID: UUID
    public var timestamp: Date
    public var level: Int
    public var subsystem: String
    public var category: String
    public var message: String

    public init(
        id: UUID = UUID(),
        deviceID: UUID,
        timestamp: Date = Date(),
        level: Int,
        subsystem: String,
        category: String,
        message: String
    ) {
        self.id = id
        self.deviceID = deviceID
        self.timestamp = timestamp
        self.level = level
        self.subsystem = subsystem
        self.category = category
        self.message = message
    }
}

/// Sendable DTO for cross-actor transfer of DebugLogEntry data.
public struct DebugLogEntryDTO: Sendable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public let deviceID: UUID
    public let timestamp: Date
    public let level: DebugLogLevel
    public let subsystem: String
    public let category: String
    public let message: String

    public init(
        id: UUID = UUID(),
        deviceID: UUID,
        timestamp: Date = Date(),
        level: DebugLogLevel,
        subsystem: String,
        category: String,
        message: String
    ) {
        self.id = id
        self.deviceID = deviceID
        self.timestamp = timestamp
        self.level = level
        self.subsystem = subsystem
        self.category = category
        // Truncate message to prevent memory issues
        self.message = String(message.prefix(4000))
    }

    /// Initialize from SwiftData model.
    public init(from model: DebugLogEntry) {
        self.id = model.id
        self.deviceID = model.deviceID
        self.timestamp = model.timestamp
        self.level = DebugLogLevel(rawValue: model.level) ?? .info
        self.subsystem = model.subsystem
        self.category = model.category
        self.message = model.message
    }
}
