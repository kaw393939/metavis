// TimelineModel.swift
// MetaVisRender
//
// Created for Sprint 11: Timeline Editing
// Core timeline data model with tracks, clips, and transitions

import Foundation
import CoreMedia

// MARK: - Timeline ID Types

/// Unique identifier for a clip
public struct ClipID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init() {
        self.rawValue = UUID().uuidString
    }
    
    public var description: String { rawValue }
}

/// Unique identifier for a track
public struct TrackID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init() {
        self.rawValue = UUID().uuidString
    }
    
    public var description: String { rawValue }
}

// MARK: - TimelineModel

/// Main timeline container holding all tracks, clips, and transitions.
///
/// A timeline represents a complete editing project with:
/// - One or more video tracks (for multi-layer compositing)
/// - Audio tracks (future)
/// - Graphics tracks (for overlays)
/// - Transitions between clips
/// - Source registry mapping source IDs to file paths
///
/// ## Example
/// ```swift
/// var timeline = TimelineModel(
///     fps: 30,
///     resolution: SIMD2(1920, 1080)
/// )
/// timeline.addVideoTrack()
/// ```
public struct TimelineModel: Codable, Sendable {
    
    // MARK: - Properties
    
    /// Timeline identifier
    public let id: String
    
    /// Frames per second
    public var fps: Double
    
    /// Output resolution
    public var resolution: SIMD2<Int>
    
    /// Video tracks (bottom to top in render order)
    public var videoTracks: [VideoTrack]
    
    /// Graphics tracks for overlays (text, models, effects)
    public var graphicsTracks: [GraphicsTrack]
    
    /// Audio tracks for multi-track audio timeline
    public var audioTracks: [AudioTrack]
    
    /// Transitions between clips
    public var transitions: [TransitionDefinition]
    
    /// Audio transitions (crossfades, J-cuts, L-cuts)
    public var audioTransitions: [AudioTransition]
    
    /// Source file registry (sourceID → path)
    public var sources: [String: SourceInfo]
    
    /// Markers for navigation and reference
    public var markers: [TimelineMarker]
    
    /// Quality mode for rendering
    public var quality: QualityMode
    
    /// Scene settings (background, lighting)
    public var scene: SceneDefinition?
    
    /// Camera settings (position, FOV, animation)
    public var camera: CameraDefinition?
    
    /// Compositing settings for AI features
    public var compositing: CompositingDefinition?
    
    /// Cinematic look settings (post-processing effects)
    public var look: CinematicLook?
    
    /// Explicit duration override (for virtual content without video clips)
    /// When set, this duration is used instead of computing from clip positions.
    public var explicitDuration: Double?
    
    // MARK: - Computed Properties
    
    /// Total duration of the timeline (based on clip positions or explicit duration)
    public var duration: Double {
        // Use explicit duration if set (for virtual content)
        if let explicit = explicitDuration {
            return explicit
        }
        
        // Otherwise compute from video clips
        var maxEnd: Double = 0
        for track in videoTracks {
            for clip in track.clips {
                let clipEnd = clip.timelineIn + clip.duration
                maxEnd = max(maxEnd, clipEnd)
            }
        }
        return maxEnd
    }
    
    /// Total duration as CMTime
    public var durationTime: CMTime {
        CMTime(seconds: duration, preferredTimescale: CMTimeScale(fps * 1000))
    }
    
    /// Total frame count
    public var frameCount: Int {
        Int(duration * fps)
    }
    
    /// Converts frame number to time in seconds
    public func timeAtFrame(_ frame: Int) -> Double {
        Double(frame) / fps
    }
    
    /// Primary video track (first track)
    public var primaryVideoTrack: VideoTrack? {
        videoTracks.first
    }
    
    /// Check if timeline has virtual content (procedural backgrounds or graphics)
    /// Virtual content can be rendered without video tracks.
    public var hasVirtualContent: Bool {
        // Has procedural background in scene
        if scene?.proceduralBackground != nil {
            return true
        }
        // Has graphics tracks
        if !graphicsTracks.isEmpty {
            return true
        }
        return false
    }
    
    // MARK: - Initialization
    
    /// Creates a new timeline with the specified settings.
    public init(
        id: String = UUID().uuidString,
        fps: Double = 30,
        resolution: SIMD2<Int> = SIMD2(1920, 1080),
        videoTracks: [VideoTrack] = [],
        graphicsTracks: [GraphicsTrack] = [],
        audioTracks: [AudioTrack] = [],
        transitions: [TransitionDefinition] = [],
        audioTransitions: [AudioTransition] = [],
        sources: [String: SourceInfo] = [:],
        markers: [TimelineMarker] = [],
        quality: QualityMode = .standard,
        scene: SceneDefinition? = nil,
        camera: CameraDefinition? = nil,
        compositing: CompositingDefinition? = nil,
        look: CinematicLook? = nil,
        explicitDuration: Double? = nil
    ) {
        self.id = id
        self.fps = fps
        self.resolution = resolution
        self.videoTracks = videoTracks
        self.graphicsTracks = graphicsTracks
        self.audioTracks = audioTracks
        self.transitions = transitions
        self.audioTransitions = audioTransitions
        self.sources = sources
        self.markers = markers
        self.quality = quality
        self.scene = scene
        self.camera = camera
        self.compositing = compositing
        self.look = look
        self.explicitDuration = explicitDuration
    }
    
    /// Creates a timeline with a single video track
    public static func singleTrack(
        fps: Double = 30,
        resolution: SIMD2<Int> = SIMD2(1920, 1080)
    ) -> TimelineModel {
        var timeline = TimelineModel(fps: fps, resolution: resolution)
        timeline.videoTracks.append(VideoTrack(id: TrackID("video_main")))
        return timeline
    }
    
    // MARK: - Source Management
    
    /// Registers a source file with an ID.
    public mutating func registerSource(
        id: String, 
        path: String, 
        duration: Double? = nil,
        resolution: SIMD2<Int>? = nil,
        fps: Double? = nil,
        codec: String? = nil,
        colorSpace: String? = nil
    ) {
        sources[id] = SourceInfo(
            path: path, 
            duration: duration,
            resolution: resolution,
            fps: fps,
            codec: codec,
            colorSpace: colorSpace
        )
    }
    
    /// Resolves a source ID to its file path.
    public func sourcePath(for sourceID: String) -> String? {
        sources[sourceID]?.path
    }
    
    // MARK: - Track Management
    
    /// Adds a new video track.
    @discardableResult
    public mutating func addVideoTrack(id: TrackID? = nil, name: String? = nil) -> TrackID {
        let trackID = id ?? TrackID()
        let track = VideoTrack(
            id: trackID,
            name: name ?? "Video \(videoTracks.count + 1)"
        )
        videoTracks.append(track)
        return trackID
    }
    
    /// Gets a video track by ID.
    public func videoTrack(id: TrackID) -> VideoTrack? {
        videoTracks.first { $0.id == id }
    }
    
    // MARK: - Clip Lookup
    
    /// Finds a clip by ID across all tracks.
    public func clip(id: ClipID) -> ClipDefinition? {
        for track in videoTracks {
            if let clip = track.clips.first(where: { $0.id == id }) {
                return clip
            }
        }
        return nil
    }
    
    /// Finds all clips active at a given timeline time.
    public func clipsAt(time: Double) -> [ClipDefinition] {
        var result: [ClipDefinition] = []
        for track in videoTracks {
            for clip in track.clips {
                if clip.containsTimelineTime(time) {
                    result.append(clip)
                }
            }
        }
        return result
    }
    
    /// Finds the transition between two clips (if any).
    public func transition(from fromClip: ClipID, to toClip: ClipID) -> TransitionDefinition? {
        transitions.first { $0.fromClip == fromClip && $0.toClip == toClip }
    }
    
    /// Finds the transition active at a given time on a track.
    public func transitionAt(time: Double, track: TrackID) -> (TransitionDefinition, Double)? {
        guard let videoTrack = self.videoTrack(id: track) else { return nil }
        
        for transition in transitions {
            // Find the from and to clips
            guard clip(id: transition.fromClip) != nil,
                  let toClip = clip(id: transition.toClip) else {
                continue
            }
            
            // Check if clips are on this track
            guard videoTrack.clips.contains(where: { $0.id == transition.fromClip }),
                  videoTrack.clips.contains(where: { $0.id == transition.toClip }) else {
                continue
            }
            
            // Calculate transition time range
            let transitionStart = toClip.timelineIn
            let transitionEnd = transitionStart + transition.duration
            
            if time >= transitionStart && time < transitionEnd {
                let progress = (time - transitionStart) / transition.duration
                return (transition, progress)
            }
        }
        
        return nil
    }
    
    // MARK: - Validation
    
    // Validation logic moved to TimelineModel+Validation.swift
}

// MARK: - VideoTrack

/// A track containing video clips.
public struct VideoTrack: Codable, Sendable, Identifiable {
    
    /// Track identifier
    public let id: TrackID
    
    /// Display name
    public var name: String
    
    /// Clips on this track (sorted by timelineIn)
    public var clips: [ClipDefinition]
    
    /// Whether the track is muted
    public var isMuted: Bool
    
    /// Whether the track is locked (prevents editing)
    public var isLocked: Bool
    
    /// Track opacity (for compositing multiple tracks)
    public var opacity: Float
    
    /// Track blend mode
    public var blendMode: BlendMode
    
    public init(
        id: TrackID = TrackID(),
        name: String = "Video",
        clips: [ClipDefinition] = [],
        isMuted: Bool = false,
        isLocked: Bool = false,
        opacity: Float = 1.0,
        blendMode: BlendMode = .normal
    ) {
        self.id = id
        self.name = name
        self.clips = clips
        self.isMuted = isMuted
        self.isLocked = isLocked
        self.opacity = opacity
        self.blendMode = blendMode
    }
    
    /// Duration of this track (last clip end time)
    public var duration: Double {
        clips.map { $0.timelineIn + $0.duration }.max() ?? 0
    }
    
    /// Finds the clip at a given timeline time.
    public func clipAt(time: Double) -> ClipDefinition? {
        clips.first { $0.containsTimelineTime(time) }
    }
    
    /// Finds clips in a time range.
    public func clipsIn(range: ClosedRange<Double>) -> [ClipDefinition] {
        clips.filter { clip in
            let clipEnd = clip.timelineIn + clip.duration
            return clip.timelineIn < range.upperBound && clipEnd > range.lowerBound
        }
    }
}

// MARK: - SourceInfo

/// Information about a registered source file.
public struct SourceInfo: Codable, Sendable {
    /// Path to the source file
    public let path: String
    
    /// Duration of the source (if known)
    public var duration: Double?
    
    /// Resolution of the source (if known)
    public var resolution: SIMD2<Int>?
    
    /// Frame rate of the source (if known)
    public var fps: Double?
    
    /// Codec of the source (if known)
    public var codec: String?
    
    /// Color space of the source (e.g. "slog3", "rec709")
    public var colorSpace: String?
    
    public init(
        path: String,
        duration: Double? = nil,
        resolution: SIMD2<Int>? = nil,
        fps: Double? = nil,
        codec: String? = nil,
        colorSpace: String? = nil
    ) {
        self.path = path
        self.duration = duration
        self.resolution = resolution
        self.fps = fps
        self.codec = codec
        self.colorSpace = colorSpace
    }
}

// MARK: - TimelineMarker

/// A marker on the timeline for navigation and reference.
public struct TimelineMarker: Codable, Sendable {
    /// Marker time on the timeline
    public let time: Double
    
    /// Marker label
    public let label: String
    
    /// Marker color (hex)
    public let color: String
    
    /// Marker type
    public let type: MarkerType
    
    public enum MarkerType: String, Codable, Sendable {
        case chapter
        case comment
        case todo
        case sync
    }
    
    public init(time: Double, label: String, color: String = "#FFFF00", type: MarkerType = .comment) {
        self.time = time
        self.label = label
        self.color = color
        self.type = type
    }
}

// MARK: - QualityMode

/// Rendering quality presets.
public enum QualityMode: String, Codable, Sendable {
    case preview   // Fast preview, lower quality
    case draft     // Medium quality, reasonable speed
    case standard  // Good quality, balanced
    case cinema    // Highest quality, slowest
    
    /// Decoder pool size for this quality mode
    public var decoderPoolSize: Int {
        switch self {
        case .preview: return 2
        case .draft: return 2
        case .standard: return 3
        case .cinema: return 4
        }
    }
    
    /// Transition frame rate for this quality mode
    public var transitionFPS: Double {
        switch self {
        case .preview: return 15
        case .draft: return 15
        case .standard: return 30
        case .cinema: return 60
        }
    }
}

// MARK: - BlendMode

/// Blend modes for track compositing.
public enum BlendMode: String, Codable, Sendable {
    case normal
    case add
    case multiply
    case screen
    case overlay
    case darken
    case lighten
    case colorBurn
    case colorDodge
    case softLight
    case hardLight
    case difference
    case exclusion
    case hue
    case saturation
    case color
    case luminosity
}

// MARK: - TimelineValidationError

// Moved to TimelineModel+Validation.swift

// MARK: - GraphicsTrack

/// A track containing graphics elements (text, models, effects).
///
/// Graphics tracks are composited on top of video tracks and support:
/// - Text overlays with animation
/// - 3D models
/// - Camera control
/// - AI-powered placement and depth compositing
public struct GraphicsTrack: Codable, Sendable, Identifiable {
    
    // MARK: - Properties
    
    /// Unique track identifier
    public let id: TrackID
    
    /// Track name
    public var name: String
    
    /// Graphics elements on this track
    public var elements: [GraphicsElement]
    
    /// Whether the track is muted (hidden)
    public var isMuted: Bool
    
    /// Whether the track is locked (prevents editing)
    public var isLocked: Bool
    
    /// Track opacity (for compositing)
    public var opacity: Float
    
    /// Track blend mode
    public var blendMode: BlendMode
    
    public init(
        id: TrackID = TrackID(),
        name: String = "Graphics",
        elements: [GraphicsElement] = [],
        isMuted: Bool = false,
        isLocked: Bool = false,
        opacity: Float = 1.0,
        blendMode: BlendMode = .normal
    ) {
        self.id = id
        self.name = name
        self.elements = elements
        self.isMuted = isMuted
        self.isLocked = isLocked
        self.opacity = opacity
        self.blendMode = blendMode
    }
    
    /// Duration of this track (last element end time)
    public var duration: Double {
        elements.compactMap { element -> Double? in
            switch element {
            case .text(let text):
                return text.duration > 0 ? Double(text.startTime + text.duration) : nil
            case .model(let model):
                return model.duration > 0 ? Double(model.startTime + model.duration) : nil
            case .solid(let solid):
                return solid.duration > 0 ? Double(solid.startTime + solid.duration) : nil
            case .adjustment(let adjustment):
                return adjustment.duration > 0 ? Double(adjustment.startTime + adjustment.duration) : nil
            }
        }.max() ?? 0
    }
}

// MARK: - GraphicsElement

/// A graphics element that can be placed on a graphics track.
public enum GraphicsElement: Codable, Sendable {
    case text(TextElement)
    case model(ModelElement)
    case solid(TimelineSolidLayer)
    case adjustment(TimelineAdjustmentLayer)
    
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
        case "solid":
            self = .solid(try TimelineSolidLayer(from: decoder))
        case "adjustment":
            self = .adjustment(try TimelineAdjustmentLayer(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown graphics element type: \(type)"
            )
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
        case .solid(let element):
            try container.encode("solid", forKey: .type)
            try element.encode(to: encoder)
        case .adjustment(let element):
            try container.encode("adjustment", forKey: .type)
            try element.encode(to: encoder)
        }
    }
}

// MARK: - CinematicLook

/// Cinematic look configuration for post-processing effects.
///
/// The look is applied after all video compositing, creating a unified
/// visual treatment across all clips and transitions.
///
/// ## Example
/// ```json
/// {
///   "look": {
///     "name": "Film Noir",
///     "halation": { "intensity": 0.3, "threshold": 0.9, "tint": [1.0, 0.9, 0.8] },
///     "bloom": { "intensity": 0.5, "threshold": 0.8, "radius": 1.2 },
///     "filmGrain": { "intensity": 0.15, "size": 1.0, "shadowBoost": 1.5 },
///     "vignette": { "intensity": 0.4, "smoothness": 0.6, "roundness": 0.8 },
///     "colorGrading": { "lut": "teal_orange.cube", "intensity": 0.7 },
///     "lens": { "distortion": 0.05, "chromaticAberration": 0.02 }
///   }
/// }
/// ```
public struct CinematicLook: Codable, Sendable {
    
    /// Optional name for the look preset
    public var name: String?
    
    /// Halation (warm light bleed around highlights)
    public var halation: HalationSettings?
    
    /// Bloom (soft glow around bright areas)
    public var bloom: BloomSettings?
    
    /// Film grain overlay
    public var filmGrain: FilmGrainSettings?
    
    /// Vignette (darkening at edges)
    public var vignette: VignetteSettings?
    
    /// Lens effects (distortion, chromatic aberration)
    public var lens: LensSettings?
    
    /// Color grading via LUT
    public var colorGrading: ColorGradingSettings?
    
    /// Anamorphic streaks (horizontal flares)
    public var anamorphic: AnamorphicSettings?
    
    /// Tone mapping configuration
    public var toneMapping: ToneMappingSettings?
    
    /// Light leaks (colored light bleeds from edges)
    public var lightLeaks: LightLeakSettings?
    
    /// Spectral dispersion (prismatic light splitting)
    public var spectralDispersion: SpectralDispersionSettings?
    
    /// Diffusion filter (soft glow / pro-mist)
    public var diffusion: DiffusionSettings?
    
    /// AI-powered face enhancement
    public var faceEnhance: FaceEnhanceSettings?
    
    /// Person segmentation-based background blur
    public var backgroundBlur: BackgroundBlurSettings?
    
    /// Whether to apply the look (master enable)
    public var enabled: Bool
    
    public init(
        name: String? = nil,
        halation: HalationSettings? = nil,
        bloom: BloomSettings? = nil,
        filmGrain: FilmGrainSettings? = nil,
        vignette: VignetteSettings? = nil,
        lens: LensSettings? = nil,
        colorGrading: ColorGradingSettings? = nil,
        anamorphic: AnamorphicSettings? = nil,
        toneMapping: ToneMappingSettings? = nil,
        lightLeaks: LightLeakSettings? = nil,
        spectralDispersion: SpectralDispersionSettings? = nil,
        diffusion: DiffusionSettings? = nil,
        faceEnhance: FaceEnhanceSettings? = nil,
        backgroundBlur: BackgroundBlurSettings? = nil,
        enabled: Bool = true
    ) {
        self.name = name
        self.halation = halation
        self.bloom = bloom
        self.filmGrain = filmGrain
        self.vignette = vignette
        self.lens = lens
        self.colorGrading = colorGrading
        self.anamorphic = anamorphic
        self.toneMapping = toneMapping
        self.lightLeaks = lightLeaks
        self.spectralDispersion = spectralDispersion
        self.diffusion = diffusion
        self.faceEnhance = faceEnhance
        self.backgroundBlur = backgroundBlur
        self.enabled = enabled
    }
    
    // MARK: - Presets
    
    /// No effects (pass-through)
    public static let none = CinematicLook(enabled: false)
    
    /// Subtle cinematic enhancement
    public static let subtle = CinematicLook(
        name: "Subtle",
        bloom: BloomSettings(intensity: 0.2, threshold: 0.9),
        filmGrain: FilmGrainSettings(intensity: 0.05),
        vignette: VignetteSettings(intensity: 0.2)
    )
    
    /// Classic film look
    public static let classicFilm = CinematicLook(
        name: "Classic Film",
        halation: HalationSettings(intensity: 0.25, threshold: 0.85),
        bloom: BloomSettings(intensity: 0.4, threshold: 0.8),
        filmGrain: FilmGrainSettings(intensity: 0.15, size: 1.2, shadowBoost: 1.3),
        vignette: VignetteSettings(intensity: 0.35, smoothness: 0.5),
        lens: LensSettings(chromaticAberration: 0.015)
    )
    
    /// Modern blockbuster style
    public static let blockbuster = CinematicLook(
        name: "Blockbuster",
        bloom: BloomSettings(intensity: 0.6, threshold: 0.75, radius: 1.5),
        vignette: VignetteSettings(intensity: 0.25, roundness: 1.0),
        anamorphic: AnamorphicSettings(intensity: 0.4, threshold: 0.8),
        toneMapping: ToneMappingSettings(operator: .aces, exposure: 0.2)
    )
    
    /// Documentary / natural look
    public static let documentary = CinematicLook(
        name: "Documentary",
        filmGrain: FilmGrainSettings(intensity: 0.08),
        vignette: VignetteSettings(intensity: 0.15),
        toneMapping: ToneMappingSettings(operator: .aces, exposure: 0.0)
    )
    
    /// Dream sequence / ethereal
    public static let dreamlike = CinematicLook(
        name: "Dreamlike",
        halation: HalationSettings(intensity: 0.5, threshold: 0.7, tint: SIMD3(1.0, 0.95, 0.9)),
        bloom: BloomSettings(intensity: 0.8, threshold: 0.6, radius: 2.0),
        vignette: VignetteSettings(intensity: 0.4, smoothness: 0.7),
        diffusion: DiffusionSettings(intensity: 0.4, radius: 1.5)
    )
    
    /// Prismatic / spectral look (like the crystal prism image)
    public static let prismatic = CinematicLook(
        name: "Prismatic",
        bloom: BloomSettings(intensity: 0.4, threshold: 0.8, radius: 1.2),
        vignette: VignetteSettings(intensity: 0.15),
        toneMapping: ToneMappingSettings(operator: .aces, exposure: 0.1),
        lightLeaks: LightLeakSettings(
            intensity: 0.25,
            color: SIMD3(1.0, 0.6, 0.8),  // Pink/magenta
            position: SIMD2(0.9, 0.5),
            animated: true
        ),
        spectralDispersion: SpectralDispersionSettings(
            intensity: 0.4,
            spread: 15.0,
            samples: 9
        )
    )
    
    /// Interview / talking head - AI-enhanced faces with natural look
    public static let interview = CinematicLook(
        name: "Interview",
        filmGrain: FilmGrainSettings(intensity: 0.05),
        vignette: VignetteSettings(intensity: 0.15, smoothness: 0.6),
        toneMapping: ToneMappingSettings(operator: .aces, exposure: 0.0),
        diffusion: DiffusionSettings(intensity: 0.1, radius: 0.8, threshold: 0.7),
        faceEnhance: .interview
    )
    
    /// Corporate / professional interview - polished look
    public static let corporate = CinematicLook(
        name: "Corporate",
        bloom: BloomSettings(intensity: 0.15, threshold: 0.9),
        vignette: VignetteSettings(intensity: 0.2, smoothness: 0.5),
        toneMapping: ToneMappingSettings(operator: .aces, exposure: 0.05, contrast: 1.05),
        diffusion: DiffusionSettings(intensity: 0.15, radius: 1.0, threshold: 0.6),
        faceEnhance: .polished
    )
    
    /// Beauty / glamour - maximum face enhancement
    public static let beauty = CinematicLook(
        name: "Beauty",
        halation: HalationSettings(intensity: 0.15, threshold: 0.85),
        bloom: BloomSettings(intensity: 0.25, threshold: 0.85, radius: 1.2),
        vignette: VignetteSettings(intensity: 0.25, smoothness: 0.7),
        toneMapping: ToneMappingSettings(operator: .aces, exposure: 0.1),
        diffusion: DiffusionSettings(intensity: 0.25, radius: 1.2, threshold: 0.5),
        faceEnhance: .beauty
    )
}

// MARK: - Halation Settings

/// Halation creates a warm glow around bright areas, simulating
/// light scattering in film emulsion.
public struct HalationSettings: Codable, Sendable {
    /// Effect intensity (0 = off, 1 = full)
    public var intensity: Float
    
    /// Luminance threshold for halation (0-1)
    public var threshold: Float
    
    /// Color tint for the halation (RGB, typically warm)
    public var tint: SIMD3<Float>
    
    /// Blur radius for the halation
    public var radius: Float
    
    /// Apply radial falloff (reduces halation at edges)
    public var radialFalloff: Bool
    
    public init(
        intensity: Float = 0.3,
        threshold: Float = 0.85,
        tint: SIMD3<Float> = SIMD3(1.0, 0.9, 0.8),
        radius: Float = 1.0,
        radialFalloff: Bool = true
    ) {
        self.intensity = intensity
        self.threshold = threshold
        self.tint = tint
        self.radius = radius
        self.radialFalloff = radialFalloff
    }
}

// MARK: - Bloom Settings

/// Bloom creates soft glow around bright areas.
public struct BloomSettings: Codable, Sendable {
    /// Effect intensity (0 = off, 1 = full)
    public var intensity: Float
    
    /// Luminance threshold for bloom (0-1)
    public var threshold: Float
    
    /// Bloom radius (larger = wider glow)
    public var radius: Float
    
    /// Soft knee for threshold (smoother transition)
    public var knee: Float
    
    public init(
        intensity: Float = 0.5,
        threshold: Float = 0.8,
        radius: Float = 1.0,
        knee: Float = 0.5
    ) {
        self.intensity = intensity
        self.threshold = threshold
        self.radius = radius
        self.knee = knee
    }
}

// MARK: - Film Grain Settings

/// Film grain adds organic texture to the image.
public struct FilmGrainSettings: Codable, Sendable {
    /// Grain intensity (0 = off, 1 = heavy)
    public var intensity: Float
    
    /// Grain size (1 = pixel-sized, larger = coarser)
    public var size: Float
    
    /// Boost grain in shadows (1 = normal, higher = more visible in darks)
    public var shadowBoost: Float
    
    /// Animate grain over time
    public var animated: Bool
    
    public init(
        intensity: Float = 0.1,
        size: Float = 1.0,
        shadowBoost: Float = 1.2,
        animated: Bool = true
    ) {
        self.intensity = intensity
        self.size = size
        self.shadowBoost = shadowBoost
        self.animated = animated
    }
}

// MARK: - Vignette Settings

/// Vignette darkens the edges of the frame.
public struct VignetteSettings: Codable, Sendable {
    /// Effect intensity (0 = off, 1 = full)
    public var intensity: Float
    
    /// Falloff smoothness (0 = hard edge, 1 = soft)
    public var smoothness: Float
    
    /// Shape (0 = rectangular, 1 = circular)
    public var roundness: Float
    
    /// Sensor width in mm (for physical accuracy)
    public var sensorWidth: Float
    
    /// Focal length in mm (for physical accuracy)
    public var focalLength: Float
    
    public init(
        intensity: Float = 0.3,
        smoothness: Float = 0.5,
        roundness: Float = 0.8,
        sensorWidth: Float = 36.0,
        focalLength: Float = 50.0
    ) {
        self.intensity = intensity
        self.smoothness = smoothness
        self.roundness = roundness
        self.sensorWidth = sensorWidth
        self.focalLength = focalLength
    }
}

// MARK: - Lens Settings

/// Lens effects including distortion and chromatic aberration.
public struct LensSettings: Codable, Sendable {
    /// Barrel distortion (positive = barrel, negative = pincushion)
    public var distortion: Float
    
    /// Secondary distortion term
    public var distortionK2: Float
    
    /// Chromatic aberration strength
    public var chromaticAberration: Float
    
    public init(
        distortion: Float = 0.0,
        distortionK2: Float = 0.0,
        chromaticAberration: Float = 0.0
    ) {
        self.distortion = distortion
        self.distortionK2 = distortionK2
        self.chromaticAberration = chromaticAberration
    }
}

// MARK: - Color Grading Settings

/// Color grading via 3D LUT.
public struct ColorGradingSettings: Codable, Sendable {
    /// Path to LUT file (.cube format)
    public var lutPath: String?
    
    /// LUT intensity (0 = original, 1 = full LUT)
    public var intensity: Float
    
    /// Inline LUT name (for built-in LUTs)
    public var preset: String?
    
    public init(
        lutPath: String? = nil,
        intensity: Float = 1.0,
        preset: String? = nil
    ) {
        self.lutPath = lutPath
        self.intensity = intensity
        self.preset = preset
    }
}

// MARK: - Anamorphic Settings

/// Anamorphic lens flare streaks.
public struct AnamorphicSettings: Codable, Sendable {
    /// Streak intensity (0 = off, 1 = full)
    public var intensity: Float
    
    /// Luminance threshold for streaks
    public var threshold: Float
    
    /// Streak color tint (RGB)
    public var tint: SIMD3<Float>
    
    /// Streak length multiplier
    public var streakLength: Float
    
    public init(
        intensity: Float = 0.4,
        threshold: Float = 0.85,
        tint: SIMD3<Float> = SIMD3(0.7, 0.85, 1.0),
        streakLength: Float = 1.0
    ) {
        self.intensity = intensity
        self.threshold = threshold
        self.tint = tint
        self.streakLength = streakLength
    }
}

// MARK: - Tone Mapping Settings

/// Tone mapping configuration.
public struct ToneMappingSettings: Codable, Sendable {
    /// Tone mapping operator
    public var `operator`: ToneMapOperator
    
    /// Exposure adjustment (stops)
    public var exposure: Float
    
    /// Saturation adjustment
    public var saturation: Float
    
    /// Contrast adjustment
    public var contrast: Float
    
    public init(
        `operator`: ToneMapOperator = .aces,
        exposure: Float = 0.0,
        saturation: Float = 1.0,
        contrast: Float = 1.0
    ) {
        self.operator = `operator`
        self.exposure = exposure
        self.saturation = saturation
        self.contrast = contrast
    }
}

/// Tone mapping operators
public enum ToneMapOperator: String, Codable, Sendable {
    case aces       // ACES filmic
    case reinhard   // Reinhard
    case linear     // No tone mapping
    case pq         // HDR PQ curve
}

// MARK: - Light Leak Settings

/// Light leaks simulate light bleeding through the camera.
public struct LightLeakSettings: Codable, Sendable {
    /// Effect intensity (0 = off, 1 = full)
    public var intensity: Float
    
    /// Color of the light leak
    public var color: SIMD3<Float>
    
    /// Position (normalized 0-1)
    public var position: SIMD2<Float>
    
    /// Animate the leak over time
    public var animated: Bool
    
    /// Animation speed
    public var speed: Float
    
    public init(
        intensity: Float = 0.3,
        color: SIMD3<Float> = SIMD3(1.0, 0.8, 0.6),
        position: SIMD2<Float> = SIMD2(0.0, 0.5),
        animated: Bool = true,
        speed: Float = 1.0
    ) {
        self.intensity = intensity
        self.color = color
        self.position = position
        self.animated = animated
        self.speed = speed
    }
}

// MARK: - Diffusion Settings

/// Diffusion filter (pro-mist / soft glow).
public struct DiffusionSettings: Codable, Sendable {
    /// Effect intensity (0 = off, 1 = full)
    public var intensity: Float
    
    /// Diffusion radius
    public var radius: Float
    
    /// Threshold for diffusion (affects mostly highlights)
    public var threshold: Float
    
    public init(
        intensity: Float = 0.3,
        radius: Float = 1.0,
        threshold: Float = 0.5
    ) {
        self.intensity = intensity
        self.radius = radius
        self.threshold = threshold
    }
}

// MARK: - Spectral Dispersion Settings

/// Spectral dispersion (prismatic light splitting) like a prism or lens aberration.
/// Operates in Linear ACEScg for physically accurate wavelength separation.
public struct SpectralDispersionSettings: Codable, Sendable {
    /// Effect intensity (0 = off, 1 = full)
    public var intensity: Float
    
    /// How far wavelengths separate (in pixels at 1080p reference)
    public var spread: Float
    
    /// Optical center (normalized 0-1, default 0.5, 0.5)
    public var center: SIMD2<Float>
    
    /// Radial falloff exponent (1 = linear, 2 = quadratic)
    public var falloff: Float
    
    /// Dispersion angle in degrees (0 = radial outward)
    public var angle: Float
    
    /// Number of spectral samples (3 = RGB, higher = smoother rainbow)
    public var samples: Int
    
    public init(
        intensity: Float = 0.3,
        spread: Float = 10.0,
        center: SIMD2<Float> = SIMD2(0.5, 0.5),
        falloff: Float = 1.5,
        angle: Float = 0.0,
        samples: Int = 7
    ) {
        self.intensity = intensity
        self.spread = spread
        self.center = center
        self.falloff = falloff
        self.angle = angle
        self.samples = samples
    }
}

// MARK: - Face Enhance Settings

/// AI-powered face enhancement for interviews and portrait video.
///
/// Uses Apple Vision framework to detect faces and applies targeted
/// enhancements only to face regions, making subjects look polished
/// without affecting the rest of the frame.
///
/// ## Example
/// ```json
/// {
///   "faceEnhance": {
///     "enabled": true,
///     "skinSmoothing": 0.3,
///     "highlightProtection": 0.5,
///     "eyeBrightening": 0.2,
///     "localContrast": 0.15,
///     "colorCorrection": 0.2,
///     "intensity": 0.8
///   }
/// }
/// ```
public struct FaceEnhanceSettings: Codable, Sendable {
    /// Master enable for face enhancement
    public var enabled: Bool
    
    /// Skin smoothing intensity (0 = off, 1 = max)
    /// Uses bilateral filtering to reduce pores/blemishes while preserving edges
    public var skinSmoothing: Float
    
    /// Highlight protection (0 = off, 1 = max)
    /// Soft-clips highlights on skin to prevent blown-out foreheads/cheeks
    public var highlightProtection: Float
    
    /// Eye brightening intensity (0 = off, 1 = max)
    /// Subtle lift to eye whites and catchlights
    public var eyeBrightening: Float
    
    /// Local contrast / clarity on facial features (0 = off, 1 = max)
    /// Enhances definition in eyes, lips, and facial structure
    public var localContrast: Float
    
    /// Skin color correction (0 = off, 1 = max)
    /// Neutralizes color casts on skin (green/magenta shifts)
    public var colorCorrection: Float
    
    /// Saturation protection for skin tones (0 = off, 1 = max)
    /// Prevents over-saturated "sunburned" look from color grading
    public var saturationProtection: Float
    
    /// Master intensity (0 = off, 1 = full effect)
    /// Blends enhanced face with original
    public var intensity: Float
    
    /// Debug mode (0 = off, 1 = show mask, 2 = show skin detection, 3 = show diff)
    public var debugMode: Float
    
    /// Use person segmentation for better mask precision
    public var useSegmentation: Bool
    
    /// Quality level for face detection
    public var detectionQuality: DetectionQuality
    
    public enum DetectionQuality: String, Codable, Sendable {
        case fast       // Lower latency, may miss some faces
        case balanced   // Good balance of speed and accuracy
        case accurate   // Best detection, higher latency
    }
    
    public init(
        enabled: Bool = true,
        skinSmoothing: Float = 0.3,
        highlightProtection: Float = 0.5,
        eyeBrightening: Float = 0.2,
        localContrast: Float = 0.15,
        colorCorrection: Float = 0.2,
        saturationProtection: Float = 0.4,
        intensity: Float = 0.8,
        debugMode: Float = 0.0,
        useSegmentation: Bool = false,
        detectionQuality: DetectionQuality = .balanced
    ) {
        self.enabled = enabled
        self.skinSmoothing = skinSmoothing
        self.highlightProtection = highlightProtection
        self.eyeBrightening = eyeBrightening
        self.localContrast = localContrast
        self.colorCorrection = colorCorrection
        self.saturationProtection = saturationProtection
        self.intensity = intensity
        self.debugMode = debugMode
        self.useSegmentation = useSegmentation
        self.detectionQuality = detectionQuality
    }
    
    // MARK: - Presets
    
    /// Subtle enhancement for documentary/natural look
    public static let subtle = FaceEnhanceSettings(
        skinSmoothing: 0.15,
        highlightProtection: 0.3,
        eyeBrightening: 0.1,
        localContrast: 0.1,
        colorCorrection: 0.1,
        saturationProtection: 0.2,
        intensity: 0.6
    )
    
    /// Standard interview enhancement
    public static let interview = FaceEnhanceSettings(
        skinSmoothing: 0.3,
        highlightProtection: 0.5,
        eyeBrightening: 0.2,
        localContrast: 0.15,
        colorCorrection: 0.2,
        saturationProtection: 0.4,
        intensity: 0.8
    )
    
    /// Polished corporate/commercial look
    public static let polished = FaceEnhanceSettings(
        skinSmoothing: 0.5,
        highlightProtection: 0.6,
        eyeBrightening: 0.3,
        localContrast: 0.2,
        colorCorrection: 0.3,
        saturationProtection: 0.5,
        intensity: 0.9
    )
    
    /// Beauty/glamour look (more aggressive)
    public static let beauty = FaceEnhanceSettings(
        skinSmoothing: 0.7,
        highlightProtection: 0.7,
        eyeBrightening: 0.4,
        localContrast: 0.25,
        colorCorrection: 0.4,
        saturationProtection: 0.6,
        intensity: 1.0
    )
}

// MARK: - Background Blur Settings

public struct BackgroundBlurSettings: Codable, Sendable {
    /// Master enable for background blur
    public var enabled: Bool
    
    /// Blur radius in pixels (0-50, typically 5-20)
    public var radius: Float
    
    /// Person mask threshold (0-1). Above = person, below = background
    public var maskThreshold: Float
    
    /// Segmentation quality: fast, balanced, or accurate
    public var segmentationQuality: String
    
    public init(
        enabled: Bool = false,
        radius: Float = 15.0,
        maskThreshold: Float = 0.5,
        segmentationQuality: String = "balanced"
    ) {
        self.enabled = enabled
        self.radius = radius
        self.maskThreshold = maskThreshold
        self.segmentationQuality = segmentationQuality
    }
    
    // MARK: - Presets
    
    /// Subtle background blur
    public static let subtle = BackgroundBlurSettings(
        enabled: true,
        radius: 8.0,
        maskThreshold: 0.5
    )
    
    /// Standard background blur
    public static let standard = BackgroundBlurSettings(
        enabled: true,
        radius: 15.0,
        maskThreshold: 0.5
    )
    
    /// Strong cinematic background blur
    public static let cinematic = BackgroundBlurSettings(
        enabled: true,
        radius: 25.0,
        maskThreshold: 0.4
    )
}

// MARK: - TimelineModel Audio Management

extension TimelineModel {
    
    /// Add an audio track to the timeline
    public mutating func addAudioTrack(_ track: AudioTrack) {
        audioTracks.append(track)
    }
    
    /// Remove an audio track by ID
    @discardableResult
    public mutating func removeAudioTrack(id: AudioTrackID) -> Bool {
        let initialCount = audioTracks.count
        audioTracks.removeAll { $0.id == id }
        return audioTracks.count < initialCount
    }
    
    /// Get an audio track by ID
    public func audioTrack(id: AudioTrackID) -> AudioTrack? {
        audioTracks.first { $0.id == id }
    }
    
    /// Get the index of an audio track by ID
    public func audioTrackIndex(id: AudioTrackID) -> Int? {
        audioTracks.firstIndex { $0.id == id }
    }
    
    /// Update an audio track by ID
    @discardableResult
    public mutating func updateAudioTrack(id: AudioTrackID, with track: AudioTrack) -> Bool {
        guard let index = audioTrackIndex(id: id) else { return false }
        audioTracks[index] = track
        return true
    }
    
    /// Move audio track to new position in stack
    public mutating func moveAudioTrack(id: AudioTrackID, to index: Int) {
        guard let currentIndex = audioTracks.firstIndex(where: { $0.id == id }) else { return }
        let track = audioTracks.remove(at: currentIndex)
        let safeIndex = min(max(0, index), audioTracks.count)
        audioTracks.insert(track, at: safeIndex)
    }
    
    /// Get all audio clips active at a specific time across all tracks
    public func audioClips(at time: Double) -> [(track: AudioTrack, clips: [AudioClipDefinition])] {
        audioTracks.compactMap { track in
            let activeClips = track.clips.filter { clip in
                let clipStart = clip.timelineIn
                let clipEnd = clip.timelineIn + (clip.sourceOut - clip.sourceIn)
                return time >= clipStart && time < clipEnd
            }
            return activeClips.isEmpty ? nil : (track: track, clips: activeClips)
        }
    }
    
    /// Total audio duration (longest track end time)
    public var audioDuration: Double {
        audioTracks.map { track in
            track.clips.map { clip in
                clip.timelineIn + (clip.sourceOut - clip.sourceIn)
            }.max() ?? 0
        }.max() ?? 0
    }
    
    /// Get all dialogue/voiceover tracks (for ducking)
    public var dialogueTracks: [AudioTrack] {
        audioTracks.filter { track in
            switch track.type {
            case .dialogue, .voiceover:
                return true
            default:
                return false
            }
        }
    }
    
    /// Get all music tracks (ducking targets)
    public var musicTracks: [AudioTrack] {
        audioTracks.filter { $0.type == .music }
    }
    
    /// Get all sound effects tracks
    public var sfxTracks: [AudioTrack] {
        audioTracks.filter { $0.type == .sfx }
    }
    
    /// Check if any audio exists in timeline
    public var hasAudio: Bool {
        !audioTracks.isEmpty && audioTracks.contains { !$0.clips.isEmpty }
    }
    
    /// Count total audio clips across all tracks
    public var totalAudioClips: Int {
        audioTracks.reduce(0) { $0 + $1.clips.count }
    }
}

// MARK: - Backward Compatibility

extension TimelineModel {
    
    enum CodingKeys: String, CodingKey {
        case id, fps, resolution
        case videoTracks, graphicsTracks, audioTracks
        case transitions, audioTransitions
        case sources, markers, quality
        case scene, camera, compositing, look
        case explicitDuration
    }
    
    /// Custom decoder to handle backward compatibility
    /// - Old manifests without audioTracks/audioTransitions will default to empty arrays
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Required fields
        id = try container.decode(String.self, forKey: .id)
        fps = try container.decode(Double.self, forKey: .fps)
        resolution = try container.decode(SIMD2<Int>.self, forKey: .resolution)
        videoTracks = try container.decode([VideoTrack].self, forKey: .videoTracks)
        graphicsTracks = try container.decode([GraphicsTrack].self, forKey: .graphicsTracks)
        transitions = try container.decode([TransitionDefinition].self, forKey: .transitions)
        
        // Audio fields with backward compatibility (default to empty if missing)
        audioTracks = try container.decodeIfPresent([AudioTrack].self, forKey: .audioTracks) ?? []
        audioTransitions = try container.decodeIfPresent([AudioTransition].self, forKey: .audioTransitions) ?? []
        
        // Optional fields
        sources = try container.decodeIfPresent([String: SourceInfo].self, forKey: .sources) ?? [:]
        markers = try container.decodeIfPresent([TimelineMarker].self, forKey: .markers) ?? []
        quality = try container.decodeIfPresent(QualityMode.self, forKey: .quality) ?? .standard
        scene = try container.decodeIfPresent(SceneDefinition.self, forKey: .scene)
        camera = try container.decodeIfPresent(CameraDefinition.self, forKey: .camera)
        compositing = try container.decodeIfPresent(CompositingDefinition.self, forKey: .compositing)
        look = try container.decodeIfPresent(CinematicLook.self, forKey: .look)
        explicitDuration = try container.decodeIfPresent(Double.self, forKey: .explicitDuration)
    }
}

