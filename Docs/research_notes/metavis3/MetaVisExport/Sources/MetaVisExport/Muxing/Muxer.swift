// Muxer.swift
// MetaVisRender
//
// Combines video, audio, and metadata streams into container formats

@preconcurrency import Foundation
@preconcurrency import AVFoundation
@preconcurrency import CoreVideo
import CoreMedia
import VideoToolbox

// MARK: - Sendable Wrappers

/// A Sendable wrapper for CVPixelBuffer to allow passing between actors
/// This is safe because we transfer ownership of the buffer to the Muxer
public struct SendablePixelBuffer: @unchecked Sendable {
    public let pixelBuffer: CVPixelBuffer
    
    public init(_ pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
    }
}

// MARK: - Muxer Error

/// Errors that can occur during muxing
public enum MuxerError: Error, LocalizedError {
    case writerCreationFailed(Error)
    case invalidOutputURL
    case invalidVideoSettings
    case invalidAudioSettings
    case inputCreationFailed(Error)
    case writingFailed(Error)
    case finalizationFailed(Error)
    case unsupportedContainer(ContainerFormat)
    case trackAdditionFailed
    case notStarted
    case alreadyFinished
    
    public var errorDescription: String? {
        switch self {
        case .writerCreationFailed(let error):
            return "Failed to create asset writer: \(error.localizedDescription)"
        case .invalidOutputURL:
            return "Invalid output URL"
        case .invalidVideoSettings:
            return "Invalid video encoding settings"
        case .invalidAudioSettings:
            return "Invalid audio encoding settings"
        case .inputCreationFailed(let error):
            return "Failed to create writer input: \(error.localizedDescription)"
        case .writingFailed(let error):
            return "Writing failed: \(error.localizedDescription)"
        case .finalizationFailed(let error):
            return "Failed to finalize output: \(error.localizedDescription)"
        case .unsupportedContainer(let format):
            return "Unsupported container format: \(format)"
        case .trackAdditionFailed:
            return "Failed to add track to output"
        case .notStarted:
            return "Muxer has not been started"
        case .alreadyFinished:
            return "Muxer has already finished"
        }
    }
}

// MARK: - Muxer Configuration

/// Configuration for the muxer
public struct MuxerConfiguration: Sendable {
    /// Output container format
    public let container: ContainerFormat
    
    /// Output file URL
    public let outputURL: URL
    
    /// Video encoding settings (nil if no video)
    public let videoSettings: VideoEncodingSettings?
    
    /// Video resolution
    public let resolution: ExportResolution?
    
    /// Frame rate
    public let frameRate: Double
    
    /// Audio encoding settings (nil if no audio)
    public let audioSettings: AudioEncodingSettings?
    
    /// Metadata to embed
    public let metadata: [String: String]
    
    /// Whether to include chapter markers
    public let includeChapters: Bool
    
    /// Chapter markers (timecode -> title)
    public let chapters: [(time: CMTime, title: String)]
    
    /// Whether to enable fast start for streaming (moov atom at beginning)
    public let fastStart: Bool
    
    /// Fragment duration for fragmented MP4 (nil for non-fragmented)
    public let fragmentDuration: CMTime?
    
    public init(
        container: ContainerFormat = .mp4,
        outputURL: URL,
        videoSettings: VideoEncodingSettings? = nil,
        resolution: ExportResolution? = nil,
        frameRate: Double = 30.0,
        audioSettings: AudioEncodingSettings? = nil,
        metadata: [String: String] = [:],
        includeChapters: Bool = false,
        chapters: [(time: CMTime, title: String)] = [],
        fastStart: Bool = true,
        fragmentDuration: CMTime? = nil
    ) {
        self.container = container
        self.outputURL = outputURL
        self.videoSettings = videoSettings
        self.resolution = resolution
        self.frameRate = frameRate
        self.audioSettings = audioSettings
        self.metadata = metadata
        self.includeChapters = includeChapters
        self.chapters = chapters
        self.fastStart = fastStart
        self.fragmentDuration = fragmentDuration
    }
}

// MARK: - Muxer State

/// Current state of the muxer
public enum MuxerState: Sendable {
    case idle
    case writing
    case finished
    case failed(Error)
}

// MARK: - Muxer

/// Combines encoded video and audio into container formats
public actor Muxer {
    
    // MARK: - Properties
    
    private let configuration: MuxerConfiguration
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var state: MuxerState = .idle
    private var videoFramesWritten: Int64 = 0
    private var audioSamplesWritten: Int64 = 0
    private var lastVideoTime: CMTime = .zero
    private var lastAudioTime: CMTime = .zero
    
    // MARK: - Initialization
    
    public init(configuration: MuxerConfiguration) throws {
        self.configuration = configuration
        
        // Create asset writer
        let fileType = try Self.avFileType(for: configuration.container)
        
        do {
            // Remove existing file if present
            try? FileManager.default.removeItem(at: configuration.outputURL)
            
            self.assetWriter = try AVAssetWriter(url: configuration.outputURL, fileType: fileType)
        } catch {
            throw MuxerError.writerCreationFailed(error)
        }
        
        guard let writer = self.assetWriter else {
            throw MuxerError.writerCreationFailed(NSError(domain: "Muxer", code: -1))
        }
        
        // Apply metadata
        writer.metadata = Self.createMetadataItems(configuration: configuration)
        
        // Create video input if needed
        if let videoSettings = configuration.videoSettings {
            let (input, adaptor) = try Self.createVideoInput(settings: videoSettings, configuration: configuration, writer: writer)
            self.videoInput = input
            self.pixelBufferAdaptor = adaptor
        }
        
        // Create audio input if needed
        if let audioSettings = configuration.audioSettings {
            self.audioInput = try Self.createAudioInput(settings: audioSettings, writer: writer)
        }
    }
    
    // MARK: - Public Methods
    
    /// Start the muxing session
    public func start() throws {
        guard case .idle = state else { return }
        
        guard let writer = assetWriter else {
            throw MuxerError.notStarted
        }
        
        guard writer.startWriting() else {
            throw MuxerError.writingFailed(writer.error ?? MuxerError.writerCreationFailed(NSError(domain: "Muxer", code: -1)))
        }
        
        writer.startSession(atSourceTime: .zero)
        state = .writing
    }
    
    /// Append a video sample buffer
    public func appendVideo(sampleBuffer: CMSampleBuffer) async throws {
        guard case .writing = state else {
            throw MuxerError.notStarted
        }
        
        guard let videoInput = videoInput else {
            throw MuxerError.invalidVideoSettings
        }
        
        while !videoInput.isReadyForMoreMediaData {
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }
        
        guard videoInput.append(sampleBuffer) else {
            throw MuxerError.writingFailed(assetWriter?.error ?? MuxerError.writingFailed(NSError(domain: "Muxer", code: -2)))
        }
        
        videoFramesWritten += 1
        lastVideoTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    }
    
    /// Append a video pixel buffer with presentation time
    public func appendVideo(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) async throws {
        guard case .writing = state else {
            throw MuxerError.notStarted
        }
        
        guard let adaptor = pixelBufferAdaptor else {
            throw MuxerError.invalidVideoSettings
        }
        
        while !adaptor.assetWriterInput.isReadyForMoreMediaData {
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }
        
        guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
            throw MuxerError.writingFailed(assetWriter?.error ?? MuxerError.writingFailed(NSError(domain: "Muxer", code: -3)))
        }
        
        videoFramesWritten += 1
        lastVideoTime = presentationTime
    }
    
    /// Append a video pixel buffer with presentation time (Sendable wrapper)
    public func appendVideo(pixelBuffer: SendablePixelBuffer, presentationTime: CMTime) async throws {
        try await appendVideo(pixelBuffer: pixelBuffer.pixelBuffer, presentationTime: presentationTime)
    }
    
    /// Append an audio sample buffer
    public func appendAudio(sampleBuffer: CMSampleBuffer) async throws {
        guard case .writing = state else {
            throw MuxerError.notStarted
        }
        
        guard let audioInput = audioInput else {
            throw MuxerError.invalidAudioSettings
        }
        
        while !audioInput.isReadyForMoreMediaData {
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }
        
        guard audioInput.append(sampleBuffer) else {
            throw MuxerError.writingFailed(assetWriter?.error ?? MuxerError.writingFailed(NSError(domain: "Muxer", code: -4)))
        }
        
        audioSamplesWritten += Int64(CMSampleBufferGetNumSamples(sampleBuffer))
        lastAudioTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    }
    
    /// Finish writing and finalize the output file
    public func finish() async throws {
        guard case .writing = state else {
            if case .finished = state { return }
            throw MuxerError.notStarted
        }
        
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        
        guard let writer = assetWriter else {
            throw MuxerError.notStarted
        }
        
        await writer.finishWriting()
        
        if let error = writer.error {
            state = .failed(error)
            throw MuxerError.finalizationFailed(error)
        }
        
        state = .finished
    }
    
    /// Cancel the muxing operation
    public func cancel() {
        assetWriter?.cancelWriting()
        state = .idle
    }
    
    /// Get current state
    public func getState() -> MuxerState {
        return state
    }
    
    /// Get progress information
    public func getProgress() -> (videoFrames: Int64, audioSamples: Int64, lastVideoTime: CMTime, lastAudioTime: CMTime) {
        return (videoFramesWritten, audioSamplesWritten, lastVideoTime, lastAudioTime)
    }
    
    // MARK: - Private Methods
    

    
    private static func avFileType(for container: ContainerFormat) throws -> AVFileType {
        switch container {
        case .mp4, .m4v:
            return .mp4
        case .mov:
            return .mov
        case .m4a:
            return .m4a
        case .wav:
            return .wav
        case .aiff:
            return .aiff
        case .mp3:
            return .mp3
        case .mkv:
            // MKV not directly supported by AVFoundation, use MP4
            return .mp4
        case .webm:
            // WebM not supported by AVFoundation
            throw MuxerError.unsupportedContainer(container)
        case .avi:
            // AVI not well supported, use MOV
            return .mov
        case .unknown:
            return .mp4
        }
    }
    
    private static func createVideoInput(settings: VideoEncodingSettings, configuration: MuxerConfiguration, writer: AVAssetWriter) throws -> (AVAssetWriterInput, AVAssetWriterInputPixelBufferAdaptor) {
        guard let resolution = configuration.resolution else {
            throw MuxerError.invalidVideoSettings
        }
        
        var outputSettings: [String: Any] = [:]
        
        // Codec
        switch settings.codec {
        case .h264:
            outputSettings[AVVideoCodecKey] = AVVideoCodecType.h264
        case .hevc, .hevcWithAlpha:
            outputSettings[AVVideoCodecKey] = AVVideoCodecType.hevc
        case .prores422, .prores422LT, .prores422Proxy:
            outputSettings[AVVideoCodecKey] = AVVideoCodecType.proRes422
        case .prores422HQ:
            outputSettings[AVVideoCodecKey] = AVVideoCodecType.proRes422HQ
        case .prores4444, .prores4444XQ:
            outputSettings[AVVideoCodecKey] = AVVideoCodecType.proRes4444
        case .proresRAW:
            // ProRes RAW not directly supported for writing
            outputSettings[AVVideoCodecKey] = AVVideoCodecType.proRes4444
        case .av1:
            // AV1 not yet widely supported for writing
            outputSettings[AVVideoCodecKey] = AVVideoCodecType.hevc
        case .jpeg, .mjpeg:
            outputSettings[AVVideoCodecKey] = AVVideoCodecType.jpeg
        case .unknown:
            outputSettings[AVVideoCodecKey] = AVVideoCodecType.h264
        }
        
        // Resolution
        outputSettings[AVVideoWidthKey] = resolution.width
        outputSettings[AVVideoHeightKey] = resolution.height
        
        // Compression properties
        var compressionProperties: [String: Any] = [:]
        
        // Bit rate
        compressionProperties[AVVideoAverageBitRateKey] = settings.bitrate
        
        // Frame rate (as max keyframe interval for quality)
        compressionProperties[AVVideoMaxKeyFrameIntervalDurationKey] = settings.keyframeInterval
        
        // Profile/Level for H.264
        if settings.codec == .h264 {
            if let profile = settings.profile {
                compressionProperties[AVVideoProfileLevelKey] = profile
            } else {
                compressionProperties[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
            }
        }
        
        // HDR metadata if needed
        // This would be added based on color space settings
        
        outputSettings[AVVideoCompressionPropertiesKey] = compressionProperties
        
        // Create input
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false
        
        guard writer.canAdd(input) else {
            throw MuxerError.trackAdditionFailed
        }
        
        writer.add(input)
        
        // Create pixel buffer adaptor
        // Determine input pixel format based on codec
        let pixelFormat: OSType
        if settings.codec == .hevc || settings.codec == .hevcWithAlpha {
            // For HEVC, we prefer 10-bit YUV (ZeroCopy path)
            pixelFormat = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        } else {
            // For H.264 and others, default to BGRA (legacy path)
            pixelFormat = kCVPixelFormatType_32BGRA
        }
        
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: resolution.width,
            kCVPixelBufferHeightKey as String: resolution.height,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )
        
        return (input, adaptor)
    }
    
    private static func createAudioInput(settings: AudioEncodingSettings, writer: AVAssetWriter) throws -> AVAssetWriterInput {
        var outputSettings: [String: Any] = [:]
        
        // Helper for PCM format detection
        let isPCMFormat = [AudioCodec.pcmS16LE, .pcmS24LE, .pcmS32LE, .pcmFloat].contains(settings.codec)
        
        // Codec
        switch settings.codec {
        case .aac, .aacLC, .aacHE:
            outputSettings[AVFormatIDKey] = kAudioFormatMPEG4AAC
        case .pcmS16LE:
            outputSettings[AVFormatIDKey] = kAudioFormatLinearPCM
            outputSettings[AVLinearPCMBitDepthKey] = 16
            outputSettings[AVLinearPCMIsBigEndianKey] = false
            outputSettings[AVLinearPCMIsFloatKey] = false
        case .pcmS24LE:
            outputSettings[AVFormatIDKey] = kAudioFormatLinearPCM
            outputSettings[AVLinearPCMBitDepthKey] = 24
            outputSettings[AVLinearPCMIsBigEndianKey] = false
            outputSettings[AVLinearPCMIsFloatKey] = false
        case .pcmS32LE:
            outputSettings[AVFormatIDKey] = kAudioFormatLinearPCM
            outputSettings[AVLinearPCMBitDepthKey] = 32
            outputSettings[AVLinearPCMIsBigEndianKey] = false
            outputSettings[AVLinearPCMIsFloatKey] = false
        case .pcmFloat:
            outputSettings[AVFormatIDKey] = kAudioFormatLinearPCM
            outputSettings[AVLinearPCMBitDepthKey] = 32
            outputSettings[AVLinearPCMIsBigEndianKey] = false
            outputSettings[AVLinearPCMIsFloatKey] = true
        case .alac:
            outputSettings[AVFormatIDKey] = kAudioFormatAppleLossless
            outputSettings[AVEncoderBitDepthHintKey] = settings.bitDepth
        case .flac:
            // FLAC not directly supported in AVFoundation for output
            outputSettings[AVFormatIDKey] = kAudioFormatAppleLossless
        case .opus:
            outputSettings[AVFormatIDKey] = kAudioFormatOpus
        case .mp3:
            // MP3 encoding not supported in AVFoundation
            outputSettings[AVFormatIDKey] = kAudioFormatMPEG4AAC
        case .ac3, .eac3:
            outputSettings[AVFormatIDKey] = kAudioFormatAC3
        case .unknown:
            // Default to AAC for unknown codecs
            outputSettings[AVFormatIDKey] = kAudioFormatMPEG4AAC
        }
        
        // Common settings
        outputSettings[AVSampleRateKey] = settings.sampleRate
        outputSettings[AVNumberOfChannelsKey] = settings.channelCount
        
        // Bit rate for compressed formats
        if !isPCMFormat, let bitrate = settings.bitrate {
            outputSettings[AVEncoderBitRateKey] = bitrate
        }
        
        // Audio channel layout
        var channelLayout = AudioChannelLayout()
        if settings.channelCount == 1 {
            channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
        } else if settings.channelCount == 2 {
            channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        } else {
            channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_AudioUnit_5_1
        }
        outputSettings[AVChannelLayoutKey] = Data(bytes: &channelLayout, count: MemoryLayout<AudioChannelLayout>.size)
        
        // Create input
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false
        
        guard writer.canAdd(input) else {
            throw MuxerError.trackAdditionFailed
        }
        
        writer.add(input)
        return input
    }
    
    private static func createMetadataItems(configuration: MuxerConfiguration) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []
        
        for (key, value) in configuration.metadata {
            let item = AVMutableMetadataItem()
            item.keySpace = .common
            
            switch key.lowercased() {
            case "title":
                item.key = AVMetadataKey.commonKeyTitle as NSString
            case "artist", "author":
                item.key = AVMetadataKey.commonKeyArtist as NSString
            case "album":
                item.key = AVMetadataKey.commonKeyAlbumName as NSString
            case "description":
                item.key = AVMetadataKey.commonKeyDescription as NSString
            case "copyright":
                item.key = AVMetadataKey.commonKeyCopyrights as NSString
            case "software":
                item.key = AVMetadataKey.commonKeySoftware as NSString
            case "date":
                item.key = AVMetadataKey.commonKeyCreationDate as NSString
            default:
                // Custom metadata
                item.keySpace = .quickTimeMetadata
                item.key = key as NSString
            }
            
            item.value = value as NSString
            items.append(item)
        }
        
        // Add creation date if not specified
        if !configuration.metadata.keys.contains("date") {
            let dateItem = AVMutableMetadataItem()
            dateItem.keySpace = .common
            dateItem.key = AVMetadataKey.commonKeyCreationDate as NSString
            let formatter = ISO8601DateFormatter()
            dateItem.value = formatter.string(from: Date()) as NSString
            items.append(dateItem)
        }
        
        // Add software tag
        if !configuration.metadata.keys.contains("software") {
            let softwareItem = AVMutableMetadataItem()
            softwareItem.keySpace = .common
            softwareItem.key = AVMetadataKey.commonKeySoftware as NSString
            softwareItem.value = "MetaVisRender" as NSString
            items.append(softwareItem)
        }
        
        return items
    }
}

// MARK: - Simple Remuxer

/// Remuxes media from one container to another without re-encoding
public actor Remuxer {
    
    private let sourceURL: URL
    private let destinationURL: URL
    private let container: ContainerFormat
    
    public init(
        sourceURL: URL,
        destinationURL: URL,
        container: ContainerFormat = .mp4
    ) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.container = container
    }
    
    /// Perform remuxing
    public func remux(progress: ((Double) -> Void)? = nil) async throws {
        let asset = AVURLAsset(url: sourceURL)
        
        // Get file type
        let fileType: AVFileType
        switch container {
        case .mp4, .m4v: fileType = .mp4
        case .mov: fileType = .mov
        case .m4a: fileType = .m4a
        case .wav: fileType = .wav
        case .aiff: fileType = .aiff
        case .mp3: fileType = .mp3
        case .mkv, .webm, .avi, .unknown: throw MuxerError.unsupportedContainer(container)
        }
        
        // Remove existing file
        try? FileManager.default.removeItem(at: destinationURL)
        
        // Create export session
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw MuxerError.writerCreationFailed(NSError(domain: "Remuxer", code: -1))
        }
        
        exportSession.outputURL = destinationURL
        exportSession.outputFileType = fileType
        
        // Export with progress monitoring
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                progress?(Double(exportSession.progress))
            }
            
            exportSession.exportAsynchronously {
                timer.invalidate()
                continuation.resume()
            }
        }
        
        // Check for errors
        if let error = exportSession.error {
            throw MuxerError.writingFailed(error)
        }
        
        if exportSession.status != .completed {
            throw MuxerError.finalizationFailed(NSError(domain: "Remuxer", code: -2))
        }
    }
}

// MARK: - Stream Multiplexer

/// Multiplexes multiple input streams into a single output
public actor StreamMultiplexer {
    
    public struct InputStream: Sendable {
        public let url: URL
        public let type: AVMediaType
        public let trackIndex: Int?
        
        public init(url: URL, type: AVMediaType, trackIndex: Int? = nil) {
            self.url = url
            self.type = type
            self.trackIndex = trackIndex
        }
    }
    
    private let inputs: [InputStream]
    private let outputURL: URL
    private let container: ContainerFormat
    
    public init(
        inputs: [InputStream],
        outputURL: URL,
        container: ContainerFormat = .mp4
    ) {
        self.inputs = inputs
        self.outputURL = outputURL
        self.container = container
    }
    
    /// Perform multiplexing
    public func multiplex(progress: ((Double) -> Void)? = nil) async throws {
        // Create composition
        let composition = AVMutableComposition()
        
        var duration = CMTime.zero
        
        for input in inputs {
            let asset = AVURLAsset(url: input.url)
            
            let tracks: [AVAssetTrack]
            if let trackIndex = input.trackIndex {
                if let track = try await asset.loadTracks(withMediaType: input.type)[safe: trackIndex] {
                    tracks = [track]
                } else {
                    tracks = []
                }
            } else {
                tracks = try await asset.loadTracks(withMediaType: input.type)
            }
            
            for track in tracks {
                guard let compositionTrack = composition.addMutableTrack(
                    withMediaType: input.type,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else { continue }
                
                let trackDuration = try await track.load(.timeRange).duration
                
                try compositionTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: trackDuration),
                    of: track,
                    at: .zero
                )
                
                if trackDuration > duration {
                    duration = trackDuration
                }
            }
        }
        
        // Export
        let fileType: AVFileType
        switch container {
        case .mp4, .m4v: fileType = .mp4
        case .mov: fileType = .mov
        case .m4a: fileType = .m4a
        case .wav: fileType = .wav
        case .aiff: fileType = .aiff
        case .mp3: fileType = .mp3
        case .mkv, .webm, .avi, .unknown: throw MuxerError.unsupportedContainer(container)
        }
        
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw MuxerError.writerCreationFailed(NSError(domain: "StreamMultiplexer", code: -1))
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = fileType
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                progress?(Double(exportSession.progress))
            }
            
            exportSession.exportAsynchronously {
                timer.invalidate()
                continuation.resume()
            }
        }
        
        if let error = exportSession.error {
            throw MuxerError.writingFailed(error)
        }
    }
}

// MARK: - Array Extension

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}
