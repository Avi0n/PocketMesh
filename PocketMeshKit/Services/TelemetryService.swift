import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "TelemetryService")

@MainActor
public final class TelemetryService: ObservableObject {
    private let `protocol`: MeshCoreProtocol
    private let modelContext: ModelContext
    private let contactRepository: ContactRepository

    @Published public var latestTelemetry: [Data: TelemetryData] = [:] // Keyed by public key
    @Published public var latestStatus: [Data: StatusData] = [:]
    @Published public var neighbours: [Data: [NeighbourEntry]] = [:]

    public init(protocol: MeshCoreProtocol, modelContext: ModelContext) {
        self.protocol = `protocol`
        self.modelContext = modelContext
        contactRepository = ContactRepository(modelContext: modelContext)
    }

    /// Request telemetry from a sensor or repeater
    public func requestTelemetry(for contact: Contact) async throws -> TelemetryData {
        let contactData = try contact.toContactData()

        let telemetry = try await `protocol`.requestTelemetry(from: contactData, timeout: 15.0)

        // Cache latest telemetry
        latestTelemetry[contact.publicKey] = telemetry

        logger.info(
            """
            Received telemetry from \(contact.name): temp=\(telemetry.temperature ?? -999) \
            humidity=\(telemetry.humidity ?? -999)
            """,
        )
        return telemetry
    }

    /// Request status from a repeater
    public func requestStatus(for contact: Contact) async throws -> StatusData {
        guard contact.type == .repeater || contact.type == .room else {
            throw TelemetryError.invalidContactType
        }

        let contactData = try contact.toContactData()

        let status = try await `protocol`.requestStatus(from: contactData, timeout: 15.0)

        // Cache latest status
        latestStatus[contact.publicKey] = status

        logger.info("Received status from \(contact.name): uptime \(status.uptime)s, battery \(status.batteryPercent)%")
        return status
    }

    /// Request neighbour table from repeater
    public func requestNeighbours(for contact: Contact) async throws -> [NeighbourEntry] {
        guard contact.type == .repeater || contact.type == .room else {
            throw TelemetryError.invalidContactType
        }

        let contactData = try contact.toContactData()

        let neighbours = try await `protocol`.requestNeighbours(from: contactData, timeout: 20.0)

        // Cache neighbours
        self.neighbours[contact.publicKey] = neighbours

        logger.info("Received \(neighbours.count) neighbours from \(contact.name)")
        return neighbours
    }

    /// Request min/max/avg sensor data over time range
    public func requestMMA(for contact: Contact, last minutes: Int) async throws -> MMAData {
        let contactData = try contact.toContactData()

        let fromSeconds = minutes * 60
        let toSeconds = 0

        let mma = try await `protocol`.requestMMA(
            from: contactData,
            fromSeconds: fromSeconds,
            toSeconds: toSeconds,
            timeout: 20.0,
        )

        logger.info("Received MMA data from \(contact.name): \(mma.sampleCount) samples")
        return mma
    }
}

public enum TelemetryError: LocalizedError {
    case invalidContactType

    public var errorDescription: String? {
        switch self {
        case .invalidContactType: "Telemetry not supported for this contact type"
        }
    }
}

// Helper to convert SwiftData Contact to protocol ContactData
public extension Contact {
    func toContactData() throws -> ContactData {
        ContactData(
            publicKey: publicKey,
            name: name,
            type: type,
            flags: 0,
            outPathLength: outPathLength ?? 0xFF,
            outPath: outPath,
            lastAdvertisement: lastAdvertisement ?? Date(),
            latitude: latitude,
            longitude: longitude,
            lastModified: lastModified,
        )
    }
}
