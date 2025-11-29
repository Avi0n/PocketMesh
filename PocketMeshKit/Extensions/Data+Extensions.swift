import Foundation

public extension Data {
    /// Convert Data to hexadecimal string representation
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// Append UInt32 as little-endian bytes
    mutating func appendUInt32LE(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    /// Append Int32 as little-endian bytes
    mutating func appendInt32LE(_ value: Int32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
