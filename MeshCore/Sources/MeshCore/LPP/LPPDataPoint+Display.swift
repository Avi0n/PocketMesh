import Foundation

extension LPPDataPoint {

    /// Returns the human-readable name of the sensor type.
    public var typeName: String { type.name }

    /// Returns the calculated battery percentage if the sensor type is voltage.
    ///
    /// Estimates percentage based on a standard LiPo battery range (3.0V to 4.2V).
    /// Returns `nil` if the sensor type is not voltage or the value is not a float.
    public var batteryPercentage: Int? {
        guard type == .voltage, case .float(let volts) = value else { return nil }
        // LiPo: 4.2V = 100%, 3.0V = 0%
        let percent = ((volts - 3.0) / 1.2) * 100
        return Int(min(100, max(0, percent)))
    }

    /// Returns a localized, human-readable string representation of the sensor value.
    ///
    /// The output includes appropriate units based on the sensor type (e.g., "°C", "%", "hPa", "V").
    public var formattedValue: String {
        switch value {
        case .digital(let on):
            on ? "On" : "Off"
        case .integer(let val):
            formatInteger(val)
        case .float(let val):
            formatFloat(val)
        case .vector3(let x, let y, let z):
            formatVector3(x: x, y: y, z: z)
        case .gps(let lat, let lon, let alt):
            "\(lat.formatted(.number.precision(.fractionLength(6)))), \(lon.formatted(.number.precision(.fractionLength(6)))) @ \(alt.formatted(.number.precision(.fractionLength(1))))m"
        case .rgb(let r, let g, let b):
            "RGB(\(r), \(g), \(b))"
        case .timestamp(let date):
            date.formatted(date: .abbreviated, time: .shortened)
        }
    }

    /// Formats an integer value with its corresponding unit.
    ///
    /// - Parameter val: The integer value to format.
    /// - Returns: A formatted string with units.
    private func formatInteger(_ val: Int) -> String {
        switch type {
        case .percentage:
            "\(val)%"
        case .illuminance:
            "\(val) lux"
        case .direction:
            "\(val)\u{00B0}"
        case .concentration:
            "\(val) ppm"
        case .power:
            "\(val) W"
        case .frequency:
            "\(val) Hz"
        default:
            val.formatted()
        }
    }

    /// Formats a floating-point value with its corresponding unit and precision.
    ///
    /// - Parameter val: The floating-point value to format.
    /// - Returns: A formatted string with units.
    private func formatFloat(_ val: Double) -> String {
        switch type {
        case .temperature:
            "\(val.formatted(.number.precision(.fractionLength(1))))\u{00B0}C"
        case .humidity:
            "\(val.formatted(.number.precision(.fractionLength(1))))%"
        case .barometer:
            "\(val.formatted(.number.precision(.fractionLength(1)))) hPa"
        case .voltage:
            "\(val.formatted(.number.precision(.fractionLength(2)))) V"
        case .current:
            "\(val.formatted(.number.precision(.fractionLength(3)))) A"
        case .altitude:
            "\(val.formatted(.number.precision(.fractionLength(1)))) m"
        case .distance:
            "\(val.formatted(.number.precision(.fractionLength(2)))) m"
        case .energy:
            "\(val.formatted(.number.precision(.fractionLength(3)))) kWh"
        case .load:
            "\(val.formatted(.number.precision(.fractionLength(2)))) kg"
        case .analogInput, .analogOutput:
            val.formatted(.number.precision(.fractionLength(2)))
        default:
            val.formatted(.number.precision(.fractionLength(2)))
        }
    }

    /// Formats a 3D vector value with its corresponding unit and labels.
    ///
    /// - Parameters:
    ///   - x: The X-axis value.
    ///   - y: The Y-axis value.
    ///   - z: The Z-axis value.
    /// - Returns: A formatted string with axis labels and units.
    private func formatVector3(x: Double, y: Double, z: Double) -> String {
        switch type {
        case .accelerometer:
            "X:\(x.formatted(.number.precision(.fractionLength(3)))) Y:\(y.formatted(.number.precision(.fractionLength(3)))) Z:\(z.formatted(.number.precision(.fractionLength(3)))) g"
        case .gyrometer:
            "X:\(x.formatted(.number.precision(.fractionLength(1)))) Y:\(y.formatted(.number.precision(.fractionLength(1)))) Z:\(z.formatted(.number.precision(.fractionLength(1)))) \u{00B0}/s"
        default:
            "X:\(x.formatted(.number.precision(.fractionLength(2)))) Y:\(y.formatted(.number.precision(.fractionLength(2)))) Z:\(z.formatted(.number.precision(.fractionLength(2))))"
        }
    }
}
