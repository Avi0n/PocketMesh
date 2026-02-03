import CoreLocation
import Foundation
import Testing
@testable import PocketMesh
@testable import PocketMeshServices

@Suite("RepeaterResolver")
struct RepeaterResolverTests {

    private func createRepeater(
        prefix: UInt8,
        secondByte: UInt8,
        name: String,
        lastAdvertTimestamp: UInt32,
        latitude: Double,
        longitude: Double
    ) -> ContactDTO {
        ContactDTO(
            id: UUID(),
            deviceID: UUID(),
            publicKey: Data([prefix, secondByte] + Array(repeating: UInt8(0), count: 30)),
            name: name,
            typeRawValue: ContactType.repeater.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            lastAdvertTimestamp: lastAdvertTimestamp,
            latitude: latitude,
            longitude: longitude,
            lastModified: 0,
            nickname: nil,
            isBlocked: false,
            isMuted: false,
            isFavorite: false,
            lastMessageDate: nil,
            unreadCount: 0
        )
    }

    @Test("prefers closest repeater when location available")
    func prefersClosestWithLocation() {
        let repeaterA = createRepeater(
            prefix: 0x3F,
            secondByte: 0x01,
            name: "Near",
            lastAdvertTimestamp: 10,
            latitude: 37.0,
            longitude: -122.0
        )
        let repeaterB = createRepeater(
            prefix: 0x3F,
            secondByte: 0x02,
            name: "Far",
            lastAdvertTimestamp: 200,
            latitude: 38.0,
            longitude: -123.0
        )

        let userLocation = CLLocation(latitude: 37.0005, longitude: -122.0005)
        let match = RepeaterResolver.bestMatch(for: 0x3F, in: [repeaterA, repeaterB], userLocation: userLocation)

        #expect(match?.displayName == "Near")
    }

    @Test("prefers most recent when location unavailable")
    func prefersMostRecentWithoutLocation() {
        let repeaterA = createRepeater(
            prefix: 0x3F,
            secondByte: 0x01,
            name: "Older",
            lastAdvertTimestamp: 10,
            latitude: 0,
            longitude: 0
        )
        let repeaterB = createRepeater(
            prefix: 0x3F,
            secondByte: 0x02,
            name: "Newer",
            lastAdvertTimestamp: 200,
            latitude: 0,
            longitude: 0
        )

        let match = RepeaterResolver.bestMatch(for: 0x3F, in: [repeaterA, repeaterB], userLocation: nil)

        #expect(match?.displayName == "Newer")
    }
}
