import Foundation

public enum ClipStatus: String, Codable, Sendable {
    case synced
    case pending
    case invalid
}
