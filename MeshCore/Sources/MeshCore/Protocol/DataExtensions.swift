import Foundation

// MARK: - Data Extensions for Binary Reading

extension Data {
    /// Hex digits lookup table (static to avoid repeated allocation)
    private static let hexDigits = Array("0123456789abcdef".utf8)

    /// Hex string representation (optimized)
    public var hexString: String {
        var chars = [UInt8](repeating: 0, count: count * 2)
        for (i, byte) in enumerated() {
            chars[i * 2] = Self.hexDigits[Int(byte >> 4)]
            chars[i * 2 + 1] = Self.hexDigits[Int(byte & 0x0F)]
        }
        return String(decoding: chars, as: UTF8.self)
    }

    /// Initialize Data from hex string (for test fixtures and contact ID handling)
    public init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex
        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }

    /// Read UInt32 little-endian at offset (uses loadUnaligned for safety)
    public func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return self.dropFirst(offset).withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))
        }
    }

    /// Read Int32 little-endian at offset (uses loadUnaligned for safety)
    public func readInt32LE(at offset: Int) -> Int32 {
        guard offset + 4 <= count else { return 0 }
        return self.dropFirst(offset).withUnsafeBytes {
            Int32(littleEndian: $0.loadUnaligned(as: Int32.self))
        }
    }

    /// Read UInt16 little-endian at offset (uses loadUnaligned for safety)
    public func readUInt16LE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return self.dropFirst(offset).withUnsafeBytes {
            UInt16(littleEndian: $0.loadUnaligned(as: UInt16.self))
        }
    }

    /// Read Int16 little-endian at offset (uses loadUnaligned for safety)
    public func readInt16LE(at offset: Int) -> Int16 {
        guard offset + 2 <= count else { return 0 }
        return self.dropFirst(offset).withUnsafeBytes {
            Int16(littleEndian: $0.loadUnaligned(as: Int16.self))
        }
    }

    // Legacy aliases for compatibility
    public func readUInt32(at offset: Int) -> UInt32 { readUInt32LE(at: offset) }
    public func readInt32(at offset: Int) -> Int32 { readInt32LE(at: offset) }
    public func readUInt16(at offset: Int) -> UInt16 { readUInt16LE(at: offset) }
    public func readInt16(at offset: Int) -> Int16 { readInt16LE(at: offset) }
}

// MARK: - SNR Helper

extension Int8 {
    /// Convert raw SNR byte to Double (MeshCore uses SNR * 4 encoding)
    public var snrValue: Double {
        Double(self) / 4.0
    }
}

extension UInt8 {
    /// Convert raw SNR byte (signed) to Double
    public var snrValue: Double {
        Int8(bitPattern: self).snrValue
    }
}
