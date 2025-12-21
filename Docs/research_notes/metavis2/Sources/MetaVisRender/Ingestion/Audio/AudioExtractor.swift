// Sources/MetaVisRender/Ingestion/Audio/AudioExtractor.swift
// Sprint 03: Extract and convert audio from media containers

@preconcurrency import AVFoundation
import Foundation

// MARK: - Audio Extractor

/// Extracts audio from video containers and converts to WAV for processing
public actor AudioExtractor {
    
    // MARK: - Types
    
    /// Output format for extracted audio
    public enum OutputFormat: Sendable {
        case wav16kMono      // Optimal for Whisper
        case wav48kStereo    // High quality
        case wav44kStereo    // CD quality
        case original        // Keep original format
        
        var sampleRate: Double {
            switch self {
            case .wav16kMono: return 16000
            case .wav48kStereo: return 48000
            case .wav44kStereo: return 44100
            case .original: return 0  // Will use source rate
            }
        }
        
        var channels: Int {
            switch self {
            case .wav16kMono: return 1
            case .wav48kStereo, .wav44kStereo: return 2
            case .original: return 0  // Will use source channels
            }
        }
    }
    
    /// Extraction result
    public struct ExtractionResult: Sendable {
        public let outputURL: URL
        public let duration: Double
        public let sampleRate: Int
        public let channels: Int
        public let format: String
        public let sourceTrackId: Int
    }
    
    /// Progress callback
    public typealias ProgressHandler = @Sendable (Float) -> Void
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Public API
    
    /// Extract audio from a media file
    /// - Parameters:
    ///   - sourceURL: URL to source video/audio file
    ///   - outputURL: URL for output audio file (nil = temp directory)
    ///   - format: Desired output format
    ///   - trackIndex: Audio track index (0 = first/primary)
    ///   - progress: Optional progress callback
    /// - Returns: Extraction result with output file info
    public func extract(
        from sourceURL: URL,
        to outputURL: URL? = nil,
        format: OutputFormat = .wav16kMono,
        trackIndex: Int = 0,
        progress: ProgressHandler? = nil
    ) async throws -> ExtractionResult {
        
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw IngestionError.fileNotFound(sourceURL)
        }
        
        let asset = AVURLAsset(url: sourceURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])
        
        // Get audio tracks
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw IngestionError.noAudioTrack
        }
        
        guard trackIndex < audioTracks.count else {
            throw IngestionError.noAudioTrack
        }
        
        let track = audioTracks[trackIndex]
        let duration = try await asset.load(.duration).seconds
        
        // Determine output URL
        let output = outputURL ?? generateTempURL(for: sourceURL)
        
        // Get source format info
        let formatDescriptions = try await track.load(.formatDescriptions)
        let sourceFormat = formatDescriptions.first.flatMap {
            CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
        }
        
        let sourceSampleRate = sourceFormat?.mSampleRate ?? 48000
        let sourceChannels = Int(sourceFormat?.mChannelsPerFrame ?? 2)
        
        // Determine target format
        let targetSampleRate = format == .original ? sourceSampleRate : format.sampleRate
        let targetChannels = format == .original ? sourceChannels : format.channels
        
        // Configure output settings
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: targetChannels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        // Create asset reader
        let reader = try AVAssetReader(asset: asset)
        
        let readerOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: targetSampleRate,
                AVNumberOfChannelsKey: targetChannels,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false
            ]
        )
        reader.add(readerOutput)
        
        // Create asset writer
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        
        let writer = try AVAssetWriter(outputURL: output, fileType: .wav)
        
        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: outputSettings
        )
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)
        
        // Start reading and writing
        guard reader.startReading() else {
            throw IngestionError.corruptedFile(reader.error?.localizedDescription ?? "Unknown error")
        }
        
        guard writer.startWriting() else {
            throw IngestionError.corruptedFile(writer.error?.localizedDescription ?? "Unknown error")
        }
        
        writer.startSession(atSourceTime: .zero)
        
        // Process audio samples
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "com.metavis.audioextractor")
            
            var lastProgress: Float = 0
            
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                        // Calculate progress
                        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                        let newProgress = Float(currentTime / duration)
                        
                        if newProgress - lastProgress > 0.01 {  // Report every 1%
                            lastProgress = newProgress
                            Task { @MainActor in
                                progress?(min(newProgress, 1.0))
                            }
                        }
                        
                        if !writerInput.append(sampleBuffer) {
                            reader.cancelReading()
                            writer.cancelWriting()
                            continuation.resume(throwing: IngestionError.corruptedFile("Failed to append audio sample"))
                            return
                        }
                    } else {
                        // No more samples
                        writerInput.markAsFinished()
                        
                        writer.finishWriting {
                            if writer.status == .completed {
                                Task { @MainActor in
                                    progress?(1.0)
                                }
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: IngestionError.corruptedFile(writer.error?.localizedDescription ?? "Unknown error"))
                            }
                        }
                        return
                    }
                }
            }
        }
        
        return ExtractionResult(
            outputURL: output,
            duration: duration,
            sampleRate: Int(targetSampleRate),
            channels: targetChannels,
            format: "wav",
            sourceTrackId: Int(track.trackID)
        )
    }
    
    /// Extract audio to a buffer for in-memory processing
    public func extractToBuffer(
        from sourceURL: URL,
        format: OutputFormat = .wav16kMono,
        trackIndex: Int = 0
    ) async throws -> AVAudioPCMBuffer {
        
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw IngestionError.fileNotFound(sourceURL)
        }
        
        let asset = AVURLAsset(url: sourceURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        
        guard !audioTracks.isEmpty else {
            throw IngestionError.noAudioTrack
        }
        
        guard trackIndex < audioTracks.count else {
            throw IngestionError.noAudioTrack
        }
        
        let track = audioTracks[trackIndex]
        let duration = try await asset.load(.duration).seconds
        
        // Target format
        let sampleRate = format == .original ? 48000 : format.sampleRate
        let channels = format == .original ? 2 : format.channels
        
        guard let audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: false
        ) else {
            throw IngestionError.corruptedFile("Failed to create audio format")
        }
        
        // Calculate buffer size
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            throw IngestionError.insufficientMemory
        }
        
        // Create reader
        let reader = try AVAssetReader(asset: asset)
        
        let readerOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: true
            ]
        )
        reader.add(readerOutput)
        
        guard reader.startReading() else {
            throw IngestionError.corruptedFile(reader.error?.localizedDescription ?? "Unknown error")
        }
        
        // Read all samples into buffer
        var frameOffset: AVAudioFrameCount = 0
        
        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            
            let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            
            guard let data = dataPointer else { continue }
            
            // Copy samples to buffer
            let floatPointer = data.withMemoryRebound(to: Float.self, capacity: sampleCount * channels) { $0 }
            
            for channel in 0..<channels {
                guard let channelData = buffer.floatChannelData?[channel] else { continue }
                
                for sample in 0..<sampleCount {
                    let srcIndex = sample * channels + channel
                    let dstIndex = Int(frameOffset) + sample
                    
                    if dstIndex < Int(buffer.frameCapacity) {
                        channelData[dstIndex] = floatPointer[srcIndex]
                    }
                }
            }
            
            frameOffset += AVAudioFrameCount(sampleCount)
        }
        
        buffer.frameLength = min(frameOffset, buffer.frameCapacity)
        
        return buffer
    }
    
    // MARK: - Utility
    
    /// Check if a file has audio
    public func hasAudio(at url: URL) async -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        
        let asset = AVURLAsset(url: url)
        let tracks = try? await asset.loadTracks(withMediaType: .audio)
        return tracks?.isEmpty == false
    }
    
    /// Get audio track count
    public func audioTrackCount(at url: URL) async -> Int {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        
        let asset = AVURLAsset(url: url)
        let tracks = try? await asset.loadTracks(withMediaType: .audio)
        return tracks?.count ?? 0
    }
    
    // MARK: - Private
    
    private func generateTempURL(for source: URL) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetaVis", isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let filename = source.deletingPathExtension().lastPathComponent
        let uuid = UUID().uuidString.prefix(8)
        
        return tempDir.appendingPathComponent("\(filename)_\(uuid).wav")
    }
}

// MARK: - Audio File Info

/// Quick audio file information
public struct AudioFileInfo: Codable, Sendable {
    public let duration: Double
    public let sampleRate: Int
    public let channels: Int
    public let codec: AudioCodec
    public let bitrate: Int?
    
    public var durationFormatted: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

extension AudioExtractor {
    
    /// Quick info about an audio file
    public func info(for url: URL) async throws -> AudioFileInfo {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw IngestionError.fileNotFound(url)
        }
        
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        
        guard let track = tracks.first else {
            throw IngestionError.noAudioTrack
        }
        
        let duration = try await asset.load(.duration).seconds
        let formatDescriptions = try await track.load(.formatDescriptions)
        let bitrate = try? await track.load(.estimatedDataRate)
        
        guard let formatDesc = formatDescriptions.first,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else {
            throw IngestionError.corruptedFile("Cannot read audio format")
        }
        
        let formatID = asbd.mFormatID
        let codec: AudioCodec
        switch formatID {
        case kAudioFormatMPEG4AAC: codec = .aac
        case kAudioFormatLinearPCM: codec = .pcmS16LE
        case kAudioFormatAppleLossless: codec = .alac
        case kAudioFormatMPEGLayer3: codec = .mp3
        case kAudioFormatOpus: codec = .opus
        case kAudioFormatFLAC: codec = .flac
        default: codec = .unknown
        }
        
        return AudioFileInfo(
            duration: duration,
            sampleRate: Int(asbd.mSampleRate),
            channels: Int(asbd.mChannelsPerFrame),
            codec: codec,
            bitrate: bitrate.map { Int($0) }
        )
    }
}
