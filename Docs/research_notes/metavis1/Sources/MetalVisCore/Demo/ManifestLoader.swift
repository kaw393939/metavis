import Foundation
import Shared

public struct ProjectManifest: Codable {
    public let title: String
    public let duration: Double
    public let audioTracks: [ManifestAudioTrack]
    public let timeline: [ManifestVisualClip]
    public let cinematic: CinematicConfig?

    enum CodingKeys: String, CodingKey {
        case title, duration
        case audioTracks = "audio_tracks"
        case timeline
        case cinematic
    }
}

public struct ManifestAudioTrack: Codable {
    public let id: String
    public let file: String
    public let type: String // "voice", "music", "sfx"
    public let startTime: Double
    public let volume: Float

    enum CodingKeys: String, CodingKey {
        case id, file, type, volume
        case startTime = "start_time"
    }
}

public struct ManifestVisualClip: Codable {
    public let start: Double
    public let duration: Double
    public let type: String // "video", "image", "text", "chart", "map"
    public let asset: String?
    public let content: String? // For text
    public let trimStart: Double? // Start time in the source asset
    public let effect: String?
    public let parameters: [String: AnyCodable]?
    public let chartData: ChartData?
    public let mapData: MapData?
    public let quoteData: QuoteData?

    enum CodingKeys: String, CodingKey {
        case start, duration, type, asset, content, effect, parameters
        case trimStart = "trim_start"
        case chartData = "chart_data"
        case mapData = "map_data"
        case quoteData = "quote_data"
    }
}

public struct QuoteData: Codable {
    public let text: String
    public let author: String?
    public let style: String? // "modern", "serif", "typewriter"
}

public struct ChartData: Codable {
    public let labels: [String]
    public let values: [Double]
    public let title: String?
    public let color: String? // Hex code or name
}

public struct MapData: Codable {
    public let style: String? // "vintage", "satellite"
    public let path: [MapPoint]
    public let geoBounds: GeoBounds?
    public let projection: String? // "mercator", "equirectangular"

    enum CodingKeys: String, CodingKey {
        case style, path, projection
        case geoBounds = "geo_bounds"
    }
}

public struct GeoBounds: Codable {
    public let minLat: Double
    public let maxLat: Double
    public let minLon: Double
    public let maxLon: Double

    enum CodingKeys: String, CodingKey {
        case minLat = "min_lat"
        case maxLat = "max_lat"
        case minLon = "min_lon"
        case maxLon = "max_lon"
    }
}

public struct MapPoint: Codable {
    public let x: Double? // 0.0-1.0
    public let y: Double? // 0.0-1.0
    public let lat: Double?
    public let lon: Double?
}

// AnyCodable removed, using Shared.AnyCodable
