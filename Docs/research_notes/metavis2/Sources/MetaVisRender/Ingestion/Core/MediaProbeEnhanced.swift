// Sources/MetaVisRender/Ingestion/Core/MediaProbeEnhanced.swift
// Sprint 03: Enhanced media probing with full metadata extraction

import AVFoundation
import Foundation
import CoreMedia
import ImageIO

// MARK: - Enhanced Media Profile

/// Complete media profile with all tracks and metadata
public struct EnhancedMediaProfile: Codable, Sendable {
    public let id: UUID
    public let path: String
    public let filename: String
    public let fileSize: Int64
    public let container: ContainerFormat
    public let duration: Double
    public let creationDate: Date?
    
    // Tracks
    public let video: VideoTrackInfo?
    public let audioTracks: [AudioTrackInfo]
    
    // Timing
    public let startTimecode: Timecode?
    public let frameCount: Int?
    
    // Metadata
    public let title: String?
    public let author: String?
    public let copyright: String?
    public let comment: String?
    public let make: String?          // Camera manufacturer
    public let model: String?         // Camera model
    public let software: String?
    public let location: GeoLocation?
    
    public init(
        id: UUID = UUID(),
        path: String,
        filename: String,
        fileSize: Int64,
        container: ContainerFormat,
        duration: Double,
        creationDate: Date? = nil,
        video: VideoTrackInfo? = nil,
        audioTracks: [AudioTrackInfo] = [],
        startTimecode: Timecode? = nil,
        frameCount: Int? = nil,
        title: String? = nil,
        author: String? = nil,
        copyright: String? = nil,
        comment: String? = nil,
        make: String? = nil,
        model: String? = nil,
        software: String? = nil,
        location: GeoLocation? = nil
    ) {
        self.id = id
        self.path = path
        self.filename = filename
        self.fileSize = fileSize
        self.container = container
        self.duration = duration
        self.creationDate = creationDate
        self.video = video
        self.audioTracks = audioTracks
        self.startTimecode = startTimecode
        self.frameCount = frameCount
        self.title = title
        self.author = author
        self.copyright = copyright
        self.comment = comment
        self.make = make
        self.model = model
        self.software = software
        self.location = location
    }
    
    // MARK: Computed Properties
    
    public var hasVideo: Bool { video != nil }
    public var hasAudio: Bool { !audioTracks.isEmpty }
    public var isAudioOnly: Bool { !hasVideo && hasAudio }
    public var isVideoOnly: Bool { hasVideo && !hasAudio }
    
    public var primaryAudio: AudioTrackInfo? { audioTracks.first }
    
    public var aspectRatio: Float? { video?.aspectRatio }
    
    public var resolution: String? {
        guard let v = video else { return nil }
        let (w, h) = v.effectiveSize
        return "\(w)×\(h)"
    }
    
    public var durationFormatted: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        let millis = Int((duration.truncatingRemainder(dividingBy: 1)) * 1000)
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, millis)
        } else {
            return String(format: "%02d:%02d.%03d", minutes, seconds, millis)
        }
    }
    
    public var fileSizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}

// MARK: - Geo Location

public struct GeoLocation: Codable, Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double?
    
    public init(latitude: Double, longitude: Double, altitude: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }
}

// MARK: - Enhanced Media Probe

/// Enhanced media probe with comprehensive metadata extraction
public actor EnhancedMediaProbe {
    
    // MARK: - Public API
    
    /// Probe a media file and extract complete metadata
    public static func probe(_ url: URL) async throws -> EnhancedMediaProfile {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw IngestionError.fileNotFound(url)
        }
        
        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
        let container = ContainerFormat.from(pathExtension: url.pathExtension)
        
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])
        
        // Load basic properties
        let duration = try await asset.load(.duration).seconds
        let creationDateMeta = try? await asset.load(.creationDate)
        let creationDate = try? await creationDateMeta?.load(.dateValue)
        
        // Extract video track
        let videoInfo = try await extractVideoTrack(from: asset)
        
        // Extract audio tracks
        let audioInfos = try await extractAudioTracks(from: asset)
        
        // Extract timecode
        let timecode = try await extractTimecode(from: asset, fps: videoInfo?.fps ?? 30)
        
        // Calculate frame count
        let frameCount = videoInfo.map { Int(duration * $0.fps) }
        
        // Extract metadata
        let metadata = try await extractMetadata(from: asset)
        
        return EnhancedMediaProfile(
            path: url.path,
            filename: url.lastPathComponent,
            fileSize: fileSize,
            container: container,
            duration: duration,
            creationDate: creationDate,
            video: videoInfo,
            audioTracks: audioInfos,
            startTimecode: timecode,
            frameCount: frameCount,
            title: metadata.title,
            author: metadata.author,
            copyright: metadata.copyright,
            comment: metadata.comment,
            make: metadata.make,
            model: metadata.model,
            software: metadata.software,
            location: metadata.location
        )
    }
    
    // MARK: - Video Track Extraction
    
    private static func extractVideoTrack(from asset: AVAsset) async throws -> VideoTrackInfo? {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else { return nil }
        
        // Basic properties
        let naturalSize = try await track.load(.naturalSize)
        let frameRate = try await track.load(.nominalFrameRate)
        let transform = try await track.load(.preferredTransform)
        let trackId = track.trackID
        
        // Calculate rotation from transform
        let rotation = rotationFromTransform(transform)
        
        // Format descriptions for codec and color info
        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let formatDesc = formatDescriptions.first else {
            return VideoTrackInfo(
                trackId: Int(trackId),
                codec: .unknown,
                width: Int(naturalSize.width),
                height: Int(naturalSize.height),
                fps: Double(frameRate),
                rotation: rotation
            )
        }
        
        // Codec
        let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc)
        let codecString = fourCCToString(mediaSubType)
        let codec = VideoCodec.from(fourCC: codecString)
        
        // Bit depth
        let bitDepth = extractBitDepth(from: formatDesc)
        
        // Color space info
        let colorSpace = extractColorSpace(from: formatDesc)
        
        // Bitrate (estimated)
        let bitrate = try? await track.load(.estimatedDataRate)
        
        // Check for alpha
        let hasAlpha = codec == .hevcWithAlpha || codec == .prores4444 || codec == .prores4444XQ
        
        return VideoTrackInfo(
            trackId: Int(trackId),
            codec: codec,
            width: Int(naturalSize.width),
            height: Int(naturalSize.height),
            fps: Double(frameRate),
            bitDepth: bitDepth,
            bitrate: bitrate.map { Int($0) },
            rotation: rotation,
            colorSpace: colorSpace,
            hasAlpha: hasAlpha
        )
    }
    
    // MARK: - Audio Track Extraction
    
    private static func extractAudioTracks(from asset: AVAsset) async throws -> [AudioTrackInfo] {
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var result: [AudioTrackInfo] = []
        
        for track in audioTracks {
            let trackId = track.trackID
            let formatDescriptions = try await track.load(.formatDescriptions)
            
            guard let formatDesc = formatDescriptions.first else { continue }
            
            // Basic audio stream description
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee
            
            let sampleRate = Int(asbd?.mSampleRate ?? 48000)
            let channels = Int(asbd?.mChannelsPerFrame ?? 2)
            let bitsPerChannel = Int(asbd?.mBitsPerChannel ?? 0)
            
            // Codec
            let formatID = asbd?.mFormatID ?? 0
            let codec = audioCodecFromFormatID(formatID)
            
            // Channel layout
            var isSpatial = false
            if let layoutData = CMAudioFormatDescriptionGetChannelLayout(formatDesc, sizeOut: nil) {
                isSpatial = layoutData.pointee.mChannelLayoutTag == kAudioChannelLayoutTag_Ambisonic_B_Format
            }
            let channelLayout = ChannelLayout.from(channels: channels, isSpatial: isSpatial)
            
            // Bitrate
            let bitrate = try? await track.load(.estimatedDataRate)
            
            // Language
            let languageCode = try? await track.load(.languageCode)
            
            result.append(AudioTrackInfo(
                trackId: Int(trackId),
                codec: codec,
                sampleRate: sampleRate,
                channels: channels,
                channelLayout: channelLayout,
                bitDepth: bitsPerChannel > 0 ? bitsPerChannel : nil,
                bitrate: bitrate.map { Int($0) },
                language: languageCode
            ))
        }
        
        return result
    }
    
    // MARK: - Timecode Extraction
    
    private static func extractTimecode(from asset: AVAsset, fps: Double) async throws -> Timecode? {
        let timecodeTracks = try await asset.loadTracks(withMediaType: .timecode)
        guard let track = timecodeTracks.first else { return nil }
        
        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let formatDesc = formatDescriptions.first else { return nil }
        
        // Try to read the timecode
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        
        guard reader.startReading() else { return nil }
        
        guard let sampleBuffer = output.copyNextSampleBuffer() else {
            reader.cancelReading()
            return nil
        }
        
        reader.cancelReading()
        
        // Parse timecode from sample buffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        
        guard let pointer = dataPointer, length >= 4 else { return nil }
        
        // Timecode is typically stored as frame number
        let frameNumber = pointer.withMemoryRebound(to: UInt32.self, capacity: 1) { $0.pointee }
        let frames = Int(CFSwapInt32BigToHost(frameNumber))
        
        // Convert frame number to timecode
        let isDropFrame = fps == 29.97 || fps == 59.94
        
        return Timecode(seconds: Double(frames) / fps, fps: fps, isDropFrame: isDropFrame)
    }
    
    // MARK: - Metadata Extraction
    
    private struct ExtractedMetadata {
        var title: String?
        var author: String?
        var copyright: String?
        var comment: String?
        var make: String?
        var model: String?
        var software: String?
        var location: GeoLocation?
    }
    
    private static func extractMetadata(from asset: AVAsset) async throws -> ExtractedMetadata {
        var result = ExtractedMetadata()
        
        let metadata = try await asset.load(.metadata)
        
        for item in metadata {
            guard let key = item.commonKey?.rawValue ?? item.key as? String else { continue }
            let value = try? await item.load(.stringValue)
            
            switch key {
            case AVMetadataKey.commonKeyTitle.rawValue, "title":
                result.title = value
            case AVMetadataKey.commonKeyAuthor.rawValue, "author":
                result.author = value
            case AVMetadataKey.commonKeyCopyrights.rawValue:
                result.copyright = value
            case AVMetadataKey.commonKeyDescription.rawValue:
                result.comment = value
            case AVMetadataKey.commonKeyMake.rawValue, "com.apple.quicktime.make":
                result.make = value
            case AVMetadataKey.commonKeyModel.rawValue, "com.apple.quicktime.model":
                result.model = value
            case AVMetadataKey.commonKeySoftware.rawValue, "com.apple.quicktime.software":
                result.software = value
            case AVMetadataKey.commonKeyLocation.rawValue, "com.apple.quicktime.location.ISO6709":
                if let locString = value {
                    result.location = parseISO6709Location(locString)
                }
            default:
                break
            }
        }
        
        return result
    }
    
    // MARK: - Helper Functions
    
    private static func rotationFromTransform(_ transform: CGAffineTransform) -> Int {
        let angle = atan2(transform.b, transform.a)
        var degrees = Int(round(angle * 180 / .pi))
        
        // Normalize to common rotation values
        if degrees < 0 { degrees += 360 }
        
        // Map to standard rotations
        switch degrees {
        case 0..<45, 315..<360: return 0
        case 45..<135: return 90
        case 135..<225: return 180
        case 225..<315: return 270
        default: return 0
        }
    }
    
    private static func fourCCToString(_ code: FourCharCode) -> String {
        let n = Int(code)
        var s = String(UnicodeScalar((n >> 24) & 255)!)
        s.append(String(UnicodeScalar((n >> 16) & 255)!))
        s.append(String(UnicodeScalar((n >> 8) & 255)!))
        s.append(String(UnicodeScalar(n & 255)!))
        return s.trimmingCharacters(in: .whitespaces)
    }
    
    private static func extractBitDepth(from formatDesc: CMFormatDescription) -> Int {
        // Try to get bit depth from extensions
        if let extensions = CMFormatDescriptionGetExtensions(formatDesc) as? [String: Any] {
            if let depth = extensions[kCMFormatDescriptionExtension_Depth as String] as? Int {
                return depth
            }
            if let bitsPerComponent = extensions["BitsPerComponent"] as? Int {
                return bitsPerComponent
            }
        }
        
        // Check for 10-bit indicators in the codec
        let codecType = CMFormatDescriptionGetMediaSubType(formatDesc)
        let codecString = fourCCToString(codecType)
        
        // ProRes 4444 and some HEVC profiles are typically 10+ bit
        if codecString.contains("ap4") || codecString.contains("hvc1") {
            // Default to 10-bit for these formats, actual detection is more complex
            return 10
        }
        
        return 8  // Default to 8-bit
    }
    
    private static func extractColorSpace(from formatDesc: CMFormatDescription) -> ColorSpaceInfo {
        var primaries = ColorPrimaries.bt709
        var transfer = TransferFunction.bt709
        var matrix: String? = nil
        var range = ColorRange.video
        var hdrMetadata: HDRMetadata? = nil
        
        // Color primaries
        if let primariesExt = CMFormatDescriptionGetExtension(
            formatDesc,
            extensionKey: kCMFormatDescriptionExtension_ColorPrimaries
        ) as? String {
            switch primariesExt {
            case "ITU_R_709_2": primaries = .bt709
            case "ITU_R_2020": primaries = .bt2020
            case "P3_D65", "DCI_P3": primaries = .p3D65
            default: break
            }
        }
        
        // Transfer function
        if let transferExt = CMFormatDescriptionGetExtension(
            formatDesc,
            extensionKey: kCMFormatDescriptionExtension_TransferFunction
        ) as? String {
            switch transferExt {
            case "ITU_R_709_2": transfer = .bt709
            case "SMPTE_ST_2084_PQ": transfer = .pq
            case "ITU_R_2100_HLG", "ARIB_STD_B67": transfer = .hlg
            case "sRGB": transfer = .sRGB
            case "Linear": transfer = .linear
            case "AppleLog", "com.apple.log": transfer = .appleLog
            default: break
            }
        }
        
        // YCbCr Matrix
        if let matrixExt = CMFormatDescriptionGetExtension(
            formatDesc,
            extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix
        ) as? String {
            matrix = matrixExt
        }
        
        // Full range flag
        if let fullRange = CMFormatDescriptionGetExtension(
            formatDesc,
            extensionKey: kCMFormatDescriptionExtension_FullRangeVideo
        ) as? Bool {
            range = fullRange ? .full : .video
        }
        
        // HDR metadata (for HDR10)
        if transfer == .pq || transfer == .hlg {
            hdrMetadata = extractHDRMetadata(from: formatDesc)
        }
        
        return ColorSpaceInfo(
            primaries: primaries,
            transfer: transfer,
            matrix: matrix,
            range: range,
            hdrMetadata: hdrMetadata
        )
    }
    
    private static func extractHDRMetadata(from formatDesc: CMFormatDescription) -> HDRMetadata? {
        guard let extensions = CMFormatDescriptionGetExtensions(formatDesc) as? [String: Any] else {
            return nil
        }
        
        var maxDisplay: Float? = nil
        var minDisplay: Float? = nil
        var maxCLL: Float? = nil
        var maxFALL: Float? = nil
        
        // Mastering display metadata
        if let masteringDisplay = extensions["MasteringDisplayColorVolume"] as? [String: Any] {
            maxDisplay = masteringDisplay["MaxDisplayMasteringLuminance"] as? Float
            minDisplay = masteringDisplay["MinDisplayMasteringLuminance"] as? Float
        }
        
        // Content light level
        if let contentLight = extensions["ContentLightLevelInfo"] as? [String: Any] {
            maxCLL = contentLight["MaxContentLightLevel"] as? Float
            maxFALL = contentLight["MaxFrameAverageLightLevel"] as? Float
        }
        
        if maxDisplay != nil || maxCLL != nil {
            return HDRMetadata(
                maxDisplayMasteringLuminance: maxDisplay,
                minDisplayMasteringLuminance: minDisplay,
                maxContentLightLevel: maxCLL,
                maxFrameAverageLightLevel: maxFALL
            )
        }
        
        return nil
    }
    
    private static func audioCodecFromFormatID(_ formatID: AudioFormatID) -> AudioCodec {
        switch formatID {
        case kAudioFormatMPEG4AAC: return .aac
        case kAudioFormatMPEG4AAC_HE: return .aacHE
        case kAudioFormatLinearPCM: return .pcmS16LE
        case kAudioFormatAppleLossless: return .alac
        case kAudioFormatMPEGLayer3: return .mp3
        case kAudioFormatOpus: return .opus
        case kAudioFormatFLAC: return .flac
        case kAudioFormatAC3: return .ac3
        case kAudioFormatEnhancedAC3: return .eac3
        default: return .unknown
        }
    }
    
    private static func parseISO6709Location(_ string: String) -> GeoLocation? {
        // ISO 6709 format: +DD.DDDD+DDD.DDDD+AAA.AAA/
        // Example: +37.7749-122.4194+0/
        
        let pattern = #"([+-]\d+\.?\d*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        
        let nsString = string as NSString
        let matches = regex.matches(in: string, range: NSRange(location: 0, length: nsString.length))
        
        guard matches.count >= 2 else { return nil }
        
        let latString = nsString.substring(with: matches[0].range)
        let lonString = nsString.substring(with: matches[1].range)
        
        guard let lat = Double(latString), let lon = Double(lonString) else { return nil }
        
        var alt: Double? = nil
        if matches.count >= 3 {
            let altString = nsString.substring(with: matches[2].range)
            alt = Double(altString)
        }
        
        return GeoLocation(latitude: lat, longitude: lon, altitude: alt)
    }
}
