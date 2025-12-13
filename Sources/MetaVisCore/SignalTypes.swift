import Foundation

/// Defines the fundamental types of data flowing through the system.
public enum SignalKind: String, Sendable, Codable, Equatable {
    case video              // RGBA Float16 Stream
    case audio              // PCM Float32 Interleaved
    case event              // MIDI / Control Data
    case generativePrompt   // String / Embedding
}

/// Defines the data type for a Node Port.
public enum PortType: String, Codable, Hashable, Sendable {
    case image          // Corresponds to SignalKind.video
    case audio          // Corresponds to SignalKind.audio
    case texture3d      // Volumetric Texture (LUT)
    case float          // Single scalar parameter
    case int            // Integer parameter
    case bool           // Boolean flag
    case vector3        // 3D Vector
    case color          // 4D Vector (RGBA)
    case string         // Text data
    case event          // Trigger signal
    case unknown
}

/// Protocol used to define generic payload data for a signal.
public protocol SignalData: Sendable, Codable {
    var kind: SignalKind { get }
}
