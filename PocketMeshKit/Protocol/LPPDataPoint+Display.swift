import Foundation

extension LPPDataPoint {
    /// Human-readable name for the data point type
    public var typeName: String {
        switch type {
        case .digitalInput: return "Digital Input"
        case .digitalOutput: return "Digital Output"
        case .analogInput: return "Analog Input"
        case .analogOutput: return "Analog Output"
        case .genericSensor: return "Sensor"
        case .illuminance: return "Illuminance"
        case .presence: return "Presence"
        case .temperature: return "Temperature"
        case .humidity: return "Humidity"
        case .accelerometer: return "Accelerometer"
        case .barometer: return "Barometer"
        case .voltage: return "Voltage"
        case .current: return "Current"
        case .frequency: return "Frequency"
        case .percentage: return "Percentage"
        case .altitude: return "Altitude"
        case .load: return "Load"
        case .concentration: return "Concentration"
        case .power: return "Power"
        case .distance: return "Distance"
        case .energy: return "Energy"
        case .direction: return "Direction"
        case .time: return "Time"
        case .gyrometer: return "Gyrometer"
        case .colour: return "Colour"
        case .gps: return "GPS"
        case .switchValue: return "Switch"
        }
    }

    /// Formatted value with appropriate units
    public var formattedValue: String {
        switch value {
        case .integer(let val):
            return formatIntegerValue(val)
        case .float(let val):
            return formatFloatValue(val)
        case .vector3(let x, let y, let z):
            return formatVector3(x: x, y: y, z: z)
        case .gps(let lat, let lon, let alt):
            return String(format: "%.6f, %.6f @ %.1fm", lat, lon, alt)
        case .rgb(let r, let g, let b):
            return "RGB(\(r), \(g), \(b))"
        }
    }

    /// Format integer values based on type
    private func formatIntegerValue(_ val: Int) -> String {
        switch type {
        case .digitalInput, .digitalOutput, .presence, .switchValue:
            return val != 0 ? "On" : "Off"
        case .percentage:
            return "\(val)%"
        case .illuminance:
            return "\(val) lux"
        case .direction:
            return "\(val)\u{00B0}"  // degree symbol
        case .time:
            let date = Date(timeIntervalSince1970: TimeInterval(val))
            return date.formatted(date: .abbreviated, time: .shortened)
        default:
            return val.formatted()
        }
    }

    /// Format float values based on type
    private func formatFloatValue(_ val: Float) -> String {
        switch type {
        case .temperature:
            return String(format: "%.1f\u{00B0}C", val)  // degree symbol
        case .humidity:
            return String(format: "%.1f%%", val)
        case .barometer:
            return String(format: "%.1f hPa", val)
        case .voltage:
            return String(format: "%.2f V", val)
        case .current:
            return String(format: "%.3f A", val)
        case .altitude:
            return String(format: "%.1f m", val)
        case .power:
            return String(format: "%.1f W", val)
        case .distance:
            return String(format: "%.2f m", val)
        case .energy:
            return String(format: "%.2f Wh", val)
        case .load:
            return String(format: "%.1f kg", val)
        case .concentration:
            return String(format: "%.0f ppm", val)
        case .frequency:
            return String(format: "%.1f Hz", val)
        default:
            return String(format: "%.2f", val)
        }
    }

    /// Format vector3 values based on type
    private func formatVector3(x: Float, y: Float, z: Float) -> String {
        switch type {
        case .accelerometer:
            return String(format: "X:%.2f Y:%.2f Z:%.2f g", x, y, z)
        case .gyrometer:
            return String(format: "X:%.1f Y:%.1f Z:%.1f \u{00B0}/s", x, y, z)
        default:
            return String(format: "X:%.2f Y:%.2f Z:%.2f", x, y, z)
        }
    }
}
