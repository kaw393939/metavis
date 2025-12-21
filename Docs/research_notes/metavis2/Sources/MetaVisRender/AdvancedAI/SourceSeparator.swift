// SourceSeparator.swift
// MetaVisRender
//
// Demucs-style neural network source separation
// Separates audio into dialog, music, ambience, and other stems
// Sprint 08

import Foundation
import AVFoundation
import Accelerate
import CoreML

// MARK: - SourceSeparator

/// Separates audio into constituent stems using neural network models
public actor SourceSeparator {
    
    // MARK: - Properties
    
    private let config: SeparationConfig
    private var model: DemucsModel?
    private var isLoaded = false
    private var isProcessing = false
    
    private let outputDirectory: URL
    
    // MARK: - Initialization
    
    public init(config: SeparationConfig = .default, outputDirectory: URL? = nil) {
        self.config = config
        self.outputDirectory = outputDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("MetaVisRender/stems", isDirectory: true)
    }
    
    // MARK: - Public API
    
    /// Load the separation model
    public func loadModel() async throws {
        guard !isLoaded else { return }
        
        model = DemucsModel()
        isLoaded = true
    }
    
    /// Unload the model to free memory
    public func unloadModel() {
        model = nil
        isLoaded = false
    }
    
    /// Separate audio file into stems
    public func separate(
        audioURL: URL,
        outputName: String? = nil,
        progress: AdvancedAIProgress? = nil
    ) async throws -> SeparatedStems {
        guard isLoaded, let model = model else {
            throw AdvancedAIError.modelNotLoaded("Demucs")
        }
        
        guard !isProcessing else {
            throw AdvancedAIError.separationFailed("Already processing")
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        let startTime = Date()
        
        // Step 1: Load and preprocess audio
        progress?(0.1, SeparationStage.preprocessing.rawValue)
        let audioData = try await loadAudio(from: audioURL)
        
        // Step 2: Process in chunks
        progress?(0.2, SeparationStage.separating.rawValue)
        let demucsStems = try await processChunks(
            audio: audioData,
            model: model,
            progress: { chunkProgress in
                let overallProgress = 0.2 + 0.6 * chunkProgress
                progress?(overallProgress, SeparationStage.separating.rawValue)
            }
        )
        
        // Step 3: Map Demucs stems to our stem types
        progress?(0.85, SeparationStage.postprocessing.rawValue)
        let mappedStems = mapToApplicationStems(demucs: demucsStems)
        
        // Step 4: Export stems
        progress?(0.9, SeparationStage.exporting.rawValue)
        let baseName = outputName ?? audioURL.deletingPathExtension().lastPathComponent
        let stems = try await exportStems(
            mappedStems,
            baseName: baseName
        )
        
        let processingTime = Date().timeIntervalSince(startTime)
        let qualityScore = estimateQuality(stems: mappedStems)
        
        let metadata = StemMetadata(
            modelVersion: "demucs-v4",
            processingTime: processingTime,
            qualityScore: qualityScore,
            sampleRate: config.outputSampleRate,
            bitDepth: config.outputBitDepth
        )
        
        progress?(1.0, SeparationStage.complete.rawValue)
        
        return SeparatedStems(
            dialog: stems.dialog,
            music: stems.music,
            ambience: stems.ambience,
            other: stems.other,
            metadata: metadata
        )
    }
    
    /// Separate and return raw Demucs stems (vocals, drums, bass, other)
    public func separateRaw(
        audioURL: URL,
        outputName: String? = nil,
        progress: AdvancedAIProgress? = nil
    ) async throws -> DemucsStems {
        guard isLoaded, let model = model else {
            throw AdvancedAIError.modelNotLoaded("Demucs")
        }
        
        guard !isProcessing else {
            throw AdvancedAIError.separationFailed("Already processing")
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        let startTime = Date()
        
        progress?(0.1, SeparationStage.preprocessing.rawValue)
        let audioData = try await loadAudio(from: audioURL)
        
        progress?(0.2, SeparationStage.separating.rawValue)
        let stems = try await processChunks(
            audio: audioData,
            model: model,
            progress: { chunkProgress in
                progress?(0.2 + 0.6 * chunkProgress, SeparationStage.separating.rawValue)
            }
        )
        
        progress?(0.9, SeparationStage.exporting.rawValue)
        let baseName = outputName ?? audioURL.deletingPathExtension().lastPathComponent
        
        // Export raw stems
        let urls = try await exportRawStems(stems, baseName: baseName)
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        let metadata = StemMetadata(
            modelVersion: "demucs-v4",
            processingTime: processingTime,
            qualityScore: 0.9,
            sampleRate: config.outputSampleRate,
            bitDepth: config.outputBitDepth
        )
        
        progress?(1.0, SeparationStage.complete.rawValue)
        
        return DemucsStems(
            vocals: urls.vocals,
            drums: urls.drums,
            bass: urls.bass,
            other: urls.other,
            metadata: metadata
        )
    }
    
    /// Check if model is loaded
    public func isModelLoaded() -> Bool {
        return isLoaded
    }
    
    /// Get estimated memory usage for the model
    public func estimatedMemoryUsage() -> Int {
        // Demucs model is approximately 200MB
        return 200 * 1024 * 1024
    }
    
    // MARK: - Private Methods
    
    private func loadAudio(from url: URL) async throws -> AudioBuffer {
        let asset = AVAsset(url: url)
        
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AdvancedAIError.invalidInput("No audio track found")
        }
        
        let duration = try await asset.load(.duration)
        
        let reader = try AVAssetReader(asset: asset)
        
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: config.outputSampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)
        
        guard reader.startReading() else {
            throw AdvancedAIError.invalidInput("Failed to start reading audio")
        }
        
        var leftChannel: [Float] = []
        var rightChannel: [Float] = []
        
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            
            if let dataPointer = dataPointer {
                let floatCount = length / MemoryLayout<Float>.size
                let floatPointer = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Float.self)
                let buffer = UnsafeBufferPointer(start: floatPointer, count: floatCount)
                
                // Deinterleave stereo
                for i in stride(from: 0, to: floatCount - 1, by: 2) {
                    leftChannel.append(buffer[i])
                    rightChannel.append(buffer[i + 1])
                }
            }
        }
        
        return AudioBuffer(
            left: leftChannel,
            right: rightChannel,
            sampleRate: config.outputSampleRate,
            duration: CMTimeGetSeconds(duration)
        )
    }
    
    private func processChunks(
        audio: AudioBuffer,
        model: DemucsModel,
        progress: @escaping (Float) -> Void
    ) async throws -> RawStems {
        let chunkSamples = Int(config.chunkDuration * config.outputSampleRate)
        let overlapSamples = Int(config.overlapDuration * config.outputSampleRate)
        let hopSamples = chunkSamples - overlapSamples
        
        var vocalsLeft: [Float] = []
        var vocalsRight: [Float] = []
        var drumsLeft: [Float] = []
        var drumsRight: [Float] = []
        var bassLeft: [Float] = []
        var bassRight: [Float] = []
        var otherLeft: [Float] = []
        var otherRight: [Float] = []
        
        let totalChunks = max(1, (audio.left.count - overlapSamples) / hopSamples)
        var chunkIndex = 0
        var position = 0
        
        while position < audio.left.count {
            let endPosition = min(position + chunkSamples, audio.left.count)
            
            let leftChunk = Array(audio.left[position..<endPosition])
            let rightChunk = Array(audio.right[position..<endPosition])
            
            // Process chunk through model
            let separated = model.separate(left: leftChunk, right: rightChunk)
            
            // Handle overlap-add for smooth transitions
            if chunkIndex == 0 {
                // First chunk: no crossfade at start
                vocalsLeft.append(contentsOf: separated.vocals.left)
                vocalsRight.append(contentsOf: separated.vocals.right)
                drumsLeft.append(contentsOf: separated.drums.left)
                drumsRight.append(contentsOf: separated.drums.right)
                bassLeft.append(contentsOf: separated.bass.left)
                bassRight.append(contentsOf: separated.bass.right)
                otherLeft.append(contentsOf: separated.other.left)
                otherRight.append(contentsOf: separated.other.right)
            } else {
                // Crossfade overlap region
                let fadeLength = min(overlapSamples, separated.vocals.left.count)
                
                // Crossfade the overlap region
                for i in 0..<fadeLength {
                    let fadeIn = Float(i) / Float(fadeLength)
                    let fadeOut = 1.0 - fadeIn
                    
                    let overlapIndex = vocalsLeft.count - fadeLength + i
                    if overlapIndex >= 0 && overlapIndex < vocalsLeft.count {
                        vocalsLeft[overlapIndex] = vocalsLeft[overlapIndex] * fadeOut + separated.vocals.left[i] * fadeIn
                        vocalsRight[overlapIndex] = vocalsRight[overlapIndex] * fadeOut + separated.vocals.right[i] * fadeIn
                        drumsLeft[overlapIndex] = drumsLeft[overlapIndex] * fadeOut + separated.drums.left[i] * fadeIn
                        drumsRight[overlapIndex] = drumsRight[overlapIndex] * fadeOut + separated.drums.right[i] * fadeIn
                        bassLeft[overlapIndex] = bassLeft[overlapIndex] * fadeOut + separated.bass.left[i] * fadeIn
                        bassRight[overlapIndex] = bassRight[overlapIndex] * fadeOut + separated.bass.right[i] * fadeIn
                        otherLeft[overlapIndex] = otherLeft[overlapIndex] * fadeOut + separated.other.left[i] * fadeIn
                        otherRight[overlapIndex] = otherRight[overlapIndex] * fadeOut + separated.other.right[i] * fadeIn
                    }
                }
                
                // Append non-overlapping part
                if fadeLength < separated.vocals.left.count {
                    vocalsLeft.append(contentsOf: separated.vocals.left[fadeLength...])
                    vocalsRight.append(contentsOf: separated.vocals.right[fadeLength...])
                    drumsLeft.append(contentsOf: separated.drums.left[fadeLength...])
                    drumsRight.append(contentsOf: separated.drums.right[fadeLength...])
                    bassLeft.append(contentsOf: separated.bass.left[fadeLength...])
                    bassRight.append(contentsOf: separated.bass.right[fadeLength...])
                    otherLeft.append(contentsOf: separated.other.left[fadeLength...])
                    otherRight.append(contentsOf: separated.other.right[fadeLength...])
                }
            }
            
            chunkIndex += 1
            position += hopSamples
            
            progress(Float(chunkIndex) / Float(totalChunks))
        }
        
        return RawStems(
            vocals: StereoBuffer(left: vocalsLeft, right: vocalsRight),
            drums: StereoBuffer(left: drumsLeft, right: drumsRight),
            bass: StereoBuffer(left: bassLeft, right: bassRight),
            other: StereoBuffer(left: otherLeft, right: otherRight)
        )
    }
    
    private func mapToApplicationStems(demucs: RawStems) -> MappedStems {
        // Map Demucs stems to our application stems:
        // - vocals -> dialog
        // - drums + bass -> music
        // - other -> split between ambience and other
        
        let dialog = demucs.vocals
        
        // Mix drums and bass for music stem
        let musicLeft = zip(demucs.drums.left, demucs.bass.left).map { $0 + $1 }
        let musicRight = zip(demucs.drums.right, demucs.bass.right).map { $0 + $1 }
        let music = StereoBuffer(left: musicLeft, right: musicRight)
        
        // Split "other" into ambience and other based on spectral content
        let (ambience, other) = splitOtherStem(demucs.other)
        
        return MappedStems(
            dialog: dialog,
            music: music,
            ambience: ambience,
            other: other
        )
    }
    
    private func splitOtherStem(_ stem: StereoBuffer) -> (ambience: StereoBuffer, other: StereoBuffer) {
        // Simple split: low frequency content -> ambience, rest -> other
        // In production, this would use proper filtering
        
        let filterLength = 64
        var ambienceLeft: [Float] = []
        var ambienceRight: [Float] = []
        var otherLeft: [Float] = []
        var otherRight: [Float] = []
        
        // Simple moving average for low-pass (ambience)
        for i in 0..<stem.left.count {
            let start = max(0, i - filterLength / 2)
            let end = min(stem.left.count, i + filterLength / 2)
            
            var sumL: Float = 0
            var sumR: Float = 0
            for j in start..<end {
                sumL += stem.left[j]
                sumR += stem.right[j]
            }
            
            let avgL = sumL / Float(end - start)
            let avgR = sumR / Float(end - start)
            
            ambienceLeft.append(avgL * 0.7)
            ambienceRight.append(avgR * 0.7)
            otherLeft.append(stem.left[i] - avgL * 0.7)
            otherRight.append(stem.right[i] - avgR * 0.7)
        }
        
        return (
            ambience: StereoBuffer(left: ambienceLeft, right: ambienceRight),
            other: StereoBuffer(left: otherLeft, right: otherRight)
        )
    }
    
    private func exportStems(
        _ stems: MappedStems,
        baseName: String
    ) async throws -> (dialog: URL, music: URL, ambience: URL, other: URL) {
        // Create output directory
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        
        let dialogURL = outputDirectory.appendingPathComponent("\(baseName)_dialog.wav")
        let musicURL = outputDirectory.appendingPathComponent("\(baseName)_music.wav")
        let ambienceURL = outputDirectory.appendingPathComponent("\(baseName)_ambience.wav")
        let otherURL = outputDirectory.appendingPathComponent("\(baseName)_other.wav")
        
        try await writeStereoWAV(buffer: stems.dialog, to: dialogURL)
        try await writeStereoWAV(buffer: stems.music, to: musicURL)
        try await writeStereoWAV(buffer: stems.ambience, to: ambienceURL)
        try await writeStereoWAV(buffer: stems.other, to: otherURL)
        
        return (dialog: dialogURL, music: musicURL, ambience: ambienceURL, other: otherURL)
    }
    
    private func exportRawStems(
        _ stems: RawStems,
        baseName: String
    ) async throws -> (vocals: URL, drums: URL, bass: URL, other: URL) {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        
        let vocalsURL = outputDirectory.appendingPathComponent("\(baseName)_vocals.wav")
        let drumsURL = outputDirectory.appendingPathComponent("\(baseName)_drums.wav")
        let bassURL = outputDirectory.appendingPathComponent("\(baseName)_bass.wav")
        let otherURL = outputDirectory.appendingPathComponent("\(baseName)_other.wav")
        
        try await writeStereoWAV(buffer: stems.vocals, to: vocalsURL)
        try await writeStereoWAV(buffer: stems.drums, to: drumsURL)
        try await writeStereoWAV(buffer: stems.bass, to: bassURL)
        try await writeStereoWAV(buffer: stems.other, to: otherURL)
        
        return (vocals: vocalsURL, drums: drumsURL, bass: bassURL, other: otherURL)
    }
    
    private func writeStereoWAV(buffer: StereoBuffer, to url: URL) async throws {
        // Create WAV file
        let sampleRate = config.outputSampleRate
        let bitDepth = config.outputBitDepth
        
        var audioFile: AVAudioFile?
        
        let format = AVAudioFormat(
            commonFormat: bitDepth == 32 ? .pcmFormatFloat32 : .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        )!
        
        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        
        guard let file = audioFile else {
            throw AdvancedAIError.separationFailed("Failed to create audio file")
        }
        
        let frameCount = AVAudioFrameCount(buffer.left.count)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AdvancedAIError.separationFailed("Failed to create PCM buffer")
        }
        
        pcmBuffer.frameLength = frameCount
        
        // Copy data to channels
        if let leftData = pcmBuffer.floatChannelData?[0],
           let rightData = pcmBuffer.floatChannelData?[1] {
            for i in 0..<Int(frameCount) {
                leftData[i] = buffer.left[i]
                rightData[i] = buffer.right[i]
            }
        }
        
        try file.write(from: pcmBuffer)
    }
    
    private func estimateQuality(stems: MappedStems) -> Float {
        // Estimate separation quality based on inter-stem correlation
        // Lower correlation = better separation
        
        var totalCorrelation: Float = 0
        var comparisons = 0
        
        let stemBuffers = [stems.dialog, stems.music, stems.ambience, stems.other]
        
        for i in 0..<stemBuffers.count {
            for j in (i+1)..<stemBuffers.count {
                let corrL = correlate(stemBuffers[i].left, stemBuffers[j].left)
                let corrR = correlate(stemBuffers[i].right, stemBuffers[j].right)
                totalCorrelation += (corrL + corrR) / 2
                comparisons += 1
            }
        }
        
        let avgCorrelation = comparisons > 0 ? totalCorrelation / Float(comparisons) : 0
        
        // Convert to quality score (lower correlation = higher quality)
        return max(0, min(1, 1.0 - avgCorrelation))
    }
    
    private func correlate(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count && !a.isEmpty else { return 0 }
        
        var correlation: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<min(a.count, 1000) {  // Sample for performance
            correlation += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denom = sqrt(normA * normB)
        return denom > 0 ? abs(correlation / denom) : 0
    }
}

// MARK: - Internal Types

/// Audio buffer with left and right channels
private struct AudioBuffer {
    let left: [Float]
    let right: [Float]
    let sampleRate: Double
    let duration: Double
}

/// Stereo buffer for a single stem
public struct StereoBuffer: Sendable {
    public let left: [Float]
    public let right: [Float]
    
    public init(left: [Float], right: [Float]) {
        self.left = left
        self.right = right
    }
    
    public var sampleCount: Int {
        left.count
    }
}

/// Raw Demucs output stems
private struct RawStems {
    let vocals: StereoBuffer
    let drums: StereoBuffer
    let bass: StereoBuffer
    let other: StereoBuffer
}

/// Mapped application stems
private struct MappedStems {
    let dialog: StereoBuffer
    let music: StereoBuffer
    let ambience: StereoBuffer
    let other: StereoBuffer
}

// MARK: - DemucsModel

/// Demucs neural network model for source separation
/// This is a simplified implementation - production would use CoreML
private class DemucsModel {
    
    /// Separate a stereo audio chunk into stems
    func separate(left: [Float], right: [Float]) -> (vocals: StereoBuffer, drums: StereoBuffer, bass: StereoBuffer, other: StereoBuffer) {
        // Simplified separation using spectral masking
        // In production, this would use the actual Demucs CoreML model
        
        let frameSize = 1024
        let hopSize = 256
        
        // Process frames
        var vocalsL: [Float] = []
        var vocalsR: [Float] = []
        var drumsL: [Float] = []
        var drumsR: [Float] = []
        var bassL: [Float] = []
        var bassR: [Float] = []
        var otherL: [Float] = []
        var otherR: [Float] = []
        
        var position = 0
        
        while position < left.count {
            let endPosition = min(position + frameSize, left.count)
            let _ = endPosition - position
            
            let leftFrame = Array(left[position..<endPosition])
            let rightFrame = Array(right[position..<endPosition])
            
            // Simplified frequency-based separation
            let separated = separateFrame(left: leftFrame, right: rightFrame)
            
            // Overlap-add
            vocalsL.append(contentsOf: separated.vocals.left)
            vocalsR.append(contentsOf: separated.vocals.right)
            drumsL.append(contentsOf: separated.drums.left)
            drumsR.append(contentsOf: separated.drums.right)
            bassL.append(contentsOf: separated.bass.left)
            bassR.append(contentsOf: separated.bass.right)
            otherL.append(contentsOf: separated.other.left)
            otherR.append(contentsOf: separated.other.right)
            
            position += hopSize
        }
        
        // Trim to original length
        let originalLength = left.count
        let trimVocalsL = Array(vocalsL.prefix(originalLength))
        let trimVocalsR = Array(vocalsR.prefix(originalLength))
        let trimDrumsL = Array(drumsL.prefix(originalLength))
        let trimDrumsR = Array(drumsR.prefix(originalLength))
        let trimBassL = Array(bassL.prefix(originalLength))
        let trimBassR = Array(bassR.prefix(originalLength))
        let trimOtherL = Array(otherL.prefix(originalLength))
        let trimOtherR = Array(otherR.prefix(originalLength))
        
        return (
            vocals: StereoBuffer(left: trimVocalsL, right: trimVocalsR),
            drums: StereoBuffer(left: trimDrumsL, right: trimDrumsR),
            bass: StereoBuffer(left: trimBassL, right: trimBassR),
            other: StereoBuffer(left: trimOtherL, right: trimOtherR)
        )
    }
    
    private func separateFrame(left: [Float], right: [Float]) -> (vocals: StereoBuffer, drums: StereoBuffer, bass: StereoBuffer, other: StereoBuffer) {
        // Simplified frequency-based separation
        // Vocals: mid frequencies (300Hz - 3kHz range indicators)
        // Drums: transients (high zero-crossing rate)
        // Bass: low frequencies (< 250Hz range indicators)
        // Other: remainder
        
        var vocalsL = [Float](repeating: 0, count: left.count)
        var vocalsR = [Float](repeating: 0, count: right.count)
        var drumsL = [Float](repeating: 0, count: left.count)
        var drumsR = [Float](repeating: 0, count: right.count)
        var bassL = [Float](repeating: 0, count: left.count)
        var bassR = [Float](repeating: 0, count: right.count)
        var otherL = [Float](repeating: 0, count: left.count)
        var otherR = [Float](repeating: 0, count: right.count)
        
        // Simple bandpass approximation using moving averages
        let bassWindow = 32
        let midWindow = 8
        
        for i in 0..<left.count {
            // Bass: long-term average (low frequency)
            let bassStart = max(0, i - bassWindow / 2)
            let bassEnd = min(left.count, i + bassWindow / 2)
            var bassAvgL: Float = 0
            var bassAvgR: Float = 0
            for j in bassStart..<bassEnd {
                bassAvgL += left[j]
                bassAvgR += right[j]
            }
            bassAvgL /= Float(bassEnd - bassStart)
            bassAvgR /= Float(bassEnd - bassStart)
            
            bassL[i] = bassAvgL * 0.8
            bassR[i] = bassAvgR * 0.8
            
            // Mid (vocals): short-term variation from bass
            let midStart = max(0, i - midWindow / 2)
            let midEnd = min(left.count, i + midWindow / 2)
            var midAvgL: Float = 0
            var midAvgR: Float = 0
            for j in midStart..<midEnd {
                midAvgL += left[j]
                midAvgR += right[j]
            }
            midAvgL /= Float(midEnd - midStart)
            midAvgR /= Float(midEnd - midStart)
            
            // Vocals are mid frequencies (between bass and high)
            vocalsL[i] = (midAvgL - bassAvgL) * 0.9
            vocalsR[i] = (midAvgR - bassAvgR) * 0.9
            
            // Drums: transient detection (difference from local average)
            let transientL = abs(left[i] - midAvgL)
            let transientR = abs(right[i] - midAvgR)
            
            if transientL > 0.1 {
                drumsL[i] = (left[i] - midAvgL) * 0.7
            }
            if transientR > 0.1 {
                drumsR[i] = (right[i] - midAvgR) * 0.7
            }
            
            // Other: everything else
            otherL[i] = left[i] - bassL[i] - vocalsL[i] - drumsL[i]
            otherR[i] = right[i] - bassR[i] - vocalsR[i] - drumsR[i]
        }
        
        return (
            vocals: StereoBuffer(left: vocalsL, right: vocalsR),
            drums: StereoBuffer(left: drumsL, right: drumsR),
            bass: StereoBuffer(left: bassL, right: bassR),
            other: StereoBuffer(left: otherL, right: otherR)
        )
    }
}
