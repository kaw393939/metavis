import Foundation
import simd

public struct RenderManifest: Codable, Sendable {
    public let metadata: ManifestMetadata
    public let scene: SceneDefinition
    public let camera: CameraDefinition
    
    /// Node-based composition graph (FUTURE - will replace layers)
    public let graph: NodeGraph?
    
    /// Layer-based composition system (NEW - preferred for complex projects)
    public let layers: [Layer]?
    
    /// Legacy element system (DEPRECATED - use layers instead)
    public let elements: [ManifestElement]?
    
    /// Legacy single source video (DEPRECATED - use video layer instead)
    public let source: SourceDefinition?
    
    public let postProcessing: PostProcessDefinition?
    public let compositing: CompositingDefinition?
    
    public init(
        metadata: ManifestMetadata,
        scene: SceneDefinition,
        camera: CameraDefinition,
        graph: NodeGraph? = nil,
        layers: [Layer]? = nil,
        elements: [ManifestElement]? = nil,
        postProcessing: PostProcessDefinition? = nil,
        compositing: CompositingDefinition? = nil,
        source: SourceDefinition? = nil
    ) {
        self.metadata = metadata
        self.scene = scene
        self.camera = camera
        self.graph = graph
        self.layers = layers
        self.elements = elements
        self.postProcessing = postProcessing
        self.compositing = compositing
        self.source = source
    }
    
    /// Returns true if using new layer-based system
    public var usesLayers: Bool {
        layers != nil && !(layers?.isEmpty ?? true)
    }
    
    /// Returns true if using legacy element system
    public var usesLegacyElements: Bool {
        !usesLayers && (elements != nil || source != nil)
    }
    
    /// Validates manifest for common errors
    /// - Throws: ValidationError if manifest has invalid data
    public func validate() throws {
        // Validate metadata
        guard metadata.fps > 0 && metadata.fps <= 240 else {
            throw ValidationError.invalidParameter("FPS must be in range (0, 240], got \(metadata.fps)")
        }
        guard metadata.resolution.x > 0 && metadata.resolution.y > 0 else {
            throw ValidationError.invalidParameter("Resolution must be positive, got \(metadata.resolution.x)x\(metadata.resolution.y)")
        }
        guard metadata.duration >= 0 else {
            throw ValidationError.invalidParameter("Duration must be non-negative, got \(metadata.duration)")
        }
        
        // Validate camera
        guard camera.fov > 0 && camera.fov < 180 else {
            throw ValidationError.invalidParameter("Camera FOV must be in range (0, 180), got \(camera.fov)")
        }
        guard !camera.position.x.isNaN && !camera.position.y.isNaN && !camera.position.z.isNaN else {
            throw ValidationError.invalidParameter("Camera position contains NaN")
        }
        guard !camera.target.x.isNaN && !camera.target.y.isNaN && !camera.target.z.isNaN else {
            throw ValidationError.invalidParameter("Camera target contains NaN")
        }
        
        // Validate scene background if procedural
        if let procBg = scene.proceduralBackground {
            switch procBg {
            case .gradient(let g):
                try g.validate()
            case .starfield(let s):
                try s.validate()
            case .procedural(let p):
                try p.validate()
            case .solid:
                break // Always valid
            }
        }
        
        // Validate text elements if using legacy system
        if let elements = elements {
            for (index, element) in elements.enumerated() {
                if case .text(let text) = element {
                    guard text.fontSize > 0 else {
                        throw ValidationError.invalidParameter("Text element \(index) has invalid fontSize: \(text.fontSize)")
                    }
                    guard text.fontSize <= 1000 else {
                        throw ValidationError.invalidParameter("Text element \(index) has unreasonably large fontSize: \(text.fontSize)")
                    }
                }
            }
        }
    }
}

// MARK: - SourceDefinition

/// Definition of the source video for compositing.
public struct SourceDefinition: Codable, Sendable {
    /// Path to the source video file.
    public let path: String
    
    /// Optional trim range.
    public let trim: TrimRange?
    
    /// Audio handling mode.
    public let audioTrack: AudioTrackMode
    
    /// Playback speed multiplier.
    public let speed: Float
    
    /// Whether to use frame blending for speed changes.
    public let frameBlending: Bool
    
    /// Input color space (e.g., "rec709", "log", "slog3").
    public let colorSpace: String?
    
    public init(
        path: String,
        trim: TrimRange? = nil,
        audioTrack: AudioTrackMode = .keep,
        speed: Float = 1.0,
        frameBlending: Bool = false,
        colorSpace: String? = nil
    ) {
        self.path = path
        self.trim = trim
        self.audioTrack = audioTrack
        self.speed = speed
        self.frameBlending = frameBlending
        self.colorSpace = colorSpace
    }
}

/// Trim range for source video.
public struct TrimRange: Codable, Sendable {
    /// Start time in seconds.
    public let inPoint: Double
    
    /// End time in seconds.
    public let outPoint: Double
    
    /// Duration of the trim range.
    public var duration: Double {
        outPoint - inPoint
    }
    
    public init(inPoint: Double, outPoint: Double) {
        self.inPoint = inPoint
        self.outPoint = outPoint
    }
    
    public init(`in`: Double, out: Double) {
        self.inPoint = `in`
        self.outPoint = out
    }
    
    // JSON encoding with "in"/"out" keys
    enum CodingKeys: String, CodingKey {
        case inPoint = "in"
        case outPoint = "out"
    }
}

/// Audio track handling modes.
public enum AudioTrackMode: String, Codable, Sendable {
    case keep       // Keep original audio
    case mute       // Remove audio
    case replace    // Replace with different audio (future)
}

/// Compositing settings for depth-aware text placement
public struct CompositingDefinition: Codable, Sendable {
    /// Compositing mode for text
    public let mode: String  // "behindSubject", "inFrontOfAll", "depthSorted", "parallax"
    
    /// Depth threshold for occlusion (0=near, 1=far)
    public let depthThreshold: Float
    
    /// Edge softness for depth blending
    public let edgeSoftness: Float
    
    /// Enable AI-based depth estimation
    public let enableDepthEstimation: Bool
    
    /// Enable AI-based smart text placement
    public let enableSmartPlacement: Bool
    
    public init(
        mode: String = "behindSubject",
        depthThreshold: Float = 0.5,
        edgeSoftness: Float = 0.05,
        enableDepthEstimation: Bool = true,
        enableSmartPlacement: Bool = false
    ) {
        self.mode = mode
        self.depthThreshold = depthThreshold
        self.edgeSoftness = edgeSoftness
        self.enableDepthEstimation = enableDepthEstimation
        self.enableSmartPlacement = enableSmartPlacement
    }
    
    /// Convert mode string to CompositeMode enum
    public var compositeMode: CompositeMode {
        switch mode.lowercased() {
        case "behindsubject": return .behindSubject
        case "infrontofall": return .inFrontOfAll
        case "depthsorted": return .depthSorted
        case "parallax": return .parallax
        default: return .behindSubject
        }
    }
}

public struct ManifestMetadata: Codable, Sendable {
    public let duration: Double
    public let fps: Double
    public let resolution: SIMD2<Int>
    public let quality: String? // "realtime", "cinema", "lab"
    
    public init(duration: Double = 10.0, fps: Double = 60.0, resolution: SIMD2<Int> = SIMD2(1920, 1080), quality: String? = "realtime") {
        self.duration = duration
        self.fps = fps
        self.resolution = resolution
        self.quality = quality
    }
    
    enum CodingKeys: String, CodingKey {
        case duration, fps, resolution, quality
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 10.0
        fps = try container.decode(Double.self, forKey: .fps)
        resolution = try container.decode(SIMD2<Int>.self, forKey: .resolution)
        quality = try container.decodeIfPresent(String.self, forKey: .quality)
    }
}

public struct SceneDefinition: Codable, Sendable {
    public let background: String // Hex color or "transparent" (legacy)
    public let ambientLight: Float
    
    /// New procedural background system (optional, overrides background if present)
    public let proceduralBackground: BackgroundDefinition?
    
    public init(background: String = "#000000", ambientLight: Float = 1.0, proceduralBackground: BackgroundDefinition? = nil) {
        self.background = background
        self.ambientLight = ambientLight
        self.proceduralBackground = proceduralBackground
    }
    
    // Custom decoding for backward compatibility
    enum CodingKeys: String, CodingKey {
        case background
        case ambientLight
        case proceduralBackground
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        background = try container.decode(String.self, forKey: .background)
        ambientLight = try container.decodeIfPresent(Float.self, forKey: .ambientLight) ?? 1.0
        proceduralBackground = try container.decodeIfPresent(BackgroundDefinition.self, forKey: .proceduralBackground)
    }
}

public struct CameraDefinition: Codable, Sendable {
    // Base camera values (used if no keyframes or for initial state)
    public let fov: Float
    public let position: SIMD3<Float>
    public let target: SIMD3<Float>
    
    // Optional keyframes for camera animation
    public let keyframes: [CameraKeyframe]?
    
    public init(fov: Float = 60.0, position: SIMD3<Float> = SIMD3(0, 0, 5), target: SIMD3<Float> = SIMD3(0, 0, 0), keyframes: [CameraKeyframe]? = nil) {
        self.fov = fov
        self.position = position
        self.target = target
        self.keyframes = keyframes
    }
    
    /// Interpolates camera properties at a given time using keyframes
    public func interpolate(at time: Float) -> (fov: Float, position: SIMD3<Float>, target: SIMD3<Float>) {
        guard let keyframes = keyframes, keyframes.count > 0 else {
            // No keyframes, return base values
            return (fov, position, target)
        }
        
        // Sort keyframes by time (should already be sorted, but just in case)
        let sortedKeyframes = keyframes.sorted { $0.time < $1.time }
        
        // Find the two keyframes we're between
        var prevKeyframe: CameraKeyframe?
        var nextKeyframe: CameraKeyframe?
        
        for kf in sortedKeyframes {
            if kf.time <= time {
                prevKeyframe = kf
            } else {
                nextKeyframe = kf
                break
            }
        }
        
        // If before first keyframe, use first keyframe values
        guard let prev = prevKeyframe else {
            let first = sortedKeyframes[0]
            return (
                first.fov ?? fov,
                first.position ?? position,
                first.target ?? target
            )
        }
        
        // If after last keyframe (or at last keyframe), use last keyframe values
        guard let next = nextKeyframe else {
            return (
                prev.fov ?? fov,
                prev.position ?? position,
                prev.target ?? target
            )
        }
        
        // Interpolate between prev and next
        let t = (time - prev.time) / (next.time - prev.time)
        let easedT = applyEasing(t: t, easing: next.easing ?? .linear)
        
        let interpolatedFov = lerp(
            prev.fov ?? fov,
            next.fov ?? fov,
            easedT
        )
        
        let interpolatedPosition = lerp3(
            prev.position ?? position,
            next.position ?? position,
            easedT
        )
        
        let interpolatedTarget = lerp3(
            prev.target ?? target,
            next.target ?? target,
            easedT
        )
        
        return (interpolatedFov, interpolatedPosition, interpolatedTarget)
    }
    
    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a + (b - a) * t
    }
    
    private func lerp3(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        return a + (b - a) * t
    }
    
    private func applyEasing(t: Float, easing: CameraEasing) -> Float {
        switch easing {
        case .linear:
            return t
        case .easeIn:
            return t * t
        case .easeOut:
            return 1 - (1 - t) * (1 - t)
        case .easeInOut:
            return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        }
    }
}

/// A keyframe for camera animation
public struct CameraKeyframe: Codable, Sendable {
    public let time: Float
    public let fov: Float?
    public let position: SIMD3<Float>?
    public let target: SIMD3<Float>?
    public let easing: CameraEasing?
    
    public init(time: Float, fov: Float? = nil, position: SIMD3<Float>? = nil, target: SIMD3<Float>? = nil, easing: CameraEasing? = nil) {
        self.time = time
        self.fov = fov
        self.position = position
        self.target = target
        self.easing = easing
    }
}

/// Easing functions for camera interpolation
public enum CameraEasing: String, Codable, Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
}

public struct PostProcessDefinition: Codable, Sendable {
    public let bloom: BloomSettings?
    public let toneMapping: ToneMapSettings?
    
    public struct BloomSettings: Codable, Sendable {
        public let intensity: Float
        public let threshold: Float
        
        public init(intensity: Float = 1.0, threshold: Float = 0.8) {
            self.intensity = intensity
            self.threshold = threshold
        }
    }
    
    public struct ToneMapSettings: Codable, Sendable {
        public let mode: String // "aces", "reinhard", "none"
        public let exposure: Float
        
        public init(mode: String = "aces", exposure: Float = 1.0) {
            self.mode = mode
            self.exposure = exposure
        }
    }
    
    public init(bloom: BloomSettings? = nil, toneMapping: ToneMapSettings? = nil) {
        self.bloom = bloom
        self.toneMapping = toneMapping
    }
}

public enum ManifestElement: Codable, Sendable {
    case text(TextElement)
    case model(ModelElement)
    // Future: particles, etc.
    
    enum CodingKeys: String, CodingKey {
        case type
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "text":
            self = .text(try TextElement(from: decoder))
        case "model":
            self = .model(try ModelElement(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown element type: \(type)")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let element):
            try container.encode("text", forKey: .type)
            try element.encode(to: encoder)
        case .model(let element):
            try container.encode("model", forKey: .type)
            try element.encode(to: encoder)
        }
    }
}

public struct TextElement: Codable, Sendable {
    public let content: String
    public let position: SIMD3<Float>
    public let fontSize: Float
    public let fontName: String
    public let color: SIMD4<Float>
    
    // Positioning System
    public let anchor: TextAnchor       // Where on the text box the position refers to
    public let alignment: TextAlignment // How text lines align within the box
    public let positionMode: PositionMode // Absolute pixels vs normalized (0-1)
    
    // Style
    public let outlineColor: SIMD4<Float>
    public let outlineWidth: Float
    public let shadowColor: SIMD4<Float>
    public let shadowOffset: SIMD2<Float>
    public let shadowBlur: Float
    
    // Depth (for 3D occlusion)
    public let depth: Float
    
    // 3D Transform
    public let rotation: SIMD3<Float>?
    public let scale: SIMD3<Float>?
    
    // Animation
    public let animation: TextAnimationConfig?
    
    // Timing (when element appears/disappears)
    public var startTime: Float  // When element becomes active (seconds)
    public let duration: Float   // How long element is active (0 = infinite)
    
    // AI-Powered Placement
    public let autoPlace: Bool      // Let AI find optimal position
    public let behindSubject: Bool  // Composite behind detected subjects
    public let depthValue: Float    // Explicit depth for compositing (0=near, 1=far)
    
    // Custom decoding for backward compatibility with old manifests
    enum CodingKeys: String, CodingKey {
        case content, position, fontSize, fontName, color
        case anchor, alignment, positionMode
        case outlineColor, outlineWidth, shadowColor, shadowOffset, shadowBlur
        case depth, rotation, scale, animation, startTime, duration
        case autoPlace, behindSubject, depthValue
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Required fields
        content = try container.decode(String.self, forKey: .content)
        position = try container.decode(SIMD3<Float>.self, forKey: .position)
        fontSize = try container.decode(Float.self, forKey: .fontSize)
        fontName = try container.decode(String.self, forKey: .fontName)
        color = try container.decode(SIMD4<Float>.self, forKey: .color)
        
        // Optional fields with defaults (for backward compatibility)
        anchor = try container.decodeIfPresent(TextAnchor.self, forKey: .anchor) ?? .topLeft
        alignment = try container.decodeIfPresent(TextAlignment.self, forKey: .alignment) ?? .left
        positionMode = try container.decodeIfPresent(PositionMode.self, forKey: .positionMode) ?? .absolute
        outlineColor = try container.decodeIfPresent(SIMD4<Float>.self, forKey: .outlineColor) ?? SIMD4(0, 0, 0, 0)
        outlineWidth = try container.decodeIfPresent(Float.self, forKey: .outlineWidth) ?? 0.0
        shadowColor = try container.decodeIfPresent(SIMD4<Float>.self, forKey: .shadowColor) ?? SIMD4(0, 0, 0, 0)
        shadowOffset = try container.decodeIfPresent(SIMD2<Float>.self, forKey: .shadowOffset) ?? SIMD2(0, 0)
        shadowBlur = try container.decodeIfPresent(Float.self, forKey: .shadowBlur) ?? 0.0
        depth = try container.decodeIfPresent(Float.self, forKey: .depth) ?? 0.0
        rotation = try container.decodeIfPresent(SIMD3<Float>.self, forKey: .rotation)
        scale = try container.decodeIfPresent(SIMD3<Float>.self, forKey: .scale)
        animation = try container.decodeIfPresent(TextAnimationConfig.self, forKey: .animation)
        startTime = try container.decodeIfPresent(Float.self, forKey: .startTime) ?? 0
        duration = try container.decodeIfPresent(Float.self, forKey: .duration) ?? 0
        autoPlace = try container.decodeIfPresent(Bool.self, forKey: .autoPlace) ?? false
        behindSubject = try container.decodeIfPresent(Bool.self, forKey: .behindSubject) ?? false
        depthValue = try container.decodeIfPresent(Float.self, forKey: .depthValue) ?? 0.8
    }
    
    public init(
        content: String,
        position: SIMD3<Float>,
        fontSize: Float = 64.0,
        fontName: String = "Helvetica",
        color: SIMD4<Float> = SIMD4(1, 1, 1, 1),
        anchor: TextAnchor = .topLeft,
        alignment: TextAlignment = .left,
        positionMode: PositionMode = .absolute,
        outlineColor: SIMD4<Float> = SIMD4(0, 0, 0, 0),
        outlineWidth: Float = 0.0,
        shadowColor: SIMD4<Float> = SIMD4(0, 0, 0, 0),
        shadowOffset: SIMD2<Float> = SIMD2(0, 0),
        shadowBlur: Float = 0.0,
        depth: Float = 0.0,
        rotation: SIMD3<Float>? = nil,
        scale: SIMD3<Float>? = nil,
        animation: TextAnimationConfig? = nil,
        startTime: Float = 0,
        duration: Float = 0,
        autoPlace: Bool = false,
        behindSubject: Bool = false,
        depthValue: Float = 0.8
    ) {
        self.content = content
        self.position = position
        self.fontSize = fontSize
        self.fontName = fontName
        self.color = color
        self.anchor = anchor
        self.alignment = alignment
        self.positionMode = positionMode
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
        self.shadowColor = shadowColor
        self.shadowOffset = shadowOffset
        self.shadowBlur = shadowBlur
        self.depth = depth
        self.rotation = rotation
        self.scale = scale
        self.animation = animation
        self.startTime = startTime
        self.duration = duration
        self.autoPlace = autoPlace
        self.behindSubject = behindSubject
        self.depthValue = depthValue
    }
}

/// Where on the text bounding box the position coordinate refers to
public enum TextAnchor: String, Codable, Sendable {
    case topLeft, topCenter, topRight
    case centerLeft, center, centerRight
    case bottomLeft, bottomCenter, bottomRight
}

/// How text lines align within a multi-line text block
public enum TextAlignment: String, Codable, Sendable {
    case left, center, right
}

/// How position coordinates are interpreted
public enum PositionMode: String, Codable, Sendable {
    case absolute   // Raw pixel coordinates
    case normalized // 0.0-1.0 relative to viewport (resolution-independent)
}

public struct ModelElement: Codable, Sendable {
    public let path: String
    public let position: SIMD3<Float>
    public let scale: SIMD3<Float>
    public let material: MaterialDefinition?
    
    // Timing (when element appears/disappears)
    public var startTime: Float  // When element becomes active (seconds)
    public let duration: Float   // How long element is active (0 = infinite)
    
    public init(
        path: String,
        position: SIMD3<Float>,
        scale: SIMD3<Float> = SIMD3(1, 1, 1),
        material: MaterialDefinition? = nil,
        startTime: Float = 0,
        duration: Float = 0
    ) {
        self.path = path
        self.position = position
        self.scale = scale
        self.material = material
        self.startTime = startTime
        self.duration = duration
    }
}

public struct MaterialDefinition: Codable, Sendable {
    public let baseColor: String? // Hex
    public let roughness: Float?
    public let metallic: Float?
    public let emissive: String? // Hex
    
    public init(baseColor: String? = nil, roughness: Float? = nil, metallic: Float? = nil, emissive: String? = nil) {
        self.baseColor = baseColor
        self.roughness = roughness
        self.metallic = metallic
        self.emissive = emissive
    }
}
