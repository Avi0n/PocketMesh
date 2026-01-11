import Foundation

public enum DebugLogLevel: Int, Sendable, CaseIterable {
    case debug = 0
    case info = 1
    case notice = 2
    case warning = 3
    case error = 4
    case fault = 5

    public var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        }
    }
}
