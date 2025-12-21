import Foundation

/// A LookAsset represents a reusable visual style (Color Grade, Effects, etc.).
/// It wraps a Preset with additional metadata for the "Style Transfer" workflow.
public struct LookAsset: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String
    
    /// The node graph definition that applies this look.
    public let preset: Preset
    
    /// Optional path to a reference image (thumbnail or source frame).
    public let referenceImagePath: String?
    
    /// Keywords for semantic search (e.g. "Cyberpunk", "Vintage", "High Key").
    public let tags: [String]
    
    /// Additional metadata (e.g. "Source Film: Blade Runner", "Author: AI").
    public let metadata: [String: String]
    
    public init(
        id: UUID = UUID(),
        name: String,
        preset: Preset,
        referenceImagePath: String? = nil,
        tags: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.preset = preset
        self.referenceImagePath = referenceImagePath
        self.tags = tags
        self.metadata = metadata
    }
}
