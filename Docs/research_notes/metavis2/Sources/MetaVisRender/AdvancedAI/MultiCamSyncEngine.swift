// MultiCamSyncEngine.swift
// MetaVisRender
//
// Audio fingerprinting and cross-correlation for multi-camera synchronization
// Uses chromagram extraction, waveform correlation, and visual refinement
// Sprint 08

import Foundation
import AVFoundation
import Accelerate

// MARK: - MultiCamSyncEngine

/// Synchronizes multiple camera angles using audio fingerprinting
public actor MultiCamSyncEngine {
    
    // MARK: - Properties
    
    private let fingerprinter: AudioFingerprinter
    private let correlator: SignalCorrelator
    private var cachedFingerprints: [UUID: AudioFingerprint] = [:]
    
    // MARK: - Initialization
    
    public init() {
        self.fingerprinter = AudioFingerprinter()
        self.correlator = SignalCorrelator()
    }
    
    // MARK: - Public API
    
    /// Synchronize multiple clips to a reference clip
    public func synchronize(
        referenceURL: URL,
        referenceClipId: UUID,
        otherClips: [(url: URL, clipId: UUID)],
        progress: AdvancedAIProgress? = nil
    ) async throws -> MultiCamAlignment {
        let startTime = Date()
        
        // Step 1: Extract fingerprint for reference
        progress?(0.1, "Extracting reference audio fingerprint")
        let referenceFingerprint = try await fingerprinter.extractFingerprint(from: referenceURL)
        cachedFingerprints[referenceClipId] = referenceFingerprint
        
        // Step 2: Process each clip
        var alignedClips: [AlignedClip] = []
        let clipCount = otherClips.count
        
        for (index, clip) in otherClips.enumerated() {
            let progressValue = 0.1 + (0.8 * Float(index + 1) / Float(clipCount))
            progress?(progressValue, "Aligning clip \(index + 1) of \(clipCount)")
            
            do {
                let aligned = try await alignClip(
                    clip,
                    toReference: referenceFingerprint,
                    referenceClipId: referenceClipId
                )
                alignedClips.append(aligned)
            } catch {
                // Log but continue with other clips
                print("Failed to align clip \(clip.clipId): \(error)")
            }
        }
        
        guard !alignedClips.isEmpty else {
            throw AdvancedAIError.syncFailed("No clips could be aligned")
        }
        
        // Calculate overall confidence
        let avgConfidence = alignedClips.reduce(0) { $0 + $1.confidence } / Float(alignedClips.count)
        
        if avgConfidence < AdvancedAIDefaults.minSyncConfidence {
            throw AdvancedAIError.lowSyncConfidence(avgConfidence)
        }
        
        // Determine best alignment method based on results
        let method = determineBestMethod(from: alignedClips)
        
        progress?(1.0, "Synchronization complete")
        
        let analysisTime = Date().timeIntervalSince(startTime)
        
        return MultiCamAlignment(
            referenceClipId: referenceClipId,
            alignedClips: alignedClips,
            confidence: avgConfidence,
            method: method,
            analysisTime: analysisTime
        )
    }
    
    /// Suggest camera cuts based on speaker and visual analysis
    public func suggestCuts(
        alignment: MultiCamAlignment,
        analyses: [UUID: FootageAnalysis],
        progress: AdvancedAIProgress? = nil
    ) async throws -> [CutSuggestion] {
        var suggestions: [CutSuggestion] = []
        
        guard let referenceAnalysis = analyses[alignment.referenceClipId] else {
            throw AdvancedAIError.invalidInput("Missing reference analysis")
        }
        
        // Find speaker changes
        if let speakerInfo = referenceAnalysis.speakerInfo {
            progress?(0.3, "Analyzing speaker changes")
            let speakerCuts = findSpeakerChangeCuts(
                speakerInfo: speakerInfo,
                alignment: alignment
            )
            suggestions.append(contentsOf: speakerCuts)
        }
        
        // Find reaction shot opportunities
        progress?(0.6, "Finding reaction shots")
        let reactionCuts = findReactionShotCuts(alignment: alignment, analyses: analyses)
        suggestions.append(contentsOf: reactionCuts)
        
        // Find shot size changes
        progress?(0.9, "Optimizing shot variety")
        let shotCuts = findShotSizeChangeCuts(alignment: alignment, analyses: analyses)
        suggestions.append(contentsOf: shotCuts)
        
        progress?(1.0, "Cut suggestions complete")
        
        // Sort by timestamp and remove duplicates
        return suggestions
            .sorted { $0.timestamp < $1.timestamp }
            .reduce(into: [CutSuggestion]()) { result, cut in
                // Avoid cuts too close together (< 2 seconds)
                if let last = result.last, cut.timestamp - last.timestamp < 2.0 {
                    // Keep the one with higher confidence
                    if cut.confidence > last.confidence {
                        result[result.count - 1] = cut
                    }
                } else {
                    result.append(cut)
                }
            }
    }
    
    /// Get the cached fingerprint for a clip
    public func getFingerprint(for clipId: UUID) -> AudioFingerprint? {
        return cachedFingerprints[clipId]
    }
    
    /// Clear the fingerprint cache
    public func clearCache() {
        cachedFingerprints.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func alignClip(
        _ clip: (url: URL, clipId: UUID),
        toReference reference: AudioFingerprint,
        referenceClipId: UUID
    ) async throws -> AlignedClip {
        // Extract fingerprint for this clip
        let fingerprint = try await fingerprinter.extractFingerprint(from: clip.url)
        cachedFingerprints[clip.clipId] = fingerprint
        
        // Cross-correlate to find offset
        let correlation = correlator.crossCorrelate(
            reference: reference,
            candidate: fingerprint
        )
        
        // Refine with waveform correlation if needed
        var offset = correlation.offset
        var confidence = correlation.confidence
        
        if confidence < 0.9 {
            let refined = correlator.refineWithWaveform(
                reference: reference,
                candidate: fingerprint,
                initialOffset: offset
            )
            if refined.confidence > confidence {
                offset = refined.offset
                confidence = refined.confidence
            }
        }
        
        // Detect drift over time
        let drift = correlator.detectDrift(
            reference: reference,
            candidate: fingerprint,
            offset: offset
        )
        
        return AlignedClip(
            clipId: clip.clipId,
            sourceURL: clip.url,
            offset: offset,
            confidence: confidence,
            drift: drift
        )
    }
    
    private func determineBestMethod(from alignedClips: [AlignedClip]) -> AlignmentMethod {
        // Use chromagram if all clips have high confidence
        let avgConfidence = alignedClips.reduce(0) { $0 + $1.confidence } / Float(alignedClips.count)
        
        if avgConfidence > 0.95 {
            return .chromagram
        } else if avgConfidence > 0.85 {
            return .audioFingerprint
        } else {
            return .waveform
        }
    }
    
    private func findSpeakerChangeCuts(
        speakerInfo: ClipSpeakerInfo,
        alignment: MultiCamAlignment
    ) -> [CutSuggestion] {
        var cuts: [CutSuggestion] = []
        let segments = speakerInfo.segments.sorted { $0.startTime < $1.startTime }
        
        for i in 1..<segments.count {
            let prevSpeaker = segments[i - 1].speakerId
            let currSpeaker = segments[i].speakerId
            
            if prevSpeaker != currSpeaker {
                // Find a clip that might show this speaker
                // For now, use round-robin between clips
                let fromClipIndex = i % (alignment.alignedClips.count + 1)
                let toClipIndex = (i + 1) % (alignment.alignedClips.count + 1)
                
                let fromClipId = fromClipIndex == 0 ? 
                    alignment.referenceClipId : 
                    alignment.alignedClips[fromClipIndex - 1].clipId
                let toClipId = toClipIndex == 0 ? 
                    alignment.referenceClipId : 
                    alignment.alignedClips[toClipIndex - 1].clipId
                
                if fromClipId != toClipId {
                    cuts.append(CutSuggestion(
                        timestamp: segments[i].startTime,
                        fromClipId: fromClipId,
                        toClipId: toClipId,
                        reason: .speakerChange,
                        confidence: segments[i].confidence
                    ))
                }
            }
        }
        
        return cuts
    }
    
    private func findReactionShotCuts(
        alignment: MultiCamAlignment,
        analyses: [UUID: FootageAnalysis]
    ) -> [CutSuggestion] {
        var cuts: [CutSuggestion] = []
        
        // Find moments of high emotion in one clip and suggest cutting to another
        for alignedClip in alignment.alignedClips {
            guard let analysis = analyses[alignedClip.clipId],
                  let emotions = analysis.emotions else { continue }
            
            for emotion in emotions {
                if emotion.intensity > 0.7 {
                    // Suggest cutting to this clip for reaction
                    cuts.append(CutSuggestion(
                        timestamp: emotion.timestamp + alignedClip.offset,
                        fromClipId: alignment.referenceClipId,
                        toClipId: alignedClip.clipId,
                        reason: .reactionShot,
                        confidence: emotion.intensity
                    ))
                }
            }
        }
        
        return cuts
    }
    
    private func findShotSizeChangeCuts(
        alignment: MultiCamAlignment,
        analyses: [UUID: FootageAnalysis]
    ) -> [CutSuggestion] {
        // This would analyze frame composition to suggest wide-to-close transitions
        // For now, return empty - would need visual analysis integration
        return []
    }
}

// MARK: - AudioFingerprinter

/// Extracts audio fingerprints using chromagram and spectral features
public struct AudioFingerprinter: Sendable {
    
    private let hopSize: Int
    private let fftSize: Int
    private let sampleRate: Double
    
    public init(
        hopSize: Int = AdvancedAIDefaults.fingerprintHopSize,
        fftSize: Int = 2048,
        sampleRate: Double = 44100
    ) {
        self.hopSize = hopSize
        self.fftSize = fftSize
        self.sampleRate = sampleRate
    }
    
    /// Extract audio fingerprint from a media file
    public func extractFingerprint(from url: URL) async throws -> AudioFingerprint {
        let asset = AVAsset(url: url)
        
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AdvancedAIError.invalidInput("No audio track found")
        }
        
        // Get audio samples
        let samples = try await extractAudioSamples(from: asset, track: audioTrack)
        
        // Compute chromagram
        let chromagram = computeChromagram(samples: samples)
        
        // Compute other features
        let rmsEnergy = computeRMSEnergy(samples: samples)
        let zeroCrossings = computeZeroCrossings(samples: samples)
        let spectralCentroid = computeSpectralCentroid(samples: samples)
        
        return AudioFingerprint(
            chromagram: chromagram,
            rmsEnergy: rmsEnergy,
            zeroCrossings: zeroCrossings,
            spectralCentroid: spectralCentroid,
            hopSize: hopSize,
            sampleRate: sampleRate
        )
    }
    
    private func extractAudioSamples(from asset: AVAsset, track: AVAssetTrack) async throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)
        
        guard reader.startReading() else {
            throw AdvancedAIError.invalidInput("Failed to start reading audio")
        }
        
        var samples: [Float] = []
        
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            
            if let dataPointer = dataPointer {
                let floatCount = length / MemoryLayout<Float>.size
                let floatPointer = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Float.self)
                samples.append(contentsOf: UnsafeBufferPointer(start: floatPointer, count: floatCount))
            }
        }
        
        return samples
    }
    
    private func computeChromagram(samples: [Float]) -> [[Float]] {
        let frameCount = samples.count / hopSize
        var chromagram: [[Float]] = []
        
        let chromaBins = AdvancedAIDefaults.chromagramBins
        
        for frameIndex in 0..<frameCount {
            let startSample = frameIndex * hopSize
            let endSample = min(startSample + fftSize, samples.count)
            
            guard endSample - startSample >= fftSize / 2 else { break }
            
            // Simplified chromagram computation
            // In production, this would use proper FFT and pitch class folding
            var chroma = [Float](repeating: 0, count: chromaBins)
            
            let frameSlice = Array(samples[startSample..<endSample])
            
            // Compute energy in each pitch class
            for i in 0..<chromaBins {
                // Simplified: use different frequency bands
                let bandStart = i * frameSlice.count / chromaBins
                let bandEnd = (i + 1) * frameSlice.count / chromaBins
                
                var energy: Float = 0
                for j in bandStart..<bandEnd {
                    energy += frameSlice[j] * frameSlice[j]
                }
                chroma[i] = sqrt(energy / Float(bandEnd - bandStart))
            }
            
            // Normalize
            let maxVal = chroma.max() ?? 1.0
            if maxVal > 0 {
                chroma = chroma.map { $0 / maxVal }
            }
            
            chromagram.append(chroma)
        }
        
        return chromagram
    }
    
    private func computeRMSEnergy(samples: [Float]) -> [Float] {
        let frameCount = samples.count / hopSize
        var rms: [Float] = []
        
        for frameIndex in 0..<frameCount {
            let startSample = frameIndex * hopSize
            let endSample = min(startSample + hopSize, samples.count)
            
            var sumSquares: Float = 0
            for i in startSample..<endSample {
                sumSquares += samples[i] * samples[i]
            }
            
            let energy = sqrt(sumSquares / Float(endSample - startSample))
            rms.append(energy)
        }
        
        return rms
    }
    
    private func computeZeroCrossings(samples: [Float]) -> [Float] {
        let frameCount = samples.count / hopSize
        var zcr: [Float] = []
        
        for frameIndex in 0..<frameCount {
            let startSample = frameIndex * hopSize
            let endSample = min(startSample + hopSize, samples.count)
            
            var crossings = 0
            for i in (startSample + 1)..<endSample {
                if (samples[i] >= 0) != (samples[i - 1] >= 0) {
                    crossings += 1
                }
            }
            
            zcr.append(Float(crossings) / Float(endSample - startSample))
        }
        
        return zcr
    }
    
    private func computeSpectralCentroid(samples: [Float]) -> [Float] {
        let frameCount = samples.count / hopSize
        var centroids: [Float] = []
        
        for frameIndex in 0..<frameCount {
            let startSample = frameIndex * hopSize
            let endSample = min(startSample + hopSize, samples.count)
            
            // Simplified spectral centroid using autocorrelation
            var weightedSum: Float = 0
            var totalSum: Float = 0
            
            for i in startSample..<endSample {
                let absVal = abs(samples[i])
                let position = Float(i - startSample) / Float(endSample - startSample)
                weightedSum += absVal * position
                totalSum += absVal
            }
            
            let centroid = totalSum > 0 ? weightedSum / totalSum : 0.5
            centroids.append(centroid)
        }
        
        return centroids
    }
}

// MARK: - SignalCorrelator

/// Cross-correlates audio signals to find time offsets
public struct SignalCorrelator: Sendable {
    
    public struct CorrelationResult: Sendable {
        public let offset: Double      // Time offset in seconds
        public let confidence: Float   // 0 to 1
        public let peakValue: Float    // Raw correlation peak
    }
    
    public init() {}
    
    /// Cross-correlate two fingerprints to find offset
    public func crossCorrelate(
        reference: AudioFingerprint,
        candidate: AudioFingerprint
    ) -> CorrelationResult {
        // Use chromagram for correlation
        let refChroma = flattenChromagram(reference.chromagram)
        let candChroma = flattenChromagram(candidate.chromagram)
        
        guard !refChroma.isEmpty && !candChroma.isEmpty else {
            return CorrelationResult(offset: 0, confidence: 0, peakValue: 0)
        }
        
        // Cross-correlation using dot products at different lags
        let maxLag = min(refChroma.count, candChroma.count) / 2
        var bestLag = 0
        var bestCorrelation: Float = -Float.infinity
        
        for lag in -maxLag..<maxLag {
            var correlation: Float = 0
            var count = 0
            
            for i in 0..<min(refChroma.count, candChroma.count) {
                let refIndex = i
                let candIndex = i + lag
                
                if candIndex >= 0 && candIndex < candChroma.count {
                    correlation += refChroma[refIndex] * candChroma[candIndex]
                    count += 1
                }
            }
            
            if count > 0 {
                correlation /= Float(count)
                if correlation > bestCorrelation {
                    bestCorrelation = correlation
                    bestLag = lag
                }
            }
        }
        
        // Convert lag to time offset
        let offset = Double(bestLag * reference.hopSize) / reference.sampleRate
        
        // Normalize confidence
        let confidence = normalizeCorrelation(bestCorrelation)
        
        return CorrelationResult(
            offset: offset,
            confidence: confidence,
            peakValue: bestCorrelation
        )
    }
    
    /// Refine offset using waveform correlation
    public func refineWithWaveform(
        reference: AudioFingerprint,
        candidate: AudioFingerprint,
        initialOffset: Double
    ) -> CorrelationResult {
        // Use RMS energy for finer alignment
        let refRMS = reference.rmsEnergy
        let candRMS = candidate.rmsEnergy
        
        guard !refRMS.isEmpty && !candRMS.isEmpty else {
            return CorrelationResult(offset: initialOffset, confidence: 0, peakValue: 0)
        }
        
        // Search in a smaller window around initial offset
        let lagSamples = Int(initialOffset * reference.sampleRate) / reference.hopSize
        let searchWindow = Int(AdvancedAIDefaults.syncRefinementWindow * reference.sampleRate) / reference.hopSize
        
        var bestLag = lagSamples
        var bestCorrelation: Float = -Float.infinity
        
        for lag in (lagSamples - searchWindow)...(lagSamples + searchWindow) {
            var correlation: Float = 0
            var count = 0
            
            for i in 0..<min(refRMS.count, candRMS.count) {
                let candIndex = i + lag
                
                if candIndex >= 0 && candIndex < candRMS.count {
                    correlation += refRMS[i] * candRMS[candIndex]
                    count += 1
                }
            }
            
            if count > 0 {
                correlation /= Float(count)
                if correlation > bestCorrelation {
                    bestCorrelation = correlation
                    bestLag = lag
                }
            }
        }
        
        let offset = Double(bestLag * reference.hopSize) / reference.sampleRate
        let confidence = normalizeCorrelation(bestCorrelation)
        
        return CorrelationResult(
            offset: offset,
            confidence: confidence,
            peakValue: bestCorrelation
        )
    }
    
    /// Detect drift over time between two recordings
    public func detectDrift(
        reference: AudioFingerprint,
        candidate: AudioFingerprint,
        offset: Double
    ) -> Double? {
        // Compare correlation at start and end of recording
        let quarterLength = min(reference.frameCount, candidate.frameCount) / 4
        
        guard quarterLength > 10 else { return nil }
        
        // Correlation at start
        let startRef = Array(reference.rmsEnergy[0..<quarterLength])
        let lagSamples = Int(offset * reference.sampleRate) / reference.hopSize
        let startCandIndex = max(0, lagSamples)
        let startCandEnd = min(candidate.rmsEnergy.count, startCandIndex + quarterLength)
        
        guard startCandEnd > startCandIndex else { return nil }
        
        let startCand = Array(candidate.rmsEnergy[startCandIndex..<startCandEnd])
        
        // Correlation at end
        let endStart = reference.rmsEnergy.count - quarterLength
        let endRef = Array(reference.rmsEnergy[endStart..<reference.rmsEnergy.count])
        
        let endCandStart = max(0, candidate.rmsEnergy.count - quarterLength + lagSamples)
        let endCandEnd = min(candidate.rmsEnergy.count, endCandStart + quarterLength)
        
        guard endCandEnd > endCandStart else { return nil }
        
        let endCand = Array(candidate.rmsEnergy[endCandStart..<endCandEnd])
        
        // Find peak offset difference
        let startOffset = findPeakOffset(ref: startRef, cand: startCand)
        let endOffset = findPeakOffset(ref: endRef, cand: endCand)
        
        let driftSamples = endOffset - startOffset
        let driftSeconds = Double(driftSamples * reference.hopSize) / reference.sampleRate
        
        // Only return if drift is significant
        if abs(driftSeconds) > 0.01 {
            return driftSeconds
        }
        
        return nil
    }
    
    // MARK: - Private Helpers
    
    private func flattenChromagram(_ chromagram: [[Float]]) -> [Float] {
        return chromagram.flatMap { $0 }
    }
    
    private func normalizeCorrelation(_ value: Float) -> Float {
        // Convert correlation to 0-1 confidence
        return min(1.0, max(0, (value + 1) / 2))
    }
    
    private func findPeakOffset(ref: [Float], cand: [Float]) -> Int {
        let maxLag = min(ref.count, cand.count) / 4
        var bestLag = 0
        var bestCorr: Float = -Float.infinity
        
        for lag in -maxLag..<maxLag {
            var correlation: Float = 0
            var count = 0
            
            for i in 0..<min(ref.count, cand.count) {
                let candIndex = i + lag
                if candIndex >= 0 && candIndex < cand.count {
                    correlation += ref[i] * cand[candIndex]
                    count += 1
                }
            }
            
            if count > 0 {
                correlation /= Float(count)
                if correlation > bestCorr {
                    bestCorr = correlation
                    bestLag = lag
                }
            }
        }
        
        return bestLag
    }
}
