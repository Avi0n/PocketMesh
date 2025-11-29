import Foundation

extension Data {
    /// Append uint16 in little-endian format
    mutating func appendUInt16LE(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    /// Read null-terminated string from offset
    func readNullTerminatedString(at offset: Int, maxLength: Int) -> String? {
        guard offset + maxLength <= count else { return nil }
        let subdata = subdata(in: offset ..< offset + maxLength)
        if let nullIndex = subdata.firstIndex(of: 0) {
            return String(data: subdata.prefix(upTo: nullIndex), encoding: .utf8)
        }
        return String(data: subdata, encoding: .utf8)
    }
}
