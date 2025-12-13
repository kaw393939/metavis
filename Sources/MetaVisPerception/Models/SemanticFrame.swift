import Foundation
import CoreGraphics
import MetaVisCore

/// A semantic description of a single video frame.
/// This structure acts as the "Eyes" for the Local LLM, providing it with structured vision data.
public struct SemanticFrame: Sendable, Codable, Equatable {
    
    public let timestamp: TimeInterval
    public let subjects: [DetectedSubject]
    public let contextTags: [String] // e.g. "Daylight", "Indoor", "Crowded"
    
    public init(timestamp: TimeInterval, subjects: [DetectedSubject], contextTags: [String] = []) {
        self.timestamp = timestamp
        self.subjects = subjects
        self.contextTags = contextTags
    }
}

/// A subject detected in the frame (Person, Object, etc).
public struct DetectedSubject: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID // UUID from Object Tracking (Diarization)
    public let rect: CGRect // Normalized 0-1
    public let label: String // "Person", "Face", "Shirt", "Dog"
    public let attributes: [String: String] // { "emotion": "Happy", "color": "Red" }
    
    public init(id: UUID = UUID(), rect: CGRect, label: String, attributes: [String : String] = [:]) {
        self.id = id
        self.rect = rect
        self.label = label
        self.attributes = attributes
    }
}
