import Foundation

/// A protocol that all MetaVis errors should conform to.
/// Ensures consistent error reporting across the application.
public protocol MetaVisErrorProtocol: LocalizedError, CustomDebugStringConvertible {
    /// A unique code for this error type (useful for telemetry/support).
    var code: Int { get }
    
    /// A user-friendly title for the error.
    var title: String { get }
    
    /// A detailed technical description for debugging.
    var debugDescription: String { get }
}

/// Standard implementation helpers.
extension MetaVisErrorProtocol {
    public var errorDescription: String? {
        return "\(title): \(debugDescription)"
    }
}

/// Generic system errors.
public enum SystemError: MetaVisErrorProtocol {
    case notImplemented(function: String)
    case invalidConfiguration(reason: String)
    
    public var code: Int {
        switch self {
        case .notImplemented: return 1001
        case .invalidConfiguration: return 1002
        }
    }
    
    public var title: String {
        switch self {
        case .notImplemented: return "Not Implemented"
        case .invalidConfiguration: return "Configuration Error"
        }
    }
    
    public var debugDescription: String {
        switch self {
        case .notImplemented(let function): return "Function '\(function)' is not yet implemented."
        case .invalidConfiguration(let reason): return "Invalid configuration: \(reason)"
        }
    }
}
