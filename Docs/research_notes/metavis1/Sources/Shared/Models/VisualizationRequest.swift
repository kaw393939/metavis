import Foundation

/// Main visualization request structure matching ei_cli pattern
public struct VisualizationRequest: Codable, Sendable {
    public let visualizationType: VisualizationType
    public let outputConfig: OutputConfig
    public let data: VisualizationData
    public let style: StyleConfig?
    public let animation: AnimationConfig?
    public let audio: [AudioTrack]?
    public let cinematic: CinematicConfig?

    public init(
        visualizationType: VisualizationType,
        outputConfig: OutputConfig,
        data: VisualizationData,
        style: StyleConfig? = nil,
        animation: AnimationConfig? = nil,
        audio: [AudioTrack]? = nil,
        cinematic: CinematicConfig? = nil
    ) {
        self.visualizationType = visualizationType
        self.outputConfig = outputConfig
        self.data = data
        self.style = style
        self.animation = animation
        self.audio = audio
        self.cinematic = cinematic
    }
}

public enum VisualizationType: String, Codable, Sendable {
    case knowledgeGraph = "knowledge_graph"
    case timeline
    case geographic
    case dataChart = "data_chart"
    case networkFlow = "network_flow"
}

/// Output configuration with preset support
public struct OutputConfig: Codable, Sendable {
    public let resolution: ResolutionConfig
    public let frameRate: Int
    public let duration: Double
    public let codec: String
    public let quality: Quality
    public let backgroundColor: [Float]
    public let includeAlpha: Bool

    private enum CodingKeys: String, CodingKey {
        case resolution, frameRate, duration, codec, quality, backgroundColor, includeAlpha
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resolution = try container.decode(ResolutionConfig.self, forKey: .resolution)
        frameRate = try container.decodeIfPresent(Int.self, forKey: .frameRate) ?? 30
        duration = try container.decode(Double.self, forKey: .duration)
        codec = try container.decodeIfPresent(String.self, forKey: .codec) ?? "h264"
        quality = try container.decodeIfPresent(Quality.self, forKey: .quality) ?? .high
        backgroundColor = try container.decodeIfPresent([Float].self, forKey: .backgroundColor) ?? [0.05, 0.05, 0.08, 1.0]
        includeAlpha = try container.decodeIfPresent(Bool.self, forKey: .includeAlpha) ?? false
    }

    public init(
        resolution: ResolutionConfig,
        frameRate: Int = 30,
        duration: Double,
        codec: String = "h264",
        quality: Quality = .high,
        backgroundColor: [Float] = [0.05, 0.05, 0.08, 1.0],
        includeAlpha: Bool = false
    ) {
        self.resolution = resolution
        self.frameRate = frameRate
        self.duration = duration
        self.codec = codec
        self.quality = quality
        self.backgroundColor = backgroundColor
        self.includeAlpha = includeAlpha
    }

    public enum Quality: String, Codable, Sendable {
        case low, medium, high, lossless
    }
}

/// Resolution configuration with preset support
public struct ResolutionConfig: Codable, Sendable {
    public let width: Int
    public let height: Int
    public let preset: String?

    public init(width: Int, height: Int, preset: String? = nil) {
        self.width = width
        self.height = height
        self.preset = preset
    }

    public init(preset: ResolutionPreset) {
        width = preset.width
        height = preset.height
        self.preset = preset.rawValue
    }
}

public enum ResolutionPreset: String, Codable, Sendable {
    case youtubeLandscape = "youtube_landscape"
    case youtubeShort = "youtube_short"
    case instagramSquare = "instagram_square"
    case fourKLandscape = "4k_landscape"

    public var width: Int {
        switch self {
        case .youtubeLandscape: return 1920
        case .youtubeShort: return 1080
        case .instagramSquare: return 1080
        case .fourKLandscape: return 3840
        }
    }

    public var height: Int {
        switch self {
        case .youtubeLandscape: return 1080
        case .youtubeShort: return 1920
        case .instagramSquare: return 1080
        case .fourKLandscape: return 2160
        }
    }
}

/// Polymorphic visualization data
public enum VisualizationData: Codable, Sendable {
    case graph(GraphData)
    case timeline(TimelineData)
    case geographic(GeographicData)
    case chart(ChartData)
    case networkFlow(NetworkFlowData)

    private enum CodingKeys: String, CodingKey {
        case type, data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "graph":
            let data = try container.decode(GraphData.self, forKey: .data)
            self = .graph(data)
        case "timeline":
            let data = try container.decode(TimelineData.self, forKey: .data)
            self = .timeline(data)
        case "geographic":
            let data = try container.decode(GeographicData.self, forKey: .data)
            self = .geographic(data)
        case "chart":
            let data = try container.decode(ChartData.self, forKey: .data)
            self = .chart(data)
        case "networkFlow":
            let data = try container.decode(NetworkFlowData.self, forKey: .data)
            self = .networkFlow(data)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown visualization type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .graph(data):
            try container.encode("graph", forKey: .type)
            try container.encode(data, forKey: .data)
        case let .timeline(data):
            try container.encode("timeline", forKey: .type)
            try container.encode(data, forKey: .data)
        case let .geographic(data):
            try container.encode("geographic", forKey: .type)
            try container.encode(data, forKey: .data)
        case let .chart(data):
            try container.encode("chart", forKey: .type)
            try container.encode(data, forKey: .data)
        case let .networkFlow(data):
            try container.encode("networkFlow", forKey: .type)
            try container.encode(data, forKey: .data)
        }
    }
}

/// Style configuration
public struct StyleConfig: Codable, Sendable {
    public let colorScheme: String?
    public let fontSize: Float?
    public let nodeSize: Float?
    public let edgeThickness: Float?

    public init(
        colorScheme: String? = nil,
        fontSize: Float? = nil,
        nodeSize: Float? = nil,
        edgeThickness: Float? = nil
    ) {
        self.colorScheme = colorScheme
        self.fontSize = fontSize
        self.nodeSize = nodeSize
        self.edgeThickness = edgeThickness
    }
}

/// Animation configuration
public struct AnimationConfig: Codable, Sendable {
    public let cameraPath: [String]?
    public let duration: Double?
    public let easing: String?

    public init(
        cameraPath: [String]? = nil,
        duration: Double? = nil,
        easing: String? = nil
    ) {
        self.cameraPath = cameraPath
        self.duration = duration
        self.easing = easing
    }
}
