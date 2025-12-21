import Foundation

// MARK: - 3.1.1 JSON Schema (Draft v1.0) Implementation

public struct MetaVisProject: Codable, Sendable {
    public let name: String
    public let resolution: Resolution
    public let frameRate: Double
    public let colorSpace: MetaVisColorSpace
    public let outputFormat: OutputFormat
    public let timeline: Timeline

    public init(name: String, resolution: Resolution, frameRate: Double, colorSpace: MetaVisColorSpace, outputFormat: OutputFormat, timeline: Timeline) {
        self.name = name
        self.resolution = resolution
        self.frameRate = frameRate
        self.colorSpace = colorSpace
        self.outputFormat = outputFormat
        self.timeline = timeline
    }
}

public struct Resolution: Codable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public enum MetaVisColorSpace: String, Codable, Sendable {
    case acescg = "ACEScg"
    case rec709 = "Rec709"
    case p3d65 = "P3D65"
}

public enum OutputFormat: String, Codable, Sendable {
    case h264 = "H264"
    case hevc = "HEVC"
    case proRes422 = "ProRes422"
    case proRes4444 = "ProRes4444"
}

// MARK: - Timeline & Tracks

public struct Timeline: Codable, Sendable {
    public let duration: Double
    public let tracks: [Track]

    public init(duration: Double, tracks: [Track]) {
        self.duration = duration
        self.tracks = tracks
    }
}

public struct Track: Codable, Sendable {
    public let id: String
    public let type: TrackType
    public let clips: [Clip]
    public let zOrder: Int
    public let blendMode: BlendMode

    public init(id: String, type: TrackType, clips: [Clip], zOrder: Int, blendMode: BlendMode = .normal) {
        self.id = id
        self.type = type
        self.clips = clips
        self.zOrder = zOrder
        self.blendMode = blendMode
    }
}

public enum TrackType: String, Codable, Sendable {
    case video
    case audio
}

public enum BlendMode: String, Codable, Sendable {
    case normal
    case add
    case multiply
    case screen
    case overlay
    case softLight
    case hardLight
}

// MARK: - Clips

public struct Clip: Codable, Sendable {
    public let id: String
    public let type: ClipType
    public let startTime: Double
    public let duration: Double
    public let transform: TransformBlock?
    public let effects: [EffectBlock]?
    public let audio: AudioBlock? // Only relevant for audio/video clips

    // Content specific properties.
    // In a real schema, we might use a polymorphic decoder, but for simplicity here we use optional fields
    public let source: String? // For image, video, audio
    public let text: TextContent?
    public let gradient: GradientContent?
    public let color: ColorContent?
    public let kenBurns: KenBurnsContent?

    public init(id: String, type: ClipType, startTime: Double, duration: Double, transform: TransformBlock? = nil, effects: [EffectBlock]? = nil, audio: AudioBlock? = nil, source: String? = nil, text: TextContent? = nil, gradient: GradientContent? = nil, color: ColorContent? = nil, kenBurns: KenBurnsContent? = nil) {
        self.id = id
        self.type = type
        self.startTime = startTime
        self.duration = duration
        self.transform = transform
        self.effects = effects
        self.audio = audio
        self.source = source
        self.text = text
        self.gradient = gradient
        self.color = color
        self.kenBurns = kenBurns
    }
}

public enum ClipType: String, Codable, Sendable {
    case image
    case video
    case kenBurns
    case text
    case proceduralChart
    case proceduralGraph
    case gradient
    case color
    case noise
    case mask
}

// MARK: - Content Models

public struct TextContent: Codable, Sendable {
    public let content: String
    public let font: String
    public let size: Double
    public let alignment: TextAlignment
    public let color: ColorVector

    public init(content: String, font: String, size: Double, alignment: TextAlignment, color: ColorVector) {
        self.content = content
        self.font = font
        self.size = size
        self.alignment = alignment
        self.color = color
    }
}

public enum TextAlignment: String, Codable, Sendable {
    case left, center, right, justified
}

public struct GradientContent: Codable, Sendable {
    public let stops: [GradientStop]
    public let startPoint: Point
    public let endPoint: Point

    public init(stops: [GradientStop], startPoint: Point, endPoint: Point) {
        self.stops = stops
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
}

public struct GradientStop: Codable, Sendable {
    public let offset: Double
    public let color: ColorVector

    public init(offset: Double, color: ColorVector) {
        self.offset = offset
        self.color = color
    }
}

public struct ColorContent: Codable, Sendable {
    public let color: ColorVector

    public init(color: ColorVector) {
        self.color = color
    }
}

public struct KenBurnsContent: Codable, Sendable {
    public let startRect: Rect
    public let endRect: Rect

    public init(startRect: Rect, endRect: Rect) {
        self.startRect = startRect
        self.endRect = endRect
    }
}

// MARK: - Transform & Effects

public struct TransformBlock: Codable, Sendable {
    public let position: Point?
    public let scale: Point? // x, y scale
    public let rotation: Double? // degrees
    public let anchorPoint: Point?
    public let opacity: Double?
    public let easing: EasingType?

    public init(position: Point? = nil, scale: Point? = nil, rotation: Double? = nil, anchorPoint: Point? = nil, opacity: Double? = nil, easing: EasingType? = nil) {
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.anchorPoint = anchorPoint
        self.opacity = opacity
        self.easing = easing
    }
}

public enum EasingType: String, Codable, Sendable {
    case linear
    case cubicBezier
    case sine
    case expo
    case back
    case bounce
}

public struct EffectBlock: Codable, Sendable {
    public let type: EffectType
    public let parameters: [String: Double] // Simplified for now
    public let lutPath: String? // Specific for LUT effect

    public init(type: EffectType, parameters: [String: Double] = [:], lutPath: String? = nil) {
        self.type = type
        self.parameters = parameters
        self.lutPath = lutPath
    }
}

public enum EffectType: String, Codable, Sendable {
    case lut
    case filmGrain
    case bloom
    case vignette
    case chromaticAberration
    case shutterAngleBlur
    case lensDistortion
}

// MARK: - Audio

public struct AudioBlock: Codable, Sendable {
    public let gain: Double?
    public let fadeIn: Double?
    public let fadeOut: Double?
    public let ducking: DuckingRule?

    public init(gain: Double? = nil, fadeIn: Double? = nil, fadeOut: Double? = nil, ducking: DuckingRule? = nil) {
        self.gain = gain
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.ducking = ducking
    }
}

public struct DuckingRule: Codable, Sendable {
    public let targetTrackId: String
    public let amount: Double
    public let attack: Double
    public let release: Double

    public init(targetTrackId: String, amount: Double, attack: Double, release: Double) {
        self.targetTrackId = targetTrackId
        self.amount = amount
        self.attack = attack
        self.release = release
    }
}

// MARK: - Primitives

public struct Point: Codable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct Rect: Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct ColorVector: Codable, Sendable {
    public let r: Double
    public let g: Double
    public let b: Double
    public let a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}
