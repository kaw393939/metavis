import Foundation

public struct Composition: Codable, Sendable {
    public let title: String
    public let width: Int?
    public let height: Int?
    public let duration: Double
    public let output: CompositionOutputConfig?
    public let cinematic: CinematicConfig?
    public let audioTracks: [AudioTrack]?
    public let assets: [DemoAsset]?
    public let timeline: [TimelineEvent]
    public let effects: [EffectConfig]?

    private enum CodingKeys: String, CodingKey {
        case title, width, height, duration, output, cinematic, audioTracks = "audio_tracks", assets, timeline, effects
    }

    public init(
        title: String,
        width: Int? = nil,
        height: Int? = nil,
        duration: Double,
        output: CompositionOutputConfig? = nil,
        cinematic: CinematicConfig? = nil,
        audioTracks: [AudioTrack]? = nil,
        assets: [DemoAsset]? = nil,
        timeline: [TimelineEvent],
        effects: [EffectConfig]? = nil
    ) {
        self.title = title
        self.width = width
        self.height = height
        self.duration = duration
        self.output = output
        self.cinematic = cinematic
        self.audioTracks = audioTracks
        self.assets = assets
        self.timeline = timeline
        self.effects = effects
    }
}

public struct EffectConfig: Codable, Sendable {
    public let type: String
    public let parameters: [String: AnyCodable]?
    
    public init(type: String, parameters: [String: AnyCodable]? = nil) {
        self.type = type
        self.parameters = parameters
    }
}

public struct CompositionOutputConfig: Codable, Sendable {
    public let codec: String?
    public let format: String?
    public let resolution: String?
    public let bitrate: Int?
    public let framerate: Double?

    public init(
        codec: String? = nil,
        format: String? = nil,
        resolution: String? = nil,
        bitrate: Int? = nil,
        framerate: Double? = nil
    ) {
        self.codec = codec
        self.format = format
        self.resolution = resolution
        self.bitrate = bitrate
        self.framerate = framerate
    }
}

public struct DemoAsset: Codable, Sendable {
    public let id: String
    public let type: String
    public let src: String
    public let transferFunction: String?

    public init(id: String, type: String, src: String, transferFunction: String? = nil) {
        self.id = id
        self.type = type
        self.src = src
        self.transferFunction = transferFunction
    }
}

/// Represents a single event in the demo timeline.
///
/// This struct acts as a union of all possible event properties.
/// Different `type` values will utilize different subsets of these properties.
public struct TimelineEvent: Codable, Sendable {
    /// The start time of the event in seconds relative to the beginning of the demo.
    public let start: Double

    /// The duration of the event in seconds.
    public let duration: Double

    /// The primary type of the event (e.g., .image, .video, .text).
    public let type: EventType

    /// An optional subtype for more specific behavior (e.g., "grid_overlay" for .debug events).
    public let subtype: String?

    /// The z-index layer for rendering order. Higher values are rendered on top.
    public let layer: Int?

    // MARK: - Content Properties

    /// The path or URL to the asset (image/video file).
    public let asset: String?

    /// A reference ID to an asset defined in the `assets` block of the manifest.
    public let assetId: String?

    /// Text content for .text events.
    public let content: String?

    /// Arbitrary data payload for visualization events (graphs, charts).
    public let data: AnyCodable?

    // MARK: - Specific Properties

    /// The type of chart to render (e.g., "bar", "line") for .chart events.
    public let chartType: String?

    /// A title string, often used in charts or debug overlays.
    public let title: String?

    /// The start time in seconds to trim from the beginning of a video or audio asset.
    public let trimStart: Double?

    /// An offset in seconds to shift audio synchronization.
    public let audioOffset: Double?

    /// The name of a specific effect to apply (e.g., "typewriter" for text).
    public let effect: String?

    /// A dictionary of parameters for effects or custom shaders.
    public let parameters: [String: AnyCodable]?

    /// Configuration object for complex events like debug overlays.
    public let config: AnyCodable?

    /// Hex color string (e.g., "#FF0000") for solid color events or text.
    public let color: String?

    /// Linear RGB color array [r, g, b] or [r, g, b, a] for HDR values.
    public let colorLinear: [Double]?

    /// Opacity level from 0.0 (transparent) to 1.0 (opaque).
    public let opacity: Double?

    /// The blend mode to use when compositing this event (e.g., "normal", "add", "multiply").
    public let blendMode: String?

    /// Transform configuration for position, scale, and rotation.
    public let transform: TransformConfig?

    /// Layout configuration for responsive positioning (anchors, margins).
    public let layout: LayoutConfig?

    /// Style configuration for text and shapes (borders, shadows, fonts).
    public let style: EventStyleConfig?

    /// Animation configuration for property tweening.
    public let animation: EventAnimationConfig?

    /// Playback speed multiplier (1.0 is normal speed).
    public let speed: Double?

    /// Whether the video or audio should loop.
    public let loop: Bool?

    /// The duration of the source clip to use (trim end).
    public let trimDuration: Double?

    private enum CodingKeys: String, CodingKey {
        case start, duration, type, subtype, layer, asset, assetId, content, data, chartType, title, trimStart = "trim_start", audioOffset = "audio_offset", effect, parameters, config, color, colorLinear = "color_linear", opacity, blendMode, transform, layout, style, animation, speed, loop, trimDuration = "trim_duration"
    }

    public init(
        start: Double,
        duration: Double,
        type: EventType,
        subtype: String? = nil,
        layer: Int? = nil,
        asset: String? = nil,
        assetId: String? = nil,
        content: String? = nil,
        data: AnyCodable? = nil,
        chartType: String? = nil,
        title: String? = nil,
        trimStart: Double? = nil,
        audioOffset: Double? = nil,
        effect: String? = nil,
        parameters: [String: AnyCodable]? = nil,
        config: AnyCodable? = nil,
        color: String? = nil,
        colorLinear: [Double]? = nil,
        opacity: Double? = nil,
        blendMode: String? = nil,
        transform: TransformConfig? = nil,
        layout: LayoutConfig? = nil,
        style: EventStyleConfig? = nil,
        animation: EventAnimationConfig? = nil,
        speed: Double? = nil,
        loop: Bool? = nil,
        trimDuration: Double? = nil
    ) {
        self.start = start
        self.duration = duration
        self.type = type
        self.subtype = subtype
        self.layer = layer
        self.asset = asset
        self.assetId = assetId
        self.content = content
        self.data = data
        self.chartType = chartType
        self.title = title
        self.trimStart = trimStart
        self.audioOffset = audioOffset
        self.effect = effect
        self.parameters = parameters
        self.config = config
        self.color = color
        self.colorLinear = colorLinear
        self.opacity = opacity
        self.blendMode = blendMode
        self.transform = transform
        self.layout = layout
        self.style = style
        self.animation = animation
        self.speed = speed
        self.loop = loop
        self.trimDuration = trimDuration
    }
}

public struct EventAnimationConfig: Codable, Sendable {
    public let property: String?
    public let from: Double?
    public let to: Double?
    public let duration: Double?
    public let easing: String?
    public let type: String? // Added for semantic animations like "grow_up"
    public let fadeIn: Double? // Added for shorthand

    public init(property: String? = nil, from: Double? = nil, to: Double? = nil, duration: Double? = nil, easing: String? = nil, type: String? = nil, fadeIn: Double? = nil) {
        self.property = property
        self.from = from
        self.to = to
        self.duration = duration
        self.easing = easing
        self.type = type
        self.fadeIn = fadeIn
    }
}

public struct EventStyleConfig: Codable, Sendable {
    public let border: BorderConfig?
    public let shadow: ShadowConfig?
    public let font: String?
    public let size: Double?
    public let color: String?
    public let alignment: String?
    public let lineHeight: Double?

    public init(
        border: BorderConfig? = nil,
        shadow: ShadowConfig? = nil,
        font: String? = nil,
        size: Double? = nil,
        color: String? = nil,
        alignment: String? = nil,
        lineHeight: Double? = nil
    ) {
        self.border = border
        self.shadow = shadow
        self.font = font
        self.size = size
        self.color = color
        self.alignment = alignment
        self.lineHeight = lineHeight
    }
}

public struct BorderConfig: Codable, Sendable {
    public let width: Double
    public let color: String

    public init(width: Double, color: String) {
        self.width = width
        self.color = color
    }
}

public struct ShadowConfig: Codable, Sendable {
    public let radius: Double
    public let opacity: Double

    public init(radius: Double, opacity: Double) {
        self.radius = radius
        self.opacity = opacity
    }
}

public struct LayoutConfig: Codable, Sendable {
    public let anchor: String?
    public let safeArea: String?
    public let margin: Double?
    public let offset: TransformPosition?
    public let width: Double?

    public init(anchor: String? = nil, safeArea: String? = nil, margin: Double? = nil, offset: TransformPosition? = nil, width: Double? = nil) {
        self.anchor = anchor
        self.safeArea = safeArea
        self.margin = margin
        self.offset = offset
        self.width = width
    }
}

public struct TransformPosition: Codable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct TransformScale: Codable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(uniform: Double) {
        x = uniform
        y = uniform
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let doubleVal = try? container.decode(Double.self) {
            x = doubleVal
            y = doubleVal
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            x = try container.decode(Double.self, forKey: .x)
            y = try container.decode(Double.self, forKey: .y)
        }
    }

    public func encode(to encoder: Encoder) throws {
        if x == y {
            var container = encoder.singleValueContainer()
            try container.encode(x)
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case x, y
    }
}

public struct TransformConfig: Codable, Sendable {
    public let scale: TransformScale?
    public let position: TransformPosition?
    public let rotation: Double?

    public init(scale: TransformScale? = nil, position: TransformPosition? = nil, rotation: Double? = nil) {
        self.scale = scale
        self.position = position
        self.rotation = rotation
    }
}

public enum EventType: String, Codable, Sendable {
    case image
    case video
    case text
    case graph
    case chart
    case color
    case audio
    case visualization
    case debug
    case sfx
    case voice
    case shape
    case group
}

// Helper for mixed types in JSON
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let arrayVal = try? container.decode([AnyCodable].self) {
            value = arrayVal.map { $0.value }
        } else if let dictVal = try? container.decode([String: AnyCodable].self) {
            value = dictVal.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intVal = value as? Int {
            try container.encode(intVal)
        } else if let doubleVal = value as? Double {
            try container.encode(doubleVal)
        } else if let stringVal = value as? String {
            try container.encode(stringVal)
        } else if let boolVal = value as? Bool {
            try container.encode(boolVal)
        } else if let arrayVal = value as? [Any] {
            try container.encode(arrayVal.map { AnyCodable($0) })
        } else if let dictVal = value as? [String: Any] {
            try container.encode(dictVal.mapValues { AnyCodable($0) })
        } else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded"))
        }
    }
}

public struct CinematicConfig: Codable, Sendable {
    public let letterbox: Bool?
    public let aspectRatio: Double?
    public let vignetteIntensity: Double?
    public let filmGrainStrength: Double?
    public let bloomIntensity: Double?
    public let bloomThreshold: Double?
    public let bloomRadius: Double?
    public let colorGrading: ColorGradingConfig?
    public let odt: String?
    public let tonemapOperator: String?
    public let lut: LUTConfig?

    public init(
        letterbox: Bool? = nil,
        aspectRatio: Double? = nil,
        vignetteIntensity: Double? = nil,
        filmGrainStrength: Double? = nil,
        bloomIntensity: Double? = nil,
        bloomThreshold: Double? = nil,
        bloomRadius: Double? = nil,
        colorGrading: ColorGradingConfig? = nil,
        odt: String? = nil,
        tonemapOperator: String? = nil,
        lut: LUTConfig? = nil
    ) {
        self.letterbox = letterbox
        self.aspectRatio = aspectRatio
        self.vignetteIntensity = vignetteIntensity
        self.filmGrainStrength = filmGrainStrength
        self.bloomIntensity = bloomIntensity
        self.bloomThreshold = bloomThreshold
        self.bloomRadius = bloomRadius
        self.colorGrading = colorGrading
        self.odt = odt
        self.tonemapOperator = tonemapOperator
        self.lut = lut
    }
}

public struct LUTConfig: Codable, Sendable {
    public let path: String
    public let domain: String?
    public let intensity: Double?

    public init(path: String, domain: String? = nil, intensity: Double? = nil) {
        self.path = path
        self.domain = domain
        self.intensity = intensity
    }
}

public struct ColorGradingConfig: Codable, Sendable {
    public let mode: String?
    public let lutName: String?
    public let strength: Double?
    public let shadows: ColorComponent?
    public let midtones: ColorComponent?
    public let highlights: ColorComponent?
    public let contrast: Double?
    public let brightness: Double?
    public let saturation: Double?
    public let hue: Double?

    public init(
        mode: String? = nil,
        lutName: String? = nil,
        strength: Double? = nil,
        shadows: ColorComponent? = nil,
        midtones: ColorComponent? = nil,
        highlights: ColorComponent? = nil,
        contrast: Double? = nil,
        brightness: Double? = nil,
        saturation: Double? = nil,
        hue: Double? = nil
    ) {
        self.mode = mode
        self.lutName = lutName
        self.strength = strength
        self.shadows = shadows
        self.midtones = midtones
        self.highlights = highlights
        self.contrast = contrast
        self.brightness = brightness
        self.saturation = saturation
        self.hue = hue
    }
}

public struct ColorComponent: Codable, Sendable {
    public let r: Double?
    public let g: Double?
    public let b: Double?
    public let a: Double?

    public init(r: Double? = nil, g: Double? = nil, b: Double? = nil, a: Double? = nil) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}
