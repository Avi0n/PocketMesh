import XCTest
@testable import MeshCore

final class TraceDataParsingTests: XCTestCase {

    func test_traceData_pathSz0_singleByteHashes() {
        // path_sz=0: 1-byte hashes, pathLength = hop count
        var payload = Data()
        payload.append(0x00)  // Reserved
        payload.append(0x02)  // pathLength = 2 hashes
        payload.append(0x00)  // flags: path_sz = 0
        payload.appendLittleEndian(UInt32(12345))  // tag
        payload.appendLittleEndian(UInt32(67890))  // authCode
        payload.append(contentsOf: [0xAA, 0xBB])   // 2 hash bytes
        payload.append(contentsOf: [0x28, 0x14])   // 2 SNR bytes (10.0, 5.0)
        payload.append(0x0C)                        // final SNR (3.0)

        let event = Parsers.TraceData.parse(payload)

        guard case .traceData(let trace) = event else {
            XCTFail("Expected traceData, got \(event)")
            return
        }

        XCTAssertEqual(trace.tag, 12345)
        XCTAssertEqual(trace.authCode, 67890)
        XCTAssertEqual(trace.path.count, 3, "Should have 2 hops + 1 destination")

        // Check hash bytes
        XCTAssertEqual(trace.path[0].hashBytes, Data([0xAA]))
        XCTAssertEqual(trace.path[1].hashBytes, Data([0xBB]))
        XCTAssertNil(trace.path[2].hashBytes, "Destination has no hash")

        // Check SNRs
        XCTAssertEqual(trace.path[0].snr, 10.0, accuracy: 0.001)
        XCTAssertEqual(trace.path[1].snr, 5.0, accuracy: 0.001)
        XCTAssertEqual(trace.path[2].snr, 3.0, accuracy: 0.001)
    }

    func test_traceData_pathSz2_fourByteHashes() {
        // path_sz=2: 4-byte hashes, hopCount = pathLength / 4
        var payload = Data()
        payload.append(0x00)  // Reserved
        payload.append(0x08)  // pathLength = 8 hash bytes = 2 hops
        payload.append(0x02)  // flags: path_sz = 2 (means 4 bytes per hash)
        payload.appendLittleEndian(UInt32(111))  // tag
        payload.appendLittleEndian(UInt32(222))  // authCode
        // 8 hash bytes (2 hops x 4 bytes)
        payload.append(contentsOf: [0x11, 0x22, 0x33, 0x44])  // hop 0
        payload.append(contentsOf: [0x55, 0x66, 0x77, 0x88])  // hop 1
        // 2 SNR bytes (one per hop)
        payload.append(contentsOf: [0x28, 0x14])  // SNRs: 10.0, 5.0
        payload.append(0x0C)  // final SNR: 3.0

        let event = Parsers.TraceData.parse(payload)

        guard case .traceData(let trace) = event else {
            XCTFail("Expected traceData, got \(event)")
            return
        }

        XCTAssertEqual(trace.path.count, 3, "Should have 2 hops + 1 destination")

        // Check 4-byte hashes
        XCTAssertEqual(trace.path[0].hashBytes, Data([0x11, 0x22, 0x33, 0x44]))
        XCTAssertEqual(trace.path[1].hashBytes, Data([0x55, 0x66, 0x77, 0x88]))
        XCTAssertNil(trace.path[2].hashBytes)

        // Legacy hash accessor (first byte only)
        XCTAssertEqual(trace.path[0].hash, 0x11)
    }

    func test_traceData_pathSz1_twoByteHashes() {
        // path_sz=1: 2-byte hashes, hopCount = pathLength / 2
        var payload = Data()
        payload.append(0x00)  // Reserved
        payload.append(0x04)  // pathLength = 4 hash bytes = 2 hops
        payload.append(0x01)  // flags: path_sz = 1 (means 2 bytes per hash)
        payload.appendLittleEndian(UInt32(100))  // tag
        payload.appendLittleEndian(UInt32(200))  // authCode
        // 4 hash bytes (2 hops x 2 bytes)
        payload.append(contentsOf: [0xAA, 0xBB])  // hop 0
        payload.append(contentsOf: [0xCC, 0xDD])  // hop 1
        // 2 SNR bytes (one per hop)
        payload.append(contentsOf: [0x28, 0x14])  // SNRs: 10.0, 5.0
        payload.append(0x0C)  // final SNR: 3.0

        let event = Parsers.TraceData.parse(payload)

        guard case .traceData(let trace) = event else {
            XCTFail("Expected traceData, got \(event)")
            return
        }

        XCTAssertEqual(trace.path.count, 3, "Should have 2 hops + 1 destination")

        // Check 2-byte hashes
        XCTAssertEqual(trace.path[0].hashBytes, Data([0xAA, 0xBB]))
        XCTAssertEqual(trace.path[1].hashBytes, Data([0xCC, 0xDD]))
        XCTAssertNil(trace.path[2].hashBytes)
    }

    func test_traceData_destinationMarker() {
        // 0xFF hash means destination (no hash)
        var payload = Data()
        payload.append(0x00)  // Reserved
        payload.append(0x01)  // pathLength = 1
        payload.append(0x00)  // flags: path_sz = 0
        payload.appendLittleEndian(UInt32(1))  // tag
        payload.appendLittleEndian(UInt32(2))  // authCode
        payload.append(0xFF)  // hash = 0xFF (destination marker)
        payload.append(0x28)  // SNR
        payload.append(0x14)  // final SNR

        let event = Parsers.TraceData.parse(payload)

        guard case .traceData(let trace) = event else {
            XCTFail("Expected traceData")
            return
        }

        // 0xFF hash should be interpreted as destination (nil)
        XCTAssertNil(trace.path[0].hashBytes)
    }

    func test_traceData_emptyPath() {
        // pathLength = 0 means direct connection (no intermediate hops)
        var payload = Data()
        payload.append(0x00)  // Reserved
        payload.append(0x00)  // pathLength = 0
        payload.append(0x00)  // flags: path_sz = 0
        payload.appendLittleEndian(UInt32(999))  // tag
        payload.appendLittleEndian(UInt32(888))  // authCode
        payload.append(0x28)  // final SNR only

        let event = Parsers.TraceData.parse(payload)

        guard case .traceData(let trace) = event else {
            XCTFail("Expected traceData, got \(event)")
            return
        }

        XCTAssertEqual(trace.path.count, 1, "Should have destination only")
        XCTAssertNil(trace.path[0].hashBytes, "Destination has no hash")
        XCTAssertEqual(trace.path[0].snr, 10.0, accuracy: 0.001)
    }

    func test_traceData_legacyHashAccessor() {
        // Verify legacy hash property works correctly
        var payload = Data()
        payload.append(0x00)  // Reserved
        payload.append(0x01)  // pathLength = 1
        payload.append(0x00)  // flags: path_sz = 0
        payload.appendLittleEndian(UInt32(1))  // tag
        payload.appendLittleEndian(UInt32(2))  // authCode
        payload.append(0x42)  // hash
        payload.append(0x28)  // SNR
        payload.append(0x14)  // final SNR

        let event = Parsers.TraceData.parse(payload)

        guard case .traceData(let trace) = event else {
            XCTFail("Expected traceData")
            return
        }

        // Legacy accessor should return first byte
        XCTAssertEqual(trace.path[0].hash, 0x42)
        XCTAssertNil(trace.path[1].hash, "Destination has no hash")
    }

    func test_traceData_tooShortPayload() {
        // Less than 11 bytes should fail
        let shortPayload = Data([0x00, 0x01, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])

        let event = Parsers.TraceData.parse(shortPayload)

        guard case .parseFailure = event else {
            XCTFail("Expected parseFailure for short payload")
            return
        }
    }

    func test_traceNode_initWithHashBytes() {
        let node = TraceNode(hashBytes: Data([0x11, 0x22, 0x33]), snr: 5.5)
        XCTAssertEqual(node.hashBytes, Data([0x11, 0x22, 0x33]))
        XCTAssertEqual(node.snr, 5.5)
        XCTAssertEqual(node.hash, 0x11, "Legacy accessor returns first byte")
    }

    func test_traceNode_initWithNilHashBytes() {
        let node = TraceNode(hashBytes: nil, snr: 3.0)
        XCTAssertNil(node.hashBytes)
        XCTAssertNil(node.hash)
        XCTAssertEqual(node.snr, 3.0)
    }

    func test_traceNode_legacyInitWithHash() {
        let node = TraceNode(hash: 0xAB, snr: 7.5)
        XCTAssertEqual(node.hashBytes, Data([0xAB]))
        XCTAssertEqual(node.hash, 0xAB)
        XCTAssertEqual(node.snr, 7.5)
    }

    func test_traceNode_legacyInitWithNilHash() {
        let node = TraceNode(hash: nil, snr: 2.0)
        XCTAssertNil(node.hashBytes)
        XCTAssertNil(node.hash)
        XCTAssertEqual(node.snr, 2.0)
    }

}
