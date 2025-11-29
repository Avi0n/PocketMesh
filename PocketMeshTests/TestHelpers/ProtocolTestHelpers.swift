import Foundation
@testable import PocketMeshKit
import XCTest

public enum ProtocolTestHelpers {
    /// Validate that a frame has the expected command code
    public static func assertFrameCode(
        _ frame: ProtocolFrame,
        equals expectedCode: UInt8,
        file: StaticString = #file,
        line: UInt = #line,
    ) {
        XCTAssertEqual(frame.code, expectedCode, "Frame code mismatch", file: file, line: line)
    }

    /// Validate that a frame has minimum payload size
    public static func assertMinimumPayloadSize(
        _ frame: ProtocolFrame,
        minimumBytes: Int,
        file: StaticString = #file,
        line: UInt = #line,
    ) {
        XCTAssertGreaterThanOrEqual(
            frame.payload.count,
            minimumBytes,
            "Payload too small: expected at least \(minimumBytes) bytes, got \(frame.payload.count)",
            file: file,
            line: line,
        )
    }

    /// Decode a UInt32 from little-endian bytes at offset
    public static func decodeUInt32LE(from data: Data, at offset: Int = 0) -> UInt32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    }

    /// Decode a UInt16 from little-endian bytes at offset
    public static func decodeUInt16LE(from data: Data, at offset: Int = 0) -> UInt16 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
    }

    /// Decode an Int32 from little-endian bytes at offset
    public static func decodeInt32LE(from data: Data, at offset: Int = 0) -> Int32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Int32.self) }
    }

    /// Extract null-terminated string from data at offset
    public static func extractNullTerminatedString(
        from data: Data,
        at offset: Int,
        maxLength: Int,
    ) -> String {
        let endIndex = min(offset + maxLength, data.count)
        let substring = data[offset ..< endIndex]

        if let nullIndex = substring.firstIndex(of: 0) {
            return String(data: substring[offset ..< nullIndex], encoding: .utf8) ?? ""
        } else {
            return String(data: substring, encoding: .utf8) ?? ""
        }
    }
}
