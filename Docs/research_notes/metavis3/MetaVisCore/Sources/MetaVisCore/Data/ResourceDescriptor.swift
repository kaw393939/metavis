import Foundation

/// Defines the physical location of a resource.
/// This allows us to switch between "Reference" (External) and "Portable" (Bundled) modes.
public enum ResourceLocation: Codable, Hashable, Sendable {
    /// A file living on the user's disk (e.g., Downloads folder).
    /// - Parameters:
    ///   - absolutePath: The full path to the file.
    ///   - bookmarkData: Security Scoped Bookmark data (required for macOS App Sandbox access).
    case external(absolutePath: String, bookmarkData: Data?)
    
    /// A file living inside the project's .mvproj bundle.
    /// - Parameter relativePath: Path relative to the bundle root (e.g., "assets/video.mp4").
    case bundled(relativePath: String)
    
    /// A system-managed asset (e.g., PhotoKit asset, SF Symbol).
    case system(identifier: String)
    
    /// A remote resource (e.g., HTTP Live Stream).
    case remote(url: URL)
    
    /// A procedurally generated resource (no file backing).
    case procedural(identifier: String)
}

/// The type of media content.
public enum ResourceType: String, Codable, Hashable, Sendable {
    case video
    case image
    case audio
    case model3D
    case text
    case shader
    case unknown
}

/// A polymorphic descriptor for any asset used in the project.
/// This struct is "Passive Data" - it has no logic or observers.
public struct ResourceDescriptor: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var type: ResourceType
    public var location: ResourceLocation
    
    /// Metadata specific to the resource (e.g., duration, resolution).
    /// Stored as a simple dictionary to be flexible.
    public var metadata: [String: String]
    
    public init(id: UUID = UUID(), name: String, type: ResourceType, location: ResourceLocation, metadata: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.type = type
        self.location = location
        self.metadata = metadata
    }
}
