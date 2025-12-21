// ExportConfiguration.swift
// MetaVisRender
//
// Created for Sprint 13: Export & Delivery
// Complete configuration for export jobs

import Foundation

// MARK: - ExportQuality

/// Quality level for export
public enum ExportQuality: String, Codable, Sendable, CaseIterable {
    case draft
    case standard
    case high
    case master
    
    public var displayName: String {
        switch self {
        case .draft: return "Draft (Fast)"
        case .standard: return "Standard"
        case .high: return "High Quality"
        case .master: return "Master"
        }
    }
    
    /// Bitrate multiplier relative to preset default
    public var bitrateMultiplier: Double {
        switch self {
        case .draft: return 0.5
        case .standard: return 1.0
        case .high: return 1.5
        case .master: return 2.0
        }
    }
}

// MARK: - ReframingMode

/// How to handle aspect ratio changes
public enum ReframingMode: String, Codable, Sendable, CaseIterable {
    /// No reframing, letterbox or pillarbox as needed
    case none
    
    /// Center crop to fill
    case centerCrop
    
    /// AI-based smart crop following subjects
    case smart
    
    /// Manual crop with specified region
    case manual
    
    public var displayName: String {
        switch self {
        case .none: return "Letterbox/Pillarbox"
        case .centerCrop: return "Center Crop"
        case .smart: return "Smart Reframe"
        case .manual: return "Manual Crop"
        }
    }
}

// MARK: - CaptionMode

/// How captions are included in export
public enum CaptionMode: String, Codable, Sendable, CaseIterable {
    /// No captions
    case none
    
    /// Burn captions into video frames
    case burned
    
    /// Side-car subtitle file (SRT, VTT)
    case sidecar
    
    /// Embedded in container (CEA-608/708)
    case embedded
    
    public var displayName: String {
        switch self {
        case .none: return "None"
        case .burned: return "Burned In"
        case .sidecar: return "Side-car File"
        case .embedded: return "Embedded"
        }
    }
}

// MARK: - ThumbnailConfiguration

/// Configuration for thumbnail generation
public struct ThumbnailConfiguration: Codable, Sendable {
    /// Generate thumbnails
    public let enabled: Bool
    
    /// Thumbnail count
    public let count: Int
    
    /// Thumbnail width
    public let width: Int
    
    /// Thumbnail height
    public let height: Int
    
    /// Image format
    public let format: ThumbnailFormat
    
    /// Specific timestamps (optional)
    public let timestamps: [TimeInterval]?
    
    public init(
        enabled: Bool = true,
        count: Int = 5,
        width: Int = 640,
        height: Int = 360,
        format: ThumbnailFormat = .jpeg,
        timestamps: [TimeInterval]? = nil
    ) {
        self.enabled = enabled
        self.count = count
        self.width = width
        self.height = height
        self.format = format
        self.timestamps = timestamps
    }
    
    public static let none = ThumbnailConfiguration(enabled: false)
    public static let `default` = ThumbnailConfiguration()
    
    public static let youtube = ThumbnailConfiguration(
        enabled: true,
        count: 3,
        width: 1280,
        height: 720,
        format: .jpeg
    )
}

public enum ThumbnailFormat: String, Codable, Sendable {
    case jpeg
    case png
    case webp
    
    public var fileExtension: String { rawValue }
}

// MARK: - MetadataConfiguration

/// Metadata to embed in export
public struct MetadataConfiguration: Codable, Sendable {
    /// Title
    public var title: String?
    
    /// Description/synopsis
    public var description: String?
    
    /// Author/creator
    public var author: String?
    
    /// Copyright notice
    public var copyright: String?
    
    /// Creation date
    public var creationDate: Date?
    
    /// Keywords/tags
    public var keywords: [String]
    
    /// Custom metadata fields
    public var customFields: [String: String]
    
    public init(
        title: String? = nil,
        description: String? = nil,
        author: String? = nil,
        copyright: String? = nil,
        creationDate: Date? = nil,
        keywords: [String] = [],
        customFields: [String: String] = [:]
    ) {
        self.title = title
        self.description = description
        self.author = author
        self.copyright = copyright
        self.creationDate = creationDate
        self.keywords = keywords
        self.customFields = customFields
    }
    
    public static let empty = MetadataConfiguration()
}

// MARK: - TimeRange

/// Range of time for partial export
public struct TimeRange: Codable, Sendable, Hashable {
    public let start: TimeInterval
    public let end: TimeInterval
    
    public var duration: TimeInterval {
        end - start
    }
    
    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }
    
    public init(start: TimeInterval, duration: TimeInterval) {
        self.start = start
        self.end = start + duration
    }
    
    /// Full timeline
    public static func full(duration: TimeInterval) -> TimeRange {
        TimeRange(start: 0, end: duration)
    }
    
    /// Check if a time is within this range
    public func contains(_ time: TimeInterval) -> Bool {
        time >= start && time <= end
    }
}

// MARK: - ManualCropRegion

/// Region for manual cropping
public struct ManualCropRegion: Codable, Sendable {
    /// Normalized X position (0-1)
    public let x: Double
    
    /// Normalized Y position (0-1)
    public let y: Double
    
    /// Normalized width (0-1)
    public let width: Double
    
    /// Normalized height (0-1)
    public let height: Double
    
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    
    public static let full = ManualCropRegion(x: 0, y: 0, width: 1, height: 1)
    
    /// Center region with specified size
    public static func center(width: Double, height: Double) -> ManualCropRegion {
        ManualCropRegion(
            x: (1 - width) / 2,
            y: (1 - height) / 2,
            width: width,
            height: height
        )
    }
}

// MARK: - ExportConfiguration

/// Complete configuration for an export job
public struct ExportConfiguration: Codable, Sendable, Identifiable {
    public let id: UUID
    
    /// Base preset
    public let preset: ExportPreset
    
    /// Quality level
    public let quality: ExportQuality
    
    /// Time range to export
    public let timeRange: TimeRange?
    
    /// Reframing mode for aspect ratio changes
    public let reframingMode: ReframingMode
    
    /// Manual crop region (when reframingMode == .manual)
    public let manualCropRegion: ManualCropRegion?
    
    /// Caption handling
    public let captionMode: CaptionMode
    
    /// Caption language (ISO 639-1)
    public let captionLanguage: String?
    
    /// Thumbnail generation
    public let thumbnails: ThumbnailConfiguration
    
    /// Metadata to embed
    public let metadata: MetadataConfiguration
    
    /// Replace existing file if present
    public let replaceExisting: Bool
    
    /// Enable two-pass encoding
    public let twoPass: Bool
    
    /// Hardware acceleration
    public let hardwareAcceleration: Bool
    
    /// Priority (higher = more urgent)
    public let priority: Int
    
    public init(
        id: UUID = UUID(),
        preset: ExportPreset,
        quality: ExportQuality = .standard,
        timeRange: TimeRange? = nil,
        reframingMode: ReframingMode = .none,
        manualCropRegion: ManualCropRegion? = nil,
        captionMode: CaptionMode = .none,
        captionLanguage: String? = nil,
        thumbnails: ThumbnailConfiguration = .default,
        metadata: MetadataConfiguration = .empty,
        replaceExisting: Bool = true,
        twoPass: Bool = false,
        hardwareAcceleration: Bool = true,
        priority: Int = 0
    ) {
        self.id = id
        self.preset = preset
        self.quality = quality
        self.timeRange = timeRange
        self.reframingMode = reframingMode
        self.manualCropRegion = manualCropRegion
        self.captionMode = captionMode
        self.captionLanguage = captionLanguage
        self.thumbnails = thumbnails
        self.metadata = metadata
        self.replaceExisting = replaceExisting
        self.twoPass = twoPass
        self.hardwareAcceleration = hardwareAcceleration
        self.priority = priority
    }
    
    /// Effective video bitrate after quality adjustment
    public var effectiveVideoBitrate: Int {
        Int(Double(preset.video.bitrate) * quality.bitrateMultiplier)
    }
    
    /// Effective audio bitrate after quality adjustment
    public var effectiveAudioBitrate: Int? {
        guard let baseBitrate = preset.audio.bitrate else { return nil }
        return Int(Double(baseBitrate) * quality.bitrateMultiplier)
    }
}

// MARK: - Convenience Builders

extension ExportConfiguration {
    /// Create configuration for YouTube
    public static func youtube(
        quality: ExportQuality = .high,
        resolution: ExportResolution = .fullHD1080p
    ) -> ExportConfiguration {
        ExportConfiguration(
            preset: resolution == .uhd4K ? .youtube4K : .youtube1080p,
            quality: quality,
            thumbnails: .youtube
        )
    }
    
    /// Create configuration for TikTok/Reels
    public static func shortForm(
        platform: ExportPlatform,
        quality: ExportQuality = .high
    ) -> ExportConfiguration {
        let preset: ExportPreset
        switch platform {
        case .tiktok:
            preset = .tiktok
        case .instagramReels:
            preset = .instagramReels
        case .youtubeShorts:
            preset = .youtubeShorts
        default:
            preset = .tiktok
        }
        
        return ExportConfiguration(
            preset: preset,
            quality: quality,
            reframingMode: .smart  // Auto-reframe for portrait
        )
    }
    
    /// Create configuration for broadcast
    public static func broadcast(
        is4K: Bool = false
    ) -> ExportConfiguration {
        ExportConfiguration(
            preset: is4K ? .broadcast4K : .broadcastHD,
            quality: .master,
            captionMode: .embedded
        )
    }
    
    /// Create configuration for archive
    public static func archive(
        resolution: ExportResolution = .fullHD1080p
    ) -> ExportConfiguration {
        ExportConfiguration(
            preset: resolution == .uhd4K ? .archive4K : .archiveProRes,
            quality: .master
        )
    }
}

// MARK: - Multi-Output Configuration

/// Configuration for exporting to multiple outputs at once
public struct MultiOutputConfiguration: Codable, Sendable {
    /// Base source timeline
    public let sourceTimeRange: TimeRange?
    
    /// Output configurations
    public let outputs: [ExportConfiguration]
    
    /// Export outputs in parallel where possible
    public let parallel: Bool
    
    /// Maximum parallel exports
    public let maxParallel: Int
    
    public init(
        sourceTimeRange: TimeRange? = nil,
        outputs: [ExportConfiguration],
        parallel: Bool = true,
        maxParallel: Int = 3
    ) {
        self.sourceTimeRange = sourceTimeRange
        self.outputs = outputs
        self.parallel = parallel
        self.maxParallel = maxParallel
    }
    
    /// Social media bundle (YouTube, TikTok, Instagram)
    public static func socialBundle(quality: ExportQuality = .high) -> MultiOutputConfiguration {
        MultiOutputConfiguration(
            outputs: [
                ExportConfiguration(preset: .youtube1080p, quality: quality),
                ExportConfiguration(preset: .tiktok, quality: quality, reframingMode: .smart),
                ExportConfiguration(preset: .instagramReels, quality: quality, reframingMode: .smart),
                ExportConfiguration(preset: .instagramFeed, quality: quality, reframingMode: .centerCrop)
            ]
        )
    }
}
