// AudioExporter.swift
// MetaVisRender
//
// Created for Sprint 12: Audio Mixing
// Export mixed audio to file or mux with video

import Foundation
import AVFoundation

// MARK: - AudioExportFormat

/// Output format for audio export
public enum AudioExportFormat: String, Codable, Sendable, CaseIterable {
    case aac
    case alac
    case pcm
    case mp3
    
    public var fileExtension: String {
        switch self {
        case .aac: return "m4a"
        case .alac: return "m4a"
        case .pcm: return "wav"
        case .mp3: return "mp3"
        }
    }
    
    public var formatID: AudioFormatID {
        switch self {
        case .aac: return kAudioFormatMPEG4AAC
        case .alac: return kAudioFormatAppleLossless
        case .pcm: return kAudioFormatLinearPCM
        case .mp3: return kAudioFormatMPEGLayer3
        }
    }
    
    public var fileType: AVFileType {
        switch self {
        case .aac, .alac: return .m4a
        case .pcm: return .wav
        case .mp3: return .mp3
        }
    }
    
    public var displayName: String {
        switch self {
        case .aac: return "AAC (Compressed)"
        case .alac: return "Apple Lossless"
        case .pcm: return "WAV (Uncompressed)"
        case .mp3: return "MP3"
        }
    }
}

// MARK: - AudioExportConfiguration

/// Configuration for audio export
public struct AudioExportConfiguration: Codable, Sendable {
    /// Output format
    public let format: AudioExportFormat
    
    /// Sample rate
    public let sampleRate: Double
    
    /// Channel count (1 = mono, 2 = stereo)
    public let channelCount: Int
    
    /// Bit rate for compressed formats (bits per second)
    public let bitRate: Int?
    
    /// Bit depth for PCM (16 or 24)
    public let bitDepth: Int
    
    public init(
        format: AudioExportFormat = .aac,
        sampleRate: Double = 48000,
        channelCount: Int = 2,
        bitRate: Int? = 256000,
        bitDepth: Int = 16
    ) {
        self.format = format
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitRate = bitRate
        self.bitDepth = bitDepth
    }
    
    public static let `default` = AudioExportConfiguration()
    
    public static let highQuality = AudioExportConfiguration(
        format: .aac,
        sampleRate: 48000,
        bitRate: 320000
    )
    
    public static let lossless = AudioExportConfiguration(
        format: .alac,
        sampleRate: 48000,
        bitDepth: 24
    )
    
    public static let wav = AudioExportConfiguration(
        format: .pcm,
        sampleRate: 48000,
        bitDepth: 24
    )
    
    /// AVFoundation output settings
    public var outputSettings: [String: Any] {
        var settings: [String: Any] = [
            AVFormatIDKey: format.formatID,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount
        ]
        
        switch format {
        case .aac:
            if let bitRate = bitRate {
                settings[AVEncoderBitRateKey] = bitRate
            }
            settings[AVEncoderAudioQualityKey] = AVAudioQuality.max.rawValue
            
        case .alac:
            settings[AVEncoderBitDepthHintKey] = bitDepth
            
        case .pcm:
            settings[AVLinearPCMBitDepthKey] = bitDepth
            settings[AVLinearPCMIsBigEndianKey] = false
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsNonInterleaved] = false
            
        case .mp3:
            if let bitRate = bitRate {
                settings[AVEncoderBitRateKey] = bitRate
            }
        }
        
        return settings
    }
}

// MARK: - AudioExporter

/// Exports mixed audio to file
///
/// Handles encoding audio buffers to various formats and
/// muxing with video when needed.
///
/// ## Example
/// ```swift
/// let exporter = AudioExporter(configuration: .highQuality)
/// try await exporter.start(outputURL: outputURL)
/// 
/// for time in stride(from: 0, to: duration, by: bufferDuration) {
///     let buffer = try await mixer.mix(...)
///     try await exporter.append(buffer: buffer)
/// }
/// 
/// try await exporter.finish()
/// ```
public actor AudioExporter {
    
    // MARK: - Types
    
    public enum State {
        case idle
        case exporting
        case finished
        case failed(Error)
    }
    
    public typealias ProgressHandler = @Sendable (Double) -> Void
    
    // MARK: - Properties
    
    /// Export configuration
    public let configuration: AudioExportConfiguration
    
    /// Current state
    public private(set) var state: State = .idle
    
    /// Asset writer
    private var writer: AVAssetWriter?
    
    /// Audio input
    private var audioInput: AVAssetWriterInput?
    
    /// Sample buffer adaptor
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    /// Current presentation time
    private var currentTime: CMTime = .zero
    
    /// Buffer queue for async writing
    private var pendingBuffers: [MixerAudioBuffer] = []
    
    // MARK: - Initialization
    
    public init(configuration: AudioExportConfiguration = .default) {
        self.configuration = configuration
    }
    
    // MARK: - Export API
    
    /// Start export to URL
    public func start(outputURL: URL) throws {
        guard case .idle = state else {
            throw AudioExportError.invalidState("Cannot start: exporter not idle")
        }
        
        // Remove existing file
        try? FileManager.default.removeItem(at: outputURL)
        
        // Create writer
        writer = try AVAssetWriter(outputURL: outputURL, fileType: configuration.format.fileType)
        
        // Create audio input
        audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: configuration.outputSettings
        )
        audioInput?.expectsMediaDataInRealTime = false
        
        guard let writer = writer, let input = audioInput else {
            throw AudioExportError.initializationFailed
        }
        
        writer.add(input)
        
        guard writer.startWriting() else {
            throw AudioExportError.writerFailed(writer.error?.localizedDescription ?? "Unknown error")
        }
        
        writer.startSession(atSourceTime: .zero)
        
        state = .exporting
        currentTime = .zero
    }
    
    /// Append audio buffer
    public func append(buffer: MixerAudioBuffer) async throws {
        guard case .exporting = state else {
            throw AudioExportError.invalidState("Cannot append: not exporting")
        }
        
        guard let input = audioInput else {
            throw AudioExportError.invalidState("No audio input")
        }
        
        // Convert buffer to CMSampleBuffer
        let sampleBuffer = try createSampleBuffer(from: buffer, at: currentTime)
        
        // Wait for input ready
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        }
        
        guard input.append(sampleBuffer) else {
            throw AudioExportError.appendFailed
        }
        
        // Advance time
        let duration = CMTime(
            value: CMTimeValue(buffer.sampleCount),
            timescale: CMTimeScale(configuration.sampleRate)
        )
        currentTime = CMTimeAdd(currentTime, duration)
    }
    
    /// Finish export
    public func finish() async throws {
        guard case .exporting = state else {
            throw AudioExportError.invalidState("Cannot finish: not exporting")
        }
        
        audioInput?.markAsFinished()
        
        guard let writer = writer else {
            throw AudioExportError.invalidState("No writer")
        }
        
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
        
        if writer.status == .completed {
            state = .finished
        } else {
            let error = writer.error ?? AudioExportError.unknown
            state = .failed(error)
            throw error
        }
    }
    
    /// Cancel export
    public func cancel() {
        writer?.cancelWriting()
        state = .idle
        cleanup()
    }
    
    // MARK: - Private
    
    private func createSampleBuffer(
        from buffer: MixerAudioBuffer,
        at time: CMTime
    ) throws -> CMSampleBuffer {
        // Create audio stream description
        var asbd = AudioStreamBasicDescription(
            mSampleRate: configuration.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(configuration.channelCount * MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(configuration.channelCount * MemoryLayout<Float>.size),
            mChannelsPerFrame: UInt32(configuration.channelCount),
            mBitsPerChannel: UInt32(MemoryLayout<Float>.size * 8),
            mReserved: 0
        )
        
        var formatDesc: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )
        
        guard status == noErr, let formatDescription = formatDesc else {
            throw AudioExportError.formatCreationFailed
        }
        
        // Interleave channels
        var interleaved = [Float](repeating: 0, count: buffer.sampleCount * configuration.channelCount)
        
        for sample in 0..<buffer.sampleCount {
            for channel in 0..<min(buffer.channelCount, configuration.channelCount) {
                interleaved[sample * configuration.channelCount + channel] = buffer.channels[channel][sample]
            }
        }
        
        // Create block buffer
        let dataSize = interleaved.count * MemoryLayout<Float>.size
        var blockBuffer: CMBlockBuffer?
        
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard blockStatus == kCMBlockBufferNoErr, let block = blockBuffer else {
            throw AudioExportError.bufferCreationFailed
        }
        
        // Copy data to block buffer
        let copyStatus = CMBlockBufferReplaceDataBytes(
            with: interleaved,
            blockBuffer: block,
            offsetIntoDestination: 0,
            dataLength: dataSize
        )
        
        guard copyStatus == kCMBlockBufferNoErr else {
            throw AudioExportError.bufferCreationFailed
        }
        
        // Create sample buffer
        var sampleBuffer: CMSampleBuffer?
        
        let timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(configuration.sampleRate)),
            presentationTimeStamp: time,
            decodeTimeStamp: .invalid
        )
        
        var timingInfo = timing
        
        let sampleStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: buffer.sampleCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        
        guard sampleStatus == noErr, let sample = sampleBuffer else {
            throw AudioExportError.sampleCreationFailed
        }
        
        return sample
    }
    
    private func cleanup() {
        writer = nil
        audioInput = nil
        currentTime = .zero
        pendingBuffers.removeAll()
    }
}

// MARK: - AudioExportError

public enum AudioExportError: Error, LocalizedError {
    case invalidState(String)
    case initializationFailed
    case writerFailed(String)
    case appendFailed
    case formatCreationFailed
    case bufferCreationFailed
    case sampleCreationFailed
    case unknown
    
    public var errorDescription: String? {
        switch self {
        case .invalidState(let msg): return "Invalid state: \(msg)"
        case .initializationFailed: return "Failed to initialize exporter"
        case .writerFailed(let msg): return "Writer failed: \(msg)"
        case .appendFailed: return "Failed to append audio buffer"
        case .formatCreationFailed: return "Failed to create audio format"
        case .bufferCreationFailed: return "Failed to create audio buffer"
        case .sampleCreationFailed: return "Failed to create sample buffer"
        case .unknown: return "Unknown error"
        }
    }
}

// MARK: - Convenience Export

extension AudioExporter {
    /// Export timeline audio to file
    public static func export(
        timeline: [AudioTrack],
        transitions: [AudioTransition] = [],
        to outputURL: URL,
        configuration: AudioExportConfiguration = .default,
        mixer: AudioMixer? = nil,
        progress: ProgressHandler? = nil
    ) async throws {
        let exporter = AudioExporter(configuration: configuration)
        let audioMixer = mixer ?? AudioMixer()
        let resolver = AudioResolver(tracks: timeline, transitions: transitions)
        
        // Setup mixer with tracks
        for track in timeline {
            await audioMixer.addTrack(track)
        }
        
        try await exporter.start(outputURL: outputURL)
        
        let duration = resolver.duration
        let bufferDuration = Double(1024) / configuration.sampleRate
        var currentTime = 0.0
        
        while currentTime < duration {
            // Resolve audio at current time
            let resolved = resolver.resolve(time: currentTime)
            
            // Create buffers for each track
            // Note: In real implementation, would read from audio decoders
            var trackBuffers: [AudioTrackID: MixerAudioBuffer] = [:]
            
            for audio in resolved {
                // Placeholder - real implementation reads from source files
                let buffer = MixerAudioBuffer.empty(
                    channelCount: configuration.channelCount,
                    sampleCount: 1024,
                    sampleRate: configuration.sampleRate
                )
                trackBuffers[audio.trackID] = buffer.applyGain(audio.volume)
            }
            
            // Mix
            let mixed = try await audioMixer.mix(
                trackBuffers: trackBuffers,
                time: currentTime
            )
            
            // Append
            try await exporter.append(buffer: mixed)
            
            currentTime += bufferDuration
            progress?(currentTime / duration)
        }
        
        try await exporter.finish()
    }
}
