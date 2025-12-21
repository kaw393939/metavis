// Sources/MetalVisCore/Validation/Configuration/OutputProfile.swift
// MetaVis Studio - Autonomous Development Infrastructure

import Foundation

/// Defines an output resolution/aspect ratio profile for validation testing.
/// Each profile represents a target output format (landscape, portrait, square, etc.)
public struct OutputProfile: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let width: Int
    public let height: Int
    public let aspectRatio: String
    public let category: ProfileCategory
    
    public enum ProfileCategory: String, Codable, Sendable {
        case landscape
        case portrait
        case square
        case ultrawide
    }
    
    /// Computed aspect ratio as a decimal
    public var aspectRatioDecimal: Double {
        Double(width) / Double(height)
    }
    
    /// Whether this is a portrait orientation
    public var isPortrait: Bool {
        height > width
    }
    
    /// Whether this is a landscape orientation
    public var isLandscape: Bool {
        width > height
    }
    
    // MARK: - Standard Profiles
    
    public static let landscape1080p = OutputProfile(
        id: "landscape_1080p",
        name: "Landscape 1080p",
        width: 1920,
        height: 1080,
        aspectRatio: "16:9",
        category: .landscape
    )
    
    public static let portrait1080p = OutputProfile(
        id: "portrait_1080p",
        name: "Portrait 1080p",
        width: 1080,
        height: 1920,
        aspectRatio: "9:16",
        category: .portrait
    )
    
    public static let landscape4K = OutputProfile(
        id: "landscape_4k",
        name: "Landscape 4K",
        width: 3840,
        height: 2160,
        aspectRatio: "16:9",
        category: .landscape
    )
    
    public static let portrait4K = OutputProfile(
        id: "portrait_4k",
        name: "Portrait 4K",
        width: 2160,
        height: 3840,
        aspectRatio: "9:16",
        category: .portrait
    )
    
    public static let square1080 = OutputProfile(
        id: "square_1080",
        name: "Square 1080",
        width: 1080,
        height: 1080,
        aspectRatio: "1:1",
        category: .square
    )
    
    public static let cinemascope = OutputProfile(
        id: "cinemascope",
        name: "CinemaScope 2.39:1",
        width: 2048,
        height: 858,
        aspectRatio: "2.39:1",
        category: .ultrawide
    )
    
    /// All standard profiles
    public static let allStandard: [OutputProfile] = [
        .landscape1080p,
        .portrait1080p,
        .landscape4K,
        .portrait4K,
        .square1080,
        .cinemascope
    ]
    
    /// Default profiles for quick validation
    public static let defaultProfiles: [OutputProfile] = [
        .landscape1080p,
        .portrait1080p
    ]
}

extension OutputProfile: CustomStringConvertible {
    public var description: String {
        "\(name) (\(width)×\(height))"
    }
}
