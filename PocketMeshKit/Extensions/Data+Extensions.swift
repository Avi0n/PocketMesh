import Foundation

public extension Data {
    /// Convert Data to hexadecimal string representation
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
