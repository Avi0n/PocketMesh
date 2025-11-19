import XCTest
@testable import PocketMeshKit

final class PerformanceTests: XCTestCase {

    func testMessageEncodingPerformance() {
        measure {
            for _ in 0..<1000 {
                let frame = ProtocolFrame(code: 2, payload: Data(repeating: 0x41, count: 160))
                _ = frame.encode()
            }
        }
    }

    func testFrameDecodingPerformance() throws {
        let testFrame = ProtocolFrame(code: 2, payload: Data(repeating: 0x41, count: 160))
        let encoded = testFrame.encode()

        measure {
            for _ in 0..<1000 {
                _ = try? ProtocolFrame.decode(encoded)
            }
        }
    }

    func testHashGenerationPerformance() {
        measure {
            for i in 0..<100 {
                let channelName = "test-channel-\(i)"
                let nameData = channelName.data(using: .utf8)!
                let hash = SHA256.hash(data: nameData)
                _ = Data(hash.prefix(16))
            }
        }
    }

    func testLargePayloadEncoding() {
        // Test maximum protocol frame size
        let maxPayload = Data(repeating: 0xFF, count: 255)

        measure {
            for _ in 0..<100 {
                let frame = ProtocolFrame(code: 1, payload: maxPayload)
                _ = frame.encode()
            }
        }
    }

    func testCoordinateConversion() {
        let coordinates = [(37.7749, -122.4194), (40.7128, -74.0060), (51.5074, -0.1278)]

        measure {
            for _ in 0..<1000 {
                for (lat, lon) in coordinates {
                    let latInt = Int32(lat * 1_000_000)
                    let lonInt = Int32(lon * 1_000_000)
                    _ = Double(latInt) / 1_000_000
                    _ = Double(lonInt) / 1_000_000
                }
            }
        }
    }
}

import CryptoKit
