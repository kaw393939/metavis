import Foundation

/// The structured intention extracted from the LLM's response.
/// This acts as the command that the system executes.
public struct UserIntent: Codable, Sendable, Equatable {
    
    public enum Action: String, Codable, Sendable {
        case colorGrade = "color_grade"
        case cut = "cut"
        case speed = "speed"
        case unknown = "unknown"
    }
    
    public let action: Action
    public let target: String // "shirt", "background", "clip"
    public let params: [String: Double] // Flattened params for simplicity
    
    public init(action: Action, target: String, params: [String : Double]) {
        self.action = action
        self.target = target
        self.params = params
    }
}
