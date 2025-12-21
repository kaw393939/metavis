import Foundation
import simd

/// The root schema for the MetaVis Director control surface.
/// This defines the high-level, semantic description of a scene.
public struct DirectorSchema: Codable, Sendable {
    public let camera: DirectorCamera
    public let actors: [DirectorActor]
    public let timeline: [DirectorAction]?
    
    public init(camera: DirectorCamera, actors: [DirectorActor], timeline: [DirectorAction]? = nil) {
        self.camera = camera
        self.actors = actors
        self.timeline = timeline
    }
}

// MARK: - Camera

public struct DirectorCamera: Codable, Sendable {
    public let lens: CameraLens
    public let movement: CameraMovement?
    public let position: CameraPosition
    
    public init(lens: CameraLens, movement: CameraMovement? = nil, position: CameraPosition) {
        self.lens = lens
        self.movement = movement
        self.position = position
    }
}

public struct CameraLens: Codable, Sendable {
    /// Lens type preset (e.g., "35mm", "85mm") or custom
    public let type: String
    
    /// Aperture f-stop (e.g., "f/2.8")
    public let aperture: String
    
    /// Focus configuration
    public let focus: CameraFocus
    
    public init(type: String = "35mm", aperture: String = "f/2.8", focus: CameraFocus = .auto) {
        self.type = type
        self.aperture = aperture
        self.focus = focus
    }
    
    /// Converts the lens type string to a vertical Field of View (FOV) in degrees.
    /// Assumes a standard 35mm full-frame sensor (36mm width, 24mm height).
    public var fov: Float {
        let focalLength: Float
        switch type.lowercased() {
        case "14mm", "ultrawide": focalLength = 14.0
        case "24mm", "wide": focalLength = 24.0
        case "35mm", "standard": focalLength = 35.0
        case "50mm", "normal": focalLength = 50.0
        case "85mm", "portrait": focalLength = 85.0
        case "135mm", "telephoto": focalLength = 135.0
        case "200mm", "supertele": focalLength = 200.0
        default:
            // Try to parse "Xmm"
            if let val = Float(type.replacingOccurrences(of: "mm", with: "")) {
                focalLength = val
            } else {
                focalLength = 35.0 // Default
            }
        }
        
        // Calculate Vertical FOV
        // FOV = 2 * atan(sensorHeight / (2 * focalLength))
        let sensorHeight: Float = 24.0
        let fovRadians = 2.0 * atan(sensorHeight / (2.0 * focalLength))
        return fovRadians * 180.0 / .pi
    }
    
    /// Parses the aperture string to a float value
    public var fStop: Float {
        let clean = aperture.replacingOccurrences(of: "f/", with: "")
        return Float(clean) ?? 2.8
    }
}

public struct CameraFocus: Codable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case auto       // Center focus
        case manual     // Fixed distance
        case tracking   // Follow target
    }
    
    public let mode: Mode
    public let target: String? // ID of actor to track
    public let distance: Float? // Manual distance
    
    public static let auto = CameraFocus(mode: .auto, target: nil, distance: nil)
    
    public init(mode: Mode, target: String? = nil, distance: Float? = nil) {
        self.mode = mode
        self.target = target
        self.distance = distance
    }
}

public struct CameraMovement: Codable, Sendable {
    public enum MovementType: String, Codable, Sendable {
        case static_ = "static"
        case dolly
        case truck
        case pan
        case orbit
        case handheld
    }
    
    public let type: MovementType
    public let intensity: Float // 0.0 to 1.0
    public let stabilization: String // "tripod", "handheld", "gimbal"
    
    public init(type: MovementType, intensity: Float = 0.0, stabilization: String = "tripod") {
        self.type = type
        self.intensity = intensity
        self.stabilization = stabilization
    }
}

public struct CameraPosition: Codable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case absolute
        case relative // Relative to subject/center
    }
    
    public let mode: Mode
    public let value: SIMD3<Float>
    
    public init(mode: Mode = .absolute, value: SIMD3<Float>) {
        self.mode = mode
        self.value = value
    }
}

// MARK: - Actor

public struct DirectorActor: Codable, Sendable {
    public let id: String
    public let type: String // "text", "image", "video", "model"
    public let content: String // Text content or file path
    public let transform: ActorTransform
    public let behavior: ActorBehavior?
    public let style: ActorStyle?
    
    public init(id: String, type: String, content: String, transform: ActorTransform, behavior: ActorBehavior? = nil, style: ActorStyle? = nil) {
        self.id = id
        self.type = type
        self.content = content
        self.transform = transform
        self.behavior = behavior
        self.style = style
    }
}

public struct ActorTransform: Codable, Sendable {
    public let position: String // Semantic: "center", "top-left" or JSON array
    public let depth: Float
    public let rotation: SIMD3<Float>
    public let scale: Float
    
    public init(position: String = "center", depth: Float = 0, rotation: SIMD3<Float> = .zero, scale: Float = 1.0) {
        self.position = position
        self.depth = depth
        self.rotation = rotation
        self.scale = scale
    }
}

public struct ActorBehavior: Codable, Sendable {
    public let entrance: String? // "fade_in", "slide_up"
    public let loop: String?     // "hover", "pulse"
    public let exit: String?     // "dissolve"
    
    public init(entrance: String? = nil, loop: String? = nil, exit: String? = nil) {
        self.entrance = entrance
        self.loop = loop
        self.exit = exit
    }
}

public struct ActorStyle: Codable, Sendable {
    public let material: String?
    public let font: String?
    public let color: String?
    
    public init(material: String? = nil, font: String? = nil, color: String? = nil) {
        self.material = material
        self.font = font
        self.color = color
    }
}

// MARK: - Timeline

public struct DirectorAction: Codable, Sendable {
    public let time: Double
    public let action: String // "camera_cut", "focus_pull"
    public let parameters: [String: String]
    
    public init(time: Double, action: String, parameters: [String: String]) {
        self.time = time
        self.action = action
        self.parameters = parameters
    }
}
