import Foundation

/// The structured intention extracted from the LLM's response.
/// This acts as the command that the system executes.
public struct UserIntent: Codable, Sendable, Equatable {
    
    public enum Action: String, Codable, Sendable {
        case colorGrade = "color_grade"
        case cut = "cut"
        case speed = "speed"
        case move = "move"
        case trimIn = "trim_in"
        case trimEnd = "trim_end"
        case rippleTrimOut = "ripple_trim_out"
        case rippleTrimIn = "ripple_trim_in"
        case rippleDelete = "ripple_delete"
        case unknown = "unknown"
    }
    
    public let action: Action
    /// Semantic target (e.g. "shirt", "background", "clip"); may be empty for purely temporal edits.
    public let target: String
    public let params: [String: Double] // Flattened params for simplicity

    /// Optional deterministic targeting when the UI/tooling can provide a specific clip.
    public let clipId: UUID?
    
    public init(action: Action, target: String, params: [String : Double], clipId: UUID? = nil) {
        self.action = action
        self.target = target
        self.params = params
        self.clipId = clipId
    }
}

public extension UserIntent {
    /// Human-readable schema description used to constrain model outputs.
    static let jsonSchemaDescription: String = #"""
Return JSON only, matching this schema exactly:
{
  "action": "color_grade|cut|speed|move|trim_in|trim_end|ripple_trim_out|ripple_trim_in|ripple_delete",
  "target": "string",               // may be empty for purely temporal edits
  "params": { "key": number, ... }, // numbers must be finite
  "clipId": "uuid"                   // optional; include when targeting a specific clip
}
No markdown, no code fences, no extra top-level keys.
"""#
}
