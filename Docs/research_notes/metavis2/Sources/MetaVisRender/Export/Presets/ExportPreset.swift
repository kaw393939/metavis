// ExportPreset.swift
// MetaVisRender
//
// Created for Sprint 13: Export & Delivery
// Platform-specific encoding configurations

import Foundation
import AVFoundation
import VideoToolbox

// MARK: - VideoCodec Export Extensions

/// Extensions to VideoCodec for export functionality
extension VideoCodec {
    /// CMVideoCodecType for VideoToolbox encoding
    public var codecType: CMVideoCodecType {
        switch self {
        case .h264: return kCMVideoCodecType_H264
        case .hevc: return kCMVideoCodecType_HEVC
        case .prores422: return kCMVideoCodecType_AppleProRes422
        case .prores422HQ: return kCMVideoCodecType_AppleProRes422HQ
        case .prores4444: return kCMVideoCodecType_AppleProRes4444
        case .prores422Proxy: return kCMVideoCodecType_AppleProRes422Proxy
        case .prores422LT: return kCMVideoCodecType_AppleProRes422LT
        case .prores4444XQ: return kCMVideoCodecType_AppleProRes4444XQ
        case .proresRAW: return kCMVideoCodecType_AppleProRes4444  // Use 4444 as fallback
        case .hevcWithAlpha: return kCMVideoCodecType_HEVC
        case .av1: return kCMVideoCodecType_H264  // Fallback, AV1 needs custom handling
        case .jpeg, .mjpeg: return kCMVideoCodecType_JPEG
        case .unknown: return kCMVideoCodecType_H264
        }
    }
    
    /// AVVideoCodecType for AVAssetWriter
    public var avCodecType: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .hevc, .hevcWithAlpha: return .hevc
        case .prores422: return .proRes422
        case .prores422HQ: return .proRes422HQ
        case .prores4444, .prores4444XQ: return .proRes4444
        case .prores422Proxy: return .proRes422Proxy
        case .prores422LT: return .proRes422LT
        case .proresRAW: return .proRes4444  // Use 4444 as fallback
        case .av1: return .h264  // Fallback
        case .jpeg, .mjpeg: return .jpeg
        case .unknown: return .h264
        }
    }
    
    /// Whether the codec is lossy
    public var isLossy: Bool {
        switch self {
        case .h264, .hevc, .hevcWithAlpha, .av1, .jpeg, .mjpeg:
            return true
        default:
            return false
        }
    }
}

// MARK: - AudioCodec Export Extensions

/// Extensions to AudioCodec for export functionality
extension AudioCodec {
    /// AudioFormatID for Core Audio/AVFoundation
    public var formatID: AudioFormatID {
        switch self {
        case .aac, .aacLC: return kAudioFormatMPEG4AAC
        case .aacHE: return kAudioFormatMPEG4AAC_HE
        case .pcmS16LE, .pcmS24LE, .pcmS32LE, .pcmFloat: return kAudioFormatLinearPCM
        case .alac: return kAudioFormatAppleLossless
        case .flac: return kAudioFormatFLAC
        case .mp3: return kAudioFormatMPEGLayer3
        case .ac3: return kAudioFormatAC3
        case .eac3: return kAudioFormatEnhancedAC3
        case .opus: return kAudioFormatOpus
        case .unknown: return kAudioFormatMPEG4AAC
        }
    }
}

// MARK: - ContainerFormat Export Extensions

extension ContainerFormat {
    /// AVFoundation file type for this container
    public var fileType: AVFileType {
        switch self {
        case .mp4: return .mp4
        case .mov: return .mov
        case .m4v: return .m4v
        case .m4a: return .m4a
        case .wav: return .wav
        case .mp3: return AVFileType(rawValue: "public.mp3")
        case .aiff: return .aiff
        case .webm: return AVFileType(rawValue: "org.webmproject.webm")
        case .mkv: return AVFileType(rawValue: "org.matroska.mkv")
        case .avi: return AVFileType(rawValue: "public.avi")
        case .unknown: return .mov
        }
    }
    
    /// File extension for this container
    public var fileExtension: String {
        rawValue
    }
}

// MARK: - AspectRatio

/// Common aspect ratios for video export
public struct AspectRatio: Codable, Sendable, Hashable, CustomStringConvertible {
    public let width: Int
    public let height: Int
    
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
    
    public var ratio: Double {
        Double(width) / Double(height)
    }
    
    public var description: String {
        "\(width):\(height)"
    }
    
    // Standard aspect ratios
    public static let landscape16x9 = AspectRatio(width: 16, height: 9)
    public static let landscape4x3 = AspectRatio(width: 4, height: 3)
    public static let portrait9x16 = AspectRatio(width: 9, height: 16)
    public static let portrait4x5 = AspectRatio(width: 4, height: 5)
    public static let square = AspectRatio(width: 1, height: 1)
    public static let cinemascope = AspectRatio(width: 2390, height: 1000)  // 2.39:1
    
    /// Whether this is a portrait orientation
    public var isPortrait: Bool {
        height > width
    }
    
    /// Whether this is a landscape orientation
    public var isLandscape: Bool {
        width > height
    }
}

// MARK: - ExportResolution

/// Video resolution configuration for export
public struct ExportResolution: Codable, Sendable, Hashable, CustomStringConvertible {
    public let width: Int
    public let height: Int
    
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
    
    public var aspectRatio: Double {
        Double(width) / Double(height)
    }
    
    public var totalPixels: Int {
        width * height
    }
    
    public var description: String {
        "\(width)x\(height)"
    }
    
    // Standard resolutions
    public static let sd480p = ExportResolution(width: 854, height: 480)
    public static let hd720p = ExportResolution(width: 1280, height: 720)
    public static let fullHD1080p = ExportResolution(width: 1920, height: 1080)
    public static let qhd1440p = ExportResolution(width: 2560, height: 1440)
    public static let uhd4K = ExportResolution(width: 3840, height: 2160)
    public static let uhd8K = ExportResolution(width: 7680, height: 4320)
    
    // Portrait resolutions (for Stories/Reels/TikTok)
    public static let portrait1080x1920 = ExportResolution(width: 1080, height: 1920)
    public static let portrait1080x1350 = ExportResolution(width: 1080, height: 1350)  // IG Feed
    
    // Square
    public static let square1080 = ExportResolution(width: 1080, height: 1080)
    
    /// Scale resolution by factor
    public func scaled(by factor: Double) -> ExportResolution {
        ExportResolution(
            width: Int(Double(width) * factor),
            height: Int(Double(height) * factor)
        )
    }
    
    /// Fit within maximum dimension while preserving aspect ratio
    public func fit(within maxDimension: Int) -> ExportResolution {
        let maxCurrent = max(width, height)
        if maxCurrent <= maxDimension {
            return self
        }
        let scale = Double(maxDimension) / Double(maxCurrent)
        return scaled(by: scale)
    }
}

// MARK: - VideoEncodingSettings

/// Video encoding configuration for export
public struct VideoEncodingSettings: Codable, Sendable {
    /// Video codec (uses existing VideoCodec from IngestionTypes)
    public let codec: VideoCodec
    
    /// Target bitrate in bits per second
    public let bitrate: Int
    
    /// Maximum bitrate for VBR encoding
    public let maxBitrate: Int?
    
    /// Keyframe interval in seconds
    public let keyframeInterval: Double
    
    /// B-frame count (0 = no B-frames)
    public let bFrameCount: Int
    
    /// H.264/HEVC profile
    public let profile: String?
    
    /// H.264/HEVC level
    public let level: String?
    
    /// Color primaries
    public let colorPrimaries: String?
    
    /// Transfer function
    public let transferFunction: String?
    
    /// Color matrix
    public let colorMatrix: String?
    
    /// Enable hardware acceleration
    public let hardwareAccelerated: Bool
    
    /// Two-pass encoding
    public let twoPass: Bool
    
    public init(
        codec: VideoCodec = .h264,
        bitrate: Int = 8_000_000,
        maxBitrate: Int? = nil,
        keyframeInterval: Double = 2.0,
        bFrameCount: Int = 2,
        profile: String? = nil,
        level: String? = nil,
        colorPrimaries: String? = nil,
        transferFunction: String? = nil,
        colorMatrix: String? = nil,
        hardwareAccelerated: Bool = true,
        twoPass: Bool = false
    ) {
        self.codec = codec
        self.bitrate = bitrate
        self.maxBitrate = maxBitrate
        self.keyframeInterval = keyframeInterval
        self.bFrameCount = bFrameCount
        self.profile = profile
        self.level = level
        self.colorPrimaries = colorPrimaries
        self.transferFunction = transferFunction
        self.colorMatrix = colorMatrix
        self.hardwareAccelerated = hardwareAccelerated
        self.twoPass = twoPass
    }
    
    /// AVFoundation video settings dictionary
    public func toAVSettings(resolution: ExportResolution) -> [String: Any] {
        var settings: [String: Any] = [
            AVVideoCodecKey: codec.avCodecType,
            AVVideoWidthKey: resolution.width,
            AVVideoHeightKey: resolution.height
        ]
        
        // Compression properties for lossy codecs
        if codec.isLossy {
            var compressionProperties: [String: Any] = [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoMaxKeyFrameIntervalDurationKey: keyframeInterval
            ]
            
            if let profile = profile {
                compressionProperties[AVVideoProfileLevelKey] = profile
            }
            
            settings[AVVideoCompressionPropertiesKey] = compressionProperties
        }
        
        return settings
    }
}

// MARK: - AudioEncodingSettings

/// Audio encoding configuration for export
public struct AudioEncodingSettings: Codable, Sendable {
    /// Audio codec (uses existing AudioCodec from IngestionTypes)
    public let codec: AudioCodec
    
    /// Sample rate in Hz
    public let sampleRate: Double
    
    /// Channel count
    public let channelCount: Int
    
    /// Bitrate in bits per second (for lossy codecs)
    public let bitrate: Int?
    
    /// Bit depth (for PCM)
    public let bitDepth: Int
    
    public init(
        codec: AudioCodec = .aac,
        sampleRate: Double = 48000,
        channelCount: Int = 2,
        bitrate: Int? = 256000,
        bitDepth: Int = 16
    ) {
        self.codec = codec
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitrate = bitrate
        self.bitDepth = bitDepth
    }
    
    /// AVFoundation audio settings dictionary
    public func toAVSettings() -> [String: Any] {
        var settings: [String: Any] = [
            AVFormatIDKey: codec.formatID,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount
        ]
        
        switch codec {
        case .aac, .aacLC, .aacHE, .mp3:
            if let bitrate = bitrate {
                settings[AVEncoderBitRateKey] = bitrate
            }
            settings[AVEncoderAudioQualityKey] = AVAudioQuality.max.rawValue
            
        case .pcmS16LE, .pcmS24LE, .pcmS32LE, .pcmFloat:
            settings[AVLinearPCMBitDepthKey] = bitDepth
            settings[AVLinearPCMIsBigEndianKey] = false
            settings[AVLinearPCMIsFloatKey] = (codec == .pcmFloat)
            settings[AVLinearPCMIsNonInterleaved] = false
            
        case .alac, .flac:
            settings[AVEncoderBitDepthHintKey] = bitDepth
            
        default:
            break
        }
        
        return settings
    }
    
    // Common presets
    public static let standard = AudioEncodingSettings()
    
    public static let highQuality = AudioEncodingSettings(
        codec: .aac,
        sampleRate: 48000,
        channelCount: 2,
        bitrate: 320000
    )
    
    public static let broadcast = AudioEncodingSettings(
        codec: .pcmS24LE,
        sampleRate: 48000,
        channelCount: 2,
        bitDepth: 24
    )
}

// MARK: - ExportPlatform

/// Target platform for export
public enum ExportPlatform: String, Codable, Sendable, CaseIterable {
    case youtube
    case youtubeShorts
    case instagramFeed
    case instagramStory
    case instagramReels
    case tiktok
    case twitter
    case linkedin
    case facebook
    case vimeo
    case broadcastHD
    case broadcast4K
    case web
    case archive
    case custom
    
    public var displayName: String {
        switch self {
        case .youtube: return "YouTube"
        case .youtubeShorts: return "YouTube Shorts"
        case .instagramFeed: return "Instagram Feed"
        case .instagramStory: return "Instagram Story"
        case .instagramReels: return "Instagram Reels"
        case .tiktok: return "TikTok"
        case .twitter: return "Twitter/X"
        case .linkedin: return "LinkedIn"
        case .facebook: return "Facebook"
        case .vimeo: return "Vimeo"
        case .broadcastHD: return "Broadcast HD"
        case .broadcast4K: return "Broadcast 4K"
        case .web: return "Web"
        case .archive: return "Archive"
        case .custom: return "Custom"
        }
    }
    
    public var maxDuration: TimeInterval? {
        switch self {
        case .youtubeShorts: return 60
        case .instagramStory: return 60
        case .instagramReels: return 90
        case .tiktok: return 180
        case .twitter: return 140
        default: return nil
        }
    }
    
    public var maxFileSize: Int64? {  // in bytes
        switch self {
        case .twitter: return 512 * 1024 * 1024  // 512 MB
        case .linkedin: return 5 * 1024 * 1024 * 1024  // 5 GB
        default: return nil
        }
    }
}

// MARK: - ExportPreset

/// Complete export configuration preset
public struct ExportPreset: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let platform: ExportPlatform
    public let resolution: ExportResolution
    public let aspectRatio: AspectRatio
    public let frameRate: Double
    public let container: ContainerFormat
    public let video: VideoEncodingSettings
    public let audio: AudioEncodingSettings
    public let pixelAspectRatio: Double
    public let interlaced: Bool
    public let hdr: Bool
    
    public init(
        id: String,
        name: String,
        platform: ExportPlatform,
        resolution: ExportResolution,
        aspectRatio: AspectRatio,
        frameRate: Double,
        container: ContainerFormat,
        video: VideoEncodingSettings,
        audio: AudioEncodingSettings,
        pixelAspectRatio: Double = 1.0,
        interlaced: Bool = false,
        hdr: Bool = false
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.resolution = resolution
        self.aspectRatio = aspectRatio
        self.frameRate = frameRate
        self.container = container
        self.video = video
        self.audio = audio
        self.pixelAspectRatio = pixelAspectRatio
        self.interlaced = interlaced
        self.hdr = hdr
    }
    
    /// Estimated output file size in bytes
    public func estimatedFileSize(duration: TimeInterval) -> Int64 {
        let videoBits = Int64(video.bitrate) * Int64(duration)
        let audioBits = Int64(audio.bitrate ?? 128000) * Int64(duration)
        return (videoBits + audioBits) / 8
    }
}

// MARK: - Preset Library

extension ExportPreset {
    
    // MARK: - YouTube Presets
    
    public static let youtube1080p = ExportPreset(
        id: "youtube-1080p",
        name: "YouTube 1080p HD",
        platform: .youtube,
        resolution: .fullHD1080p,
        aspectRatio: .landscape16x9,
        frameRate: 30,
        container: .mp4,
        video: VideoEncodingSettings(
            codec: .h264,
            bitrate: 8_000_000,
            keyframeInterval: 2.0,
            profile: AVVideoProfileLevelH264HighAutoLevel
        ),
        audio: AudioEncodingSettings(
            codec: .aac,
            sampleRate: 48000,
            bitrate: 384000
        )
    )
    
    public static let youtube4K = ExportPreset(
        id: "youtube-4k",
        name: "YouTube 4K UHD",
        platform: .youtube,
        resolution: .uhd4K,
        aspectRatio: .landscape16x9,
        frameRate: 30,
        container: .mp4,
        video: VideoEncodingSettings(
            codec: .hevc,
            bitrate: 35_000_000,
            keyframeInterval: 2.0
        ),
        audio: AudioEncodingSettings(
            codec: .aac,
            sampleRate: 48000,
            bitrate: 384000
        )
    )
    
    public static let youtubeShorts = ExportPreset(
        id: "youtube-shorts",
        name: "YouTube Shorts",
        platform: .youtubeShorts,
        resolution: .portrait1080x1920,
        aspectRatio: .portrait9x16,
        frameRate: 30,
        container: .mp4,
        video: VideoEncodingSettings(
            codec: .h264,
            bitrate: 6_000_000,
            keyframeInterval: 2.0
        ),
        audio: AudioEncodingSettings(
            codec: .aac,
            sampleRate: 48000,
            bitrate: 256000
        )
    )
    
    // MARK: - Instagram Presets
    
    public static let instagramFeed = ExportPreset(
        id: "instagram-feed",
        name: "Instagram Feed",
        platform: .instagramFeed,
        resolution: .portrait1080x1350,
        aspectRatio: .portrait4x5,
        frameRate: 30,
        container: .mp4,
        video: VideoEncodingSettings(
            codec: .h264,
            bitrate: 5_000_000,
            keyframeInterval: 2.0
        ),
        audio: AudioEncodingSettings(
            codec: .aac,
            sampleRate: 48000,
            bitrate: 256000
        )
    )
    
    public static let instagramStory = ExportPreset(
        id: "instagram-story",
        name: "Instagram Story",
        platform: .instagramStory,
        resolution: .portrait1080x1920,
        aspectRatio: .portrait9x16,
        frameRate: 30,
        container: .mp4,
        video: VideoEncodingSettings(
            codec: .h264,
            bitrate: 6_000_000,
            keyframeInterval: 2.0
        ),
        audio: AudioEncodingSettings(
            codec: .aac,
            sampleRate: 48000,
            bitrate: 256000
        )
    )
    
    public static let instagramReels = ExportPreset(
        id: "instagram-reels",
        name: "Instagram Reels",
        platform: .instagramReels,
        resolution: .portrait1080x1920,
        aspectRatio: .portrait9x16,
        frameRate: 30,
        container: .mp4,
        video: VideoEncodingSettings(
            codec: .h264,
            bitrate: 6_000_000,
            keyframeInterval: 2.0
        ),
        audio: AudioEncodingSettings(
            codec: .aac,
            sampleRate: 48000,
            bitrate: 256000
        )
    )
    
    // MARK: - TikTok Presets
    
    public static let tiktok = ExportPreset(
        id: "tiktok",
        name: "TikTok",
        platform: .tiktok,
        resolution: .portrait1080x1920,
        aspectRatio: .portrait9x16,
        frameRate: 30,
        container: .mp4,
        video: VideoEncodingSettings(
            codec: .h264,
            bitrate: 6_000_000,
            keyframeInterval: 2.0
        ),
        audio: AudioEncodingSettings(
            codec: .aac,
            sampleRate: 48000,
            bitrate: 256000
        )
    )
    
    // MARK: - Twitter/X Presets
    
    public static let twitter = ExportPreset(
        id: "twitter",
        name: "Twitter/X",
        platform: .twitter,
        resolution: .fullHD1080p,
        aspectRatio: .landscape16x9,
        frameRate: 30,
        container: .mp4,
        video: VideoEncodingSettings(
            codec: .h264,
            bitrate: 5_000_000,
            keyframeInterval: 2.0
        ),
        audio: AudioEncodingSettings(
            codec: .aac,
            sampleRate: 44100,
            bitrate: 192000
        )
    )
    
    // MARK: - LinkedIn Presets
    
    public static let linkedin = ExportPreset(
        id: "linkedin",
        name: "LinkedIn",
        platform: .linkedin,
        resolution: .fullHD1080p,
        aspectRatio: .landscape16x9,
        frameRate: 30,
        container: .mp4,
        video: VideoEncodingSettings(
            codec: .h264,
            bitrate: 8_000_000,
            keyframeInterval: 2.0
        ),
        audio: AudioEncodingSettings(
            codec: .aac,
            sampleRate: 48000,
            bitrate: 256000
        )
    )
    
    // MARK: - Broadcast Presets
    
    public static let broadcastHD = ExportPreset(
        id: "broadcast-hd",
        name: "Broadcast HD (1080i/p)",
        platform: .broadcastHD,
        resolution: .fullHD1080p,
        aspectRatio: .landscape16x9,
        frameRate: 29.97,
        container: .mov,
        video: VideoEncodingSettings(
            codec: .prores422HQ,
            bitrate: 220_000_000
        ),
        audio: AudioEncodingSettings(
            codec: .pcmS24LE,
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24
        )
    )
    
    public static let broadcast4K = ExportPreset(
        id: "broadcast-4k",
        name: "Broadcast 4K UHD",
        platform: .broadcast4K,
        resolution: .uhd4K,
        aspectRatio: .landscape16x9,
        frameRate: 29.97,
        container: .mov,
        video: VideoEncodingSettings(
            codec: .prores422HQ,
            bitrate: 880_000_000
        ),
        audio: AudioEncodingSettings(
            codec: .pcmS24LE,
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24
        )
    )
    
    // MARK: - Web Presets
    
    public static let web720p = ExportPreset(
        id: "web-720p",
        name: "Web 720p",
        platform: .web,
        resolution: .hd720p,
        aspectRatio: .landscape16x9,
        frameRate: 30,
        container: .mp4,
        video: VideoEncodingSettings(
            codec: .h264,
            bitrate: 3_000_000,
            keyframeInterval: 2.0
        ),
        audio: AudioEncodingSettings(
            codec: .aac,
            sampleRate: 44100,
            bitrate: 128000
        )
    )
    
    public static let web1080p = ExportPreset(
        id: "web-1080p",
        name: "Web 1080p",
        platform: .web,
        resolution: .fullHD1080p,
        aspectRatio: .landscape16x9,
        frameRate: 30,
        container: .mp4,
        video: VideoEncodingSettings(
            codec: .h264,
            bitrate: 5_000_000,
            keyframeInterval: 2.0
        ),
        audio: AudioEncodingSettings(
            codec: .aac,
            sampleRate: 44100,
            bitrate: 192000
        )
    )
    
    // MARK: - Archive Presets
    
    public static let archiveProRes = ExportPreset(
        id: "archive-prores",
        name: "Archive ProRes 4444",
        platform: .archive,
        resolution: .fullHD1080p,
        aspectRatio: .landscape16x9,
        frameRate: 24,
        container: .mov,
        video: VideoEncodingSettings(
            codec: .prores4444,
            bitrate: 330_000_000
        ),
        audio: AudioEncodingSettings(
            codec: .pcmS24LE,
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24
        )
    )
    
    public static let archive4K = ExportPreset(
        id: "archive-4k",
        name: "Archive 4K ProRes",
        platform: .archive,
        resolution: .uhd4K,
        aspectRatio: .landscape16x9,
        frameRate: 24,
        container: .mov,
        video: VideoEncodingSettings(
            codec: .prores422HQ,
            bitrate: 880_000_000
        ),
        audio: AudioEncodingSettings(
            codec: .alac,
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24
        )
    )
    
    // MARK: - All Presets
    
    public static let allPresets: [ExportPreset] = [
        .youtube1080p,
        .youtube4K,
        .youtubeShorts,
        .instagramFeed,
        .instagramStory,
        .instagramReels,
        .tiktok,
        .twitter,
        .linkedin,
        .broadcastHD,
        .broadcast4K,
        .web720p,
        .web1080p,
        .archiveProRes,
        .archive4K
    ]
    
    /// Find preset by ID
    public static func preset(withID id: String) -> ExportPreset? {
        allPresets.first { $0.id == id }
    }
    
    /// Find presets for platform
    public static func presets(for platform: ExportPlatform) -> [ExportPreset] {
        allPresets.filter { $0.platform == platform }
    }
}

// MARK: - Preset Customization

extension ExportPreset {
    /// Create a custom preset with modified settings
    public func with(
        resolution: ExportResolution? = nil,
        frameRate: Double? = nil,
        videoBitrate: Int? = nil,
        audioCodec: AudioCodec? = nil,
        audioBitrate: Int? = nil
    ) -> ExportPreset {
        ExportPreset(
            id: "\(id)-custom",
            name: "\(name) (Custom)",
            platform: platform,
            resolution: resolution ?? self.resolution,
            aspectRatio: aspectRatio,
            frameRate: frameRate ?? self.frameRate,
            container: container,
            video: VideoEncodingSettings(
                codec: video.codec,
                bitrate: videoBitrate ?? video.bitrate,
                maxBitrate: video.maxBitrate,
                keyframeInterval: video.keyframeInterval,
                bFrameCount: video.bFrameCount,
                profile: video.profile,
                level: video.level,
                colorPrimaries: video.colorPrimaries,
                transferFunction: video.transferFunction,
                colorMatrix: video.colorMatrix,
                hardwareAccelerated: video.hardwareAccelerated,
                twoPass: video.twoPass
            ),
            audio: AudioEncodingSettings(
                codec: audioCodec ?? audio.codec,
                sampleRate: audio.sampleRate,
                channelCount: audio.channelCount,
                bitrate: audioBitrate ?? audio.bitrate,
                bitDepth: audio.bitDepth
            ),
            pixelAspectRatio: pixelAspectRatio,
            interlaced: interlaced,
            hdr: hdr
        )
    }
}
