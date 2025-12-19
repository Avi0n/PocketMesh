import Foundation
import Testing
@testable import MeshCore

@Suite("Session Helper Tests")
struct SessionHelperTests {
    
    @Test("MeshCoreError.invalidInput stores message")
    func invalidInputError() {
        let error = MeshCoreError.invalidInput("test message")
        if case .invalidInput(let msg) = error {
            #expect(msg == "test message")
        } else {
            Issue.record("Expected invalidInput case")
        }
    }
    
    @Test("MeshContact.isFloodPath returns true for -1 path length")
    func contactIsFloodPath() {
        let floodContact = MeshContact(
            id: "test",
            publicKey: Data(repeating: 0x01, count: 32),
            type: 0,
            flags: 0,
            outPathLength: -1,
            outPath: Data(),
            advertisedName: "Test",
            lastAdvertisement: Date(),
            latitude: 0,
            longitude: 0,
            lastModified: Date()
        )
        #expect(floodContact.isFloodPath == true)
        
        let directContact = MeshContact(
            id: "test2",
            publicKey: Data(repeating: 0x02, count: 32),
            type: 0,
            flags: 0,
            outPathLength: 2,
            outPath: Data([0x01, 0x02]),
            advertisedName: "Test2",
            lastAdvertisement: Date(),
            latitude: 0,
            longitude: 0,
            lastModified: Date()
        )
        #expect(directContact.isFloodPath == false)
    }
    
    @Test("NeighboursResponse aggregates neighbours correctly")
    func neighboursResponseStructure() {
        let neighbours = [
            Neighbour(publicKeyPrefix: Data([0x01, 0x02, 0x03, 0x04]), secondsAgo: 10, snr: 5.5),
            Neighbour(publicKeyPrefix: Data([0x05, 0x06, 0x07, 0x08]), secondsAgo: 20, snr: 3.0)
        ]
        
        let response = NeighboursResponse(
            publicKeyPrefix: Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]),
            tag: Data(),
            totalCount: 2,
            neighbours: neighbours
        )
        
        #expect(response.totalCount == 2)
        #expect(response.neighbours.count == 2)
        #expect(response.neighbours[0].snr == 5.5)
        #expect(response.neighbours[1].secondsAgo == 20)
    }
    
    @Test("MessageSentInfo has correct structure")
    func messageSentInfoStructure() {
        let info = MessageSentInfo(
            type: 0x00,
            expectedAck: Data([0x12, 0x34, 0x56, 0x78]),
            suggestedTimeoutMs: 5000
        )
        
        #expect(info.type == 0x00)
        #expect(info.expectedAck.count == 4)
        #expect(info.suggestedTimeoutMs == 5000)
    }
}
