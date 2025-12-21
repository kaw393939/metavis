// Sources/MetaVisRender/Ingestion/Core/IngestionTypes.swift
// Sprint 03: Core types for AI Video Ingestion

import Foundation
import simd
import CoreMedia

// MARK: - Video Codecs

/// Supported video codecs
public enum VideoCodec: String, Codable, Sendable, CaseIterable {
    case h264 = "avc1"
    case hevc = "hvc1"
    case hevcWithAlpha = "muxa"
    case prores422 = "apcn"
    case prores422HQ = "apch"
    case prores422LT = "apcs"
    case prores422Proxy = "apco"
    case prores4444 = "ap4h"
    case prores4444XQ = "ap4x"
    case proresRAW = "aprn"
    case av1 = "av01"
    case jpeg = "jpeg"
    case mjpeg = "mjpa"
    case unknown = "unknown"
    
    public var displayName: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC (H.265)"
        case .hevcWithAlpha: return "HEVC with Alpha"
        case .prores422: return "ProRes 422"
        case .prores422HQ: return "ProRes 422 HQ"
        case .prores422LT: return "ProRes 422 LT"
        case .prores422Proxy: return "ProRes 422 Proxy"
        case .prores4444: return "ProRes 4444"
        case .prores4444XQ: return "ProRes 4444 XQ"
        case .proresRAW: return "ProRes RAW"
        case .av1: return "AV1"
        case .jpeg: return "JPEG"
        case .mjpeg: return "Motion JPEG"
        case .unknown: return "Unknown"
        }
    }
    
    public var isProRes: Bool {
        switch self {
        case .prores422, .prores422HQ, .prores422LT, .prores422Proxy,
             .prores4444, .prores4444XQ, .proresRAW:
            return true
        default:
            return false
        }
    }
    
    public static func from(fourCC: String) -> VideoCodec {
        let normalized = fourCC.trimmingCharacters(in: .whitespaces).lowercased()
        return VideoCodec.allCases.first { $0.rawValue.lowercased() == normalized } ?? .unknown
    }
}

// MARK: - Audio Codecs

/// Supported audio codecs
public enum AudioCodec: String, Codable, Sendable, CaseIterable {
    case aac = "aac"
    case aacLC = "aac-lc"
    case aacHE = "aac-he"
    case pcmS16LE = "pcm_s16le"
    case pcmS24LE = "pcm_s24le"
    case pcmS32LE = "pcm_s32le"
    case pcmFloat = "pcm_f32le"
    case alac = "alac"
    case mp3 = "mp3"
    case opus = "opus"
    case flac = "flac"
    case ac3 = "ac3"
    case eac3 = "eac3"
    case unknown = "unknown"
    
    public var displayName: String {
        switch self {
        case .aac, .aacLC: return "AAC-LC"
        case .aacHE: return "AAC-HE"
        case .pcmS16LE: return "PCM 16-bit"
        case .pcmS24LE: return "PCM 24-bit"
        case .pcmS32LE: return "PCM 32-bit"
        case .pcmFloat: return "PCM Float"
        case .alac: return "Apple Lossless"
        case .mp3: return "MP3"
        case .opus: return "Opus"
        case .flac: return "FLAC"
        case .ac3: return "Dolby Digital"
        case .eac3: return "Dolby Digital Plus"
        case .unknown: return "Unknown"
        }
    }
    
    public var isLossless: Bool {
        switch self {
        case .pcmS16LE, .pcmS24LE, .pcmS32LE, .pcmFloat, .alac, .flac:
            return true
        default:
            return false
        }
    }
}

// MARK: - Container Formats

/// Media container formats
public enum ContainerFormat: String, Codable, Sendable {
    case mov = "mov"
    case mp4 = "mp4"
    case m4v = "m4v"
    case m4a = "m4a"
    case wav = "wav"
    case mp3 = "mp3"
    case aiff = "aiff"
    case webm = "webm"
    case mkv = "mkv"
    case avi = "avi"
    case unknown = "unknown"
    
    public static func from(pathExtension: String) -> ContainerFormat {
        switch pathExtension.lowercased() {
        case "mov": return .mov
        case "mp4": return .mp4
        case "m4v": return .m4v
        case "m4a": return .m4a
        case "wav": return .wav
        case "mp3": return .mp3
        case "aiff", "aif": return .aiff
        case "webm": return .webm
        case "mkv": return .mkv
        case "avi": return .avi
        default: return .unknown
        }
    }
}

// MARK: - Color Space

/// Color primaries / gamut
public enum ColorPrimaries: String, Codable, Sendable {
    case bt709 = "ITU_R_709_2"
    case bt2020 = "ITU_R_2020"
    case p3DCI = "P3_DCI"
    case p3D65 = "P3_D65"
    case sRGB = "sRGB"
    case adobeRGB = "AdobeRGB"
    case unknown = "unknown"
    
    public var displayName: String {
        switch self {
        case .bt709: return "BT.709 (SDR)"
        case .bt2020: return "BT.2020 (HDR/WCG)"
        case .p3DCI: return "DCI-P3"
        case .p3D65: return "Display P3"
        case .sRGB: return "sRGB"
        case .adobeRGB: return "Adobe RGB"
        case .unknown: return "Unknown"
        }
    }
    
    public var isWideGamut: Bool {
        switch self {
        case .bt2020, .p3DCI, .p3D65, .adobeRGB:
            return true
        default:
            return false
        }
    }
}

// MARK: - Transfer Function

/// OETF / Transfer characteristics
public enum TransferFunction: String, Codable, Sendable {
    case bt709 = "ITU_R_709_2"
    case sRGB = "sRGB"
    case linear = "Linear"
    case pq = "SMPTE_ST_2084_PQ"      // HDR10, Dolby Vision
    case hlg = "ITU_R_2100_HLG"        // HLG HDR
    case gamma22 = "Gamma_2_2"
    case gamma28 = "Gamma_2_8"
    case log = "Log"
    case slog3 = "SLog3"
    case appleLog = "AppleLog"
    case unknown = "unknown"
    
    public var displayName: String {
        switch self {
        case .bt709: return "BT.709"
        case .sRGB: return "sRGB"
        case .linear: return "Linear"
        case .pq: return "PQ (HDR10)"
        case .hlg: return "HLG"
        case .gamma22: return "Gamma 2.2"
        case .gamma28: return "Gamma 2.8"
        case .log: return "Log"
        case .slog3: return "S-Log3"
        case .appleLog: return "Apple Log"
        case .unknown: return "Unknown"
        }
    }
    
    public var isHDR: Bool {
        switch self {
        case .pq, .hlg, .log, .slog3:
            return true
        default:
            return false
        }
    }
}

// MARK: - HDR Metadata

/// HDR static metadata (mastering display info)
public struct HDRMetadata: Codable, Sendable, Equatable {
    /// Mastering display peak luminance in nits
    public let maxDisplayMasteringLuminance: Float?
    /// Mastering display min luminance in nits
    public let minDisplayMasteringLuminance: Float?
    /// MaxCLL (Maximum Content Light Level) in nits
    public let maxContentLightLevel: Float?
    /// MaxFALL (Maximum Frame-Average Light Level) in nits
    public let maxFrameAverageLightLevel: Float?
    /// Mastering display color primaries (xy coordinates)
    public let displayPrimaries: [SIMD2<Float>]?
    /// White point (xy coordinates)
    public let whitePoint: SIMD2<Float>?
    
    public init(
        maxDisplayMasteringLuminance: Float? = nil,
        minDisplayMasteringLuminance: Float? = nil,
        maxContentLightLevel: Float? = nil,
        maxFrameAverageLightLevel: Float? = nil,
        displayPrimaries: [SIMD2<Float>]? = nil,
        whitePoint: SIMD2<Float>? = nil
    ) {
        self.maxDisplayMasteringLuminance = maxDisplayMasteringLuminance
        self.minDisplayMasteringLuminance = minDisplayMasteringLuminance
        self.maxContentLightLevel = maxContentLightLevel
        self.maxFrameAverageLightLevel = maxFrameAverageLightLevel
        self.displayPrimaries = displayPrimaries
        self.whitePoint = whitePoint
    }
    
    public var hasMetadata: Bool {
        maxDisplayMasteringLuminance != nil ||
        maxContentLightLevel != nil ||
        displayPrimaries != nil
    }
}

// MARK: - Color Space Info (Combined)

/// Complete color space information
public struct ColorSpaceInfo: Codable, Sendable, Equatable {
    public let primaries: ColorPrimaries
    public let transfer: TransferFunction
    public let matrix: String?  // YCbCr matrix (bt709, bt2020nc, etc.)
    public let range: ColorRange
    public let hdrMetadata: HDRMetadata?
    
    public init(
        primaries: ColorPrimaries = .bt709,
        transfer: TransferFunction = .bt709,
        matrix: String? = nil,
        range: ColorRange = .video,
        hdrMetadata: HDRMetadata? = nil
    ) {
        self.primaries = primaries
        self.transfer = transfer
        self.matrix = matrix
        self.range = range
        self.hdrMetadata = hdrMetadata
    }
    
    public var isHDR: Bool {
        transfer.isHDR || primaries.isWideGamut
    }
    
    public var isSDR: Bool {
        !isHDR
    }
    
    public static let sdr709 = ColorSpaceInfo(
        primaries: .bt709,
        transfer: .bt709,
        matrix: "ITU_R_709_2",
        range: .video
    )
}

/// Color value range
public enum ColorRange: String, Codable, Sendable {
    case video = "video"   // Limited range (16-235)
    case full = "full"     // Full range (0-255)
}

// MARK: - Video Track Info

/// Detailed video track information
public struct VideoTrackInfo: Codable, Sendable, Equatable {
    public let trackId: Int
    public let codec: VideoCodec
    public let width: Int
    public let height: Int
    public let fps: Double
    public let bitDepth: Int
    public let bitrate: Int?
    public let rotation: Int
    public let colorSpace: ColorSpaceInfo
    public let hasAlpha: Bool
    public let isInterlaced: Bool
    public let fieldOrder: FieldOrder?
    public let pixelAspectRatio: Float
    
    public init(
        trackId: Int = 1,
        codec: VideoCodec,
        width: Int,
        height: Int,
        fps: Double,
        bitDepth: Int = 8,
        bitrate: Int? = nil,
        rotation: Int = 0,
        colorSpace: ColorSpaceInfo = .sdr709,
        hasAlpha: Bool = false,
        isInterlaced: Bool = false,
        fieldOrder: FieldOrder? = nil,
        pixelAspectRatio: Float = 1.0
    ) {
        self.trackId = trackId
        self.codec = codec
        self.width = width
        self.height = height
        self.fps = fps
        self.bitDepth = bitDepth
        self.bitrate = bitrate
        self.rotation = rotation
        self.colorSpace = colorSpace
        self.hasAlpha = hasAlpha
        self.isInterlaced = isInterlaced
        self.fieldOrder = fieldOrder
        self.pixelAspectRatio = pixelAspectRatio
    }
    
    /// Effective display size after rotation
    public var effectiveSize: (width: Int, height: Int) {
        let absRotation = abs(rotation) % 360
        if absRotation == 90 || absRotation == 270 {
            return (height, width)
        }
        return (width, height)
    }
    
    /// Aspect ratio
    public var aspectRatio: Float {
        let (w, h) = effectiveSize
        guard h > 0 else { return 1.0 }
        return Float(w) / Float(h) * pixelAspectRatio
    }
    
    /// Is portrait orientation
    public var isPortrait: Bool {
        let (w, h) = effectiveSize
        return h > w
    }
}

/// Field order for interlaced content
public enum FieldOrder: String, Codable, Sendable {
    case topFirst = "top_first"
    case bottomFirst = "bottom_first"
    case progressive = "progressive"
}

// MARK: - Audio Track Info

/// Detailed audio track information
public struct AudioTrackInfo: Codable, Sendable, Equatable {
    public let trackId: Int
    public let codec: AudioCodec
    public let sampleRate: Int
    public let channels: Int
    public let channelLayout: ChannelLayout
    public let bitDepth: Int?
    public let bitrate: Int?
    public let language: String?
    public let title: String?
    
    public init(
        trackId: Int = 1,
        codec: AudioCodec,
        sampleRate: Int = 48000,
        channels: Int = 2,
        channelLayout: ChannelLayout = .stereo,
        bitDepth: Int? = nil,
        bitrate: Int? = nil,
        language: String? = nil,
        title: String? = nil
    ) {
        self.trackId = trackId
        self.codec = codec
        self.sampleRate = sampleRate
        self.channels = channels
        self.channelLayout = channelLayout
        self.bitDepth = bitDepth
        self.bitrate = bitrate
        self.language = language
        self.title = title
    }
    
    public var isStereo: Bool { channels == 2 }
    public var isMono: Bool { channels == 1 }
    public var isSurround: Bool { channels > 2 }
    public var isSpatial: Bool { channelLayout == .spatialAudio || channelLayout == .ambisonicsFirstOrder }
}

/// Audio channel layouts
public enum ChannelLayout: String, Codable, Sendable {
    case mono = "mono"
    case stereo = "stereo"
    case surround51 = "5.1"
    case surround71 = "7.1"
    case quadraphonic = "quad"
    case spatialAudio = "spatial"
    case ambisonicsFirstOrder = "ambisonic_1"
    case unknown = "unknown"
    
    public static func from(channels: Int, isSpatial: Bool = false) -> ChannelLayout {
        if isSpatial { return .spatialAudio }
        switch channels {
        case 1: return .mono
        case 2: return .stereo
        case 4: return .quadraphonic
        case 6: return .surround51
        case 8: return .surround71
        default: return .unknown
        }
    }
}

// MARK: - Timecode

/// SMPTE timecode
public struct Timecode: Codable, Sendable, Equatable, CustomStringConvertible {
    public let hours: Int
    public let minutes: Int
    public let seconds: Int
    public let frames: Int
    public let fps: Double
    public let isDropFrame: Bool
    
    public init(hours: Int, minutes: Int, seconds: Int, frames: Int, fps: Double, isDropFrame: Bool = false) {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.frames = frames
        self.fps = fps
        self.isDropFrame = isDropFrame
    }
    
    public init(seconds: Double, fps: Double, isDropFrame: Bool = false) {
        let totalFrames = Int(seconds * fps)
        let framesPerSecond = Int(fps.rounded())
        
        self.frames = totalFrames % framesPerSecond
        let totalSeconds = totalFrames / framesPerSecond
        self.seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        self.minutes = totalMinutes % 60
        self.hours = totalMinutes / 60
        self.fps = fps
        self.isDropFrame = isDropFrame
    }
    
    public var description: String {
        let separator = isDropFrame ? ";" : ":"
        return String(format: "%02d:%02d:%02d%@%02d", hours, minutes, seconds, separator, frames)
    }
    
    public var totalSeconds: Double {
        let framesPerSecond = fps.rounded()
        let totalFrames = Double(hours) * 3600 * framesPerSecond +
                          Double(minutes) * 60 * framesPerSecond +
                          Double(seconds) * framesPerSecond +
                          Double(frames)
        return totalFrames / fps
    }
}

// MARK: - Quality Flags

/// Detected quality issues
public struct QualityFlags: OptionSet, Codable, Sendable {
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    public static let underexposed = QualityFlags(rawValue: 1 << 0)
    public static let overexposed = QualityFlags(rawValue: 1 << 1)
    public static let lowContrast = QualityFlags(rawValue: 1 << 2)
    public static let noisy = QualityFlags(rawValue: 1 << 3)
    public static let blurry = QualityFlags(rawValue: 1 << 4)
    public static let shaky = QualityFlags(rawValue: 1 << 5)
    public static let audioClipping = QualityFlags(rawValue: 1 << 6)
    public static let lowBitrate = QualityFlags(rawValue: 1 << 7)
    public static let interlaced = QualityFlags(rawValue: 1 << 8)
    public static let variableFrameRate = QualityFlags(rawValue: 1 << 9)
    
    public var issues: [String] {
        var result: [String] = []
        if contains(.underexposed) { result.append("underexposed") }
        if contains(.overexposed) { result.append("overexposed") }
        if contains(.lowContrast) { result.append("low_contrast") }
        if contains(.noisy) { result.append("noisy") }
        if contains(.blurry) { result.append("blurry") }
        if contains(.shaky) { result.append("shaky") }
        if contains(.audioClipping) { result.append("audio_clipping") }
        if contains(.lowBitrate) { result.append("low_bitrate") }
        if contains(.interlaced) { result.append("interlaced") }
        if contains(.variableFrameRate) { result.append("variable_frame_rate") }
        return result
    }
}

// MARK: - Ingestion Errors

/// Errors during media ingestion
public enum IngestionError: Error, LocalizedError {
    case fileNotFound(URL)
    case unsupportedFormat(String)
    case noVideoTrack
    case noAudioTrack
    case corruptedFile(String)
    case codecNotSupported(String)
    case insufficientMemory
    case transcriptionFailed(String)
    case analysisTimeout
    case cancelled
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .unsupportedFormat(let format):
            return "Unsupported format: \(format)"
        case .noVideoTrack:
            return "No video track found"
        case .noAudioTrack:
            return "No audio track found"
        case .corruptedFile(let reason):
            return "Corrupted file: \(reason)"
        case .codecNotSupported(let codec):
            return "Codec not supported: \(codec)"
        case .insufficientMemory:
            return "Insufficient memory for operation"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .analysisTimeout:
            return "Analysis timed out"
        case .cancelled:
            return "Operation cancelled"
        }
    }
}

// MARK: - Ingestion Stage

/// Stages of the ingestion pipeline
public enum IngestionStage: String, Codable, Sendable, CaseIterable {
    case starting = "starting"
    case extractingMetadata = "extracting_metadata"
    case extractingAudio = "extracting_audio"
    case detectingSpeech = "detecting_speech"
    case transcribing = "transcribing"
    case diarizing = "diarizing"
    case analyzingVideo = "analyzing_video"
    case detectingScenes = "detecting_scenes"
    case generatingCaptions = "generating_captions"
    case buildingManifest = "building_manifest"
    case writingOutput = "writing_output"
    case complete = "complete"
    case failed = "failed"
    
    public var displayName: String {
        switch self {
        case .starting: return "Starting"
        case .extractingMetadata: return "Extracting metadata"
        case .extractingAudio: return "Extracting audio"
        case .detectingSpeech: return "Detecting speech"
        case .transcribing: return "Transcribing"
        case .diarizing: return "Identifying speakers"
        case .analyzingVideo: return "Analyzing video"
        case .detectingScenes: return "Detecting scenes"
        case .generatingCaptions: return "Generating captions"
        case .buildingManifest: return "Building manifest"
        case .writingOutput: return "Writing output"
        case .complete: return "Complete"
        case .failed: return "Failed"
        }
    }
}
