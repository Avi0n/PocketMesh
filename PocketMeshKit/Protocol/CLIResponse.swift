import Foundation

/// Parsed CLI response from repeater
public enum CLIResponse: Sendable, Equatable {
    case ok
    case error(String)
    case unknownCommand(String)  // Specific case for "Error: unknown command"
    case version(String)
    case deviceTime(String)
    case name(String)
    case radio(frequency: Double, bandwidth: Double, spreadingFactor: Int, codingRate: Int)
    case txPower(Int)
    case repeatMode(Bool)
    case advertInterval(Int)
    case floodAdvertInterval(Int)  // Value is in hours, not minutes
    case floodMax(Int)
    case latitude(Double)
    case longitude(Double)
    case raw(String)

    /// Parse a CLI response text into a structured type
    /// Note: Response correlation must be handled by the caller based on pending query tracking
    public static func parse(_ text: String, forQuery query: String? = nil) -> CLIResponse {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed == "OK" {
            return .ok
        }

        if trimmed.lowercased().hasPrefix("error") {
            // Check for "unknown command" specifically for defensive handling
            if trimmed.lowercased().contains("unknown command") {
                return .unknownCommand(trimmed)
            }
            return .error(trimmed)
        }

        // Firmware version: "MeshCore v1.10.0 (2025-04-18)" or "v1.11.0 (2025-04-18)"
        // Some firmware builds omit "MeshCore " prefix
        if trimmed.hasPrefix("MeshCore v") || (trimmed.hasPrefix("v") && trimmed.contains("(")) {
            return .version(trimmed)
        }

        // Clock response: "06:40 - 18/4/2025 UTC" or contains time-like patterns
        if trimmed.contains("UTC") || (trimmed.contains(":") && trimmed.contains("/")) {
            return .deviceTime(trimmed)
        }

        // Radio params: "915.000,250.0,10,5" (freq,bw,sf,cr)
        // Use query hint to disambiguate from other comma-separated values
        if query == "get radio" {
            let parts = trimmed.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count >= 4,
               let freq = Double(parts[0]),
               let bw = Double(parts[1]),
               let sf = Int(parts[2]),
               let cr = Int(parts[3]) {
                return .radio(frequency: freq, bandwidth: bw, spreadingFactor: sf, codingRate: cr)
            }
        }

        // TX power: integer dBm value
        if query == "get tx", let power = Int(trimmed) {
            return .txPower(power)
        }

        // Repeat mode: "on" or "off"
        if query == "get repeat" {
            if trimmed.lowercased() == "on" {
                return .repeatMode(true)
            } else if trimmed.lowercased() == "off" {
                return .repeatMode(false)
            }
        }

        // Advert interval: integer minutes
        if query == "get advert.interval", let interval = Int(trimmed) {
            return .advertInterval(interval)
        }

        // Flood advert interval: integer hours
        if query == "get flood.advert.interval", let interval = Int(trimmed) {
            return .floodAdvertInterval(interval)
        }

        // Flood max: integer hops
        if query == "get flood.max", let maxHops = Int(trimmed) {
            return .floodMax(maxHops)
        }

        // Name is plain text - use query hint
        if query == "get name" {
            return .name(trimmed)
        }

        // Latitude: decimal degrees
        if query == "get lat", let lat = Double(trimmed) {
            return .latitude(lat)
        }

        // Longitude: decimal degrees
        if query == "get lon", let lon = Double(trimmed) {
            return .longitude(lon)
        }

        return .raw(trimmed)
    }
}
