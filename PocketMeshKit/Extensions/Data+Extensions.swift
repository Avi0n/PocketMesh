import Foundation

public extension Data {
    /// Converts data to uppercase hex string with optional separator between bytes
    /// - Parameter separator: String to insert between each byte (default: none)
    /// - Returns: Hex string representation
    func hexString(separator: String = "") -> String {
        map { String(format: "%02X", $0) }.joined(separator: separator)
    }

    /// Initialize Data from a hex string
    /// - Parameter hexString: Hex string (e.g., "AABBCC" or "AA BB CC")
    init?(hexString: String) {
        // Filter to only hex digits and uppercase
        let hex = hexString.filter { $0.isHexDigit }.uppercased()
        guard hex.count % 2 == 0 else { return nil }

        var data = Data()
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }
}
