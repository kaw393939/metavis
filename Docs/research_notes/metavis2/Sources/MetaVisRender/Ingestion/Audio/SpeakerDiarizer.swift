// Sources/MetaVisRender/Ingestion/Audio/SpeakerDiarizer.swift
// Sprint 03: Speaker diarization - who spoke when

import AVFoundation
import Accelerate
import Foundation

// Note: Speaker, SpeakerSegment, and DiarizationResult types are defined in TranscriptTypes.swift

// MARK: - Speaker Diarizer

/// Identifies and segments speakers in audio
/// Uses voice embeddings and clustering to determine who spoke when
public actor SpeakerDiarizer {
    
    // MARK: - Configuration
    
    public struct Config: Sendable {
        /// Minimum segment duration (seconds)
        public let minSegmentDuration: Double
        /// Maximum number of speakers to detect
        public let maxSpeakers: Int
        /// Clustering threshold (0-1, lower = more speakers)
        public let clusteringThreshold: Float
        /// Embedding dimension
        public let embeddingDimension: Int
        /// Frame size for analysis (seconds)
        public let frameSize: Double
        /// Hop size between frames (seconds)
        public let hopSize: Double
        
        public init(
            minSegmentDuration: Double = 0.5,
            maxSpeakers: Int = 10,
            clusteringThreshold: Float = 0.6,
            embeddingDimension: Int = 128,
            frameSize: Double = 1.5,
            hopSize: Double = 0.25
        ) {
            self.minSegmentDuration = minSegmentDuration
            self.maxSpeakers = maxSpeakers
            self.clusteringThreshold = clusteringThreshold
            self.embeddingDimension = embeddingDimension
            self.frameSize = frameSize
            self.hopSize = hopSize
        }
        
        public static let `default` = Config()
        
        /// Single speaker - very aggressive merging
        public static let monologue = Config(
            minSegmentDuration: 1.0,
            maxSpeakers: 1,
            clusteringThreshold: 0.3,  // Merge almost everything
            frameSize: 2.0,
            hopSize: 0.5
        )
        
        /// Interview - expect 2-4 distinct speakers
        public static let interview = Config(
            minSegmentDuration: 0.5,
            maxSpeakers: 4,
            clusteringThreshold: 0.75  // Higher = more merging
        )
        
        /// Podcast - expect multiple speakers with clear turns
        public static let podcast = Config(
            minSegmentDuration: 0.5,
            maxSpeakers: 6,
            clusteringThreshold: 0.70
        )
        
        /// Conversation - balanced detection
        public static let conversation = Config(
            minSegmentDuration: 0.3,
            maxSpeakers: 8,
            clusteringThreshold: 0.65
        )
    }
    
    private let config: Config
    
    public init(config: Config = .default) {
        self.config = config
    }
    
    // MARK: - Public API
    
    /// Perform speaker diarization on audio file
    public func diarize(url: URL) async throws -> DiarizationResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw IngestionError.fileNotFound(url)
        }
        
        // Load audio
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        let sampleRate = format.sampleRate
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw IngestionError.insufficientMemory
        }
        try audioFile.read(into: buffer)
        
        // Extract embeddings for each frame
        let frameEmbeddings = extractFrameEmbeddings(from: buffer, sampleRate: sampleRate)
        
        guard !frameEmbeddings.isEmpty else {
            return DiarizationResult(
                speakers: [],
                segments: []
            )
        }
        
        // Cluster embeddings to identify speakers
        let clusters = clusterEmbeddings(frameEmbeddings)
        
        // Build segments from clusters
        let segments = buildSegments(from: clusters, hopSize: config.hopSize)
        
        // Merge short segments
        let mergedSegments = mergeShortSegments(segments)
        
        // Build speaker profiles
        let speakers = buildSpeakerProfiles(from: mergedSegments, embeddings: frameEmbeddings)
        
        return DiarizationResult(
            speakers: speakers,
            segments: mergedSegments
        )
    }
    
    /// Diarize with speech segments hint (from VAD)
    public func diarize(url: URL, speechSegments: [SpeechActivity]) async throws -> DiarizationResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw IngestionError.fileNotFound(url)
        }
        
        // Load audio
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        let sampleRate = format.sampleRate
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw IngestionError.insufficientMemory
        }
        try audioFile.read(into: buffer)
        
        // Only analyze speech segments
        var allEmbeddings: [(time: Double, embedding: [Float])] = []
        
        for segment in speechSegments where segment.isSpeech {
            let segmentEmbeddings = extractFrameEmbeddings(
                from: buffer,
                sampleRate: sampleRate,
                startTime: segment.start,
                endTime: segment.end
            )
            allEmbeddings.append(contentsOf: segmentEmbeddings)
        }
        
        guard !allEmbeddings.isEmpty else {
            return DiarizationResult(
                speakers: [],
                segments: []
            )
        }
        
        // Cluster and build result
        let clusters = clusterEmbeddings(allEmbeddings)
        let segments = buildSegments(from: clusters, hopSize: config.hopSize)
        let mergedSegments = mergeShortSegments(segments)
        let speakers = buildSpeakerProfiles(from: mergedSegments, embeddings: allEmbeddings)
        
        return DiarizationResult(
            speakers: speakers,
            segments: mergedSegments
        )
    }
    
    // MARK: - Embedding Extraction
    
    private func extractFrameEmbeddings(
        from buffer: AVAudioPCMBuffer,
        sampleRate: Double,
        startTime: Double = 0,
        endTime: Double? = nil
    ) -> [(time: Double, embedding: [Float])] {
        guard let channelData = buffer.floatChannelData else { return [] }
        
        let frameLength = Int(buffer.frameLength)
        let duration = Double(frameLength) / sampleRate
        let actualEndTime = endTime ?? duration
        
        let frameSamples = Int(config.frameSize * sampleRate)
        let hopSamples = Int(config.hopSize * sampleRate)
        
        var embeddings: [(time: Double, embedding: [Float])] = []
        var currentSample = Int(startTime * sampleRate)
        let endSample = min(Int(actualEndTime * sampleRate), frameLength - frameSamples)
        
        while currentSample < endSample {
            // Mix channels to mono
            var monoFrame = [Float](repeating: 0, count: frameSamples)
            let channelCount = Int(buffer.format.channelCount)
            
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for i in 0..<frameSamples {
                    monoFrame[i] += samples[currentSample + i]
                }
            }
            
            for i in 0..<frameSamples {
                monoFrame[i] /= Float(channelCount)
            }
            
            // Extract embedding (simplified MFCC-like features)
            let embedding = extractEmbedding(from: monoFrame, sampleRate: sampleRate)
            let time = Double(currentSample) / sampleRate
            embeddings.append((time: time, embedding: embedding))
            
            currentSample += hopSamples
        }
        
        return embeddings
    }
    
    private func extractEmbedding(from samples: [Float], sampleRate: Double) -> [Float] {
        // Simplified speaker embedding using spectral features
        // Real implementation would use a neural network (e.g., ECAPA-TDNN)
        
        let fftSize = 512
        let numBands = config.embeddingDimension / 4
        
        // Compute power spectrum
        var spectrum = [Float](repeating: 0, count: fftSize / 2)
        
        // Simple DFT for each band (approximation)
        for band in 0..<numBands {
            let freqBin = band * (fftSize / 2) / numBands
            var real: Float = 0
            var imag: Float = 0
            
            let binFreq = Double(freqBin) * sampleRate / Double(fftSize)
            let omega = 2.0 * Double.pi * binFreq / sampleRate
            
            for i in 0..<min(samples.count, fftSize) {
                let phase = omega * Double(i)
                real += samples[i] * Float(cos(phase))
                imag += samples[i] * Float(sin(phase))
            }
            
            spectrum[freqBin] = sqrt(real * real + imag * imag)
        }
        
        // Convert to mel-like scale and take log
        var embedding = [Float](repeating: 0, count: config.embeddingDimension)
        
        for i in 0..<numBands {
            let power = max(1e-10, spectrum[i])
            embedding[i] = log10(power)
        }
        
        // Add delta features (temporal derivatives)
        for i in 0..<numBands {
            embedding[numBands + i] = embedding[i]  // Simplified
        }
        
        // Add statistics
        var mean: Float = 0
        var variance: Float = 0
        vDSP_meanv(embedding, 1, &mean, vDSP_Length(numBands))
        
        for i in 0..<numBands {
            let diff = embedding[i] - mean
            variance += diff * diff
        }
        variance /= Float(numBands)
        
        // Fill remaining dimensions with statistics
        for i in (numBands * 2)..<config.embeddingDimension {
            if i % 2 == 0 {
                embedding[i] = mean
            } else {
                embedding[i] = sqrt(variance)
            }
        }
        
        // Normalize
        var norm: Float = 0
        vDSP_svesq(embedding, 1, &norm, vDSP_Length(config.embeddingDimension))
        norm = sqrt(norm)
        
        if norm > 0 {
            for i in embedding.indices {
                embedding[i] /= norm
            }
        }
        
        return embedding
    }
    
    // MARK: - Clustering
    
    private func clusterEmbeddings(_ embeddings: [(time: Double, embedding: [Float])]) -> [(time: Double, clusterId: Int)] {
        guard !embeddings.isEmpty else { return [] }
        
        // For large datasets, use sampling + assignment approach
        let maxDirectClustering = 500
        
        if embeddings.count > maxDirectClustering {
            return clusterWithSampling(embeddings, sampleSize: maxDirectClustering)
        }
        
        // For smaller datasets, use full agglomerative clustering
        return agglomerativeClustering(embeddings)
    }
    
    /// Fast clustering for large datasets: cluster a sample, then assign the rest
    private func clusterWithSampling(
        _ embeddings: [(time: Double, embedding: [Float])],
        sampleSize: Int
    ) -> [(time: Double, clusterId: Int)] {
        // Sample evenly across the timeline
        let step = embeddings.count / sampleSize
        var sampleIndices: [Int] = []
        for i in stride(from: 0, to: embeddings.count, by: max(1, step)) {
            sampleIndices.append(i)
            if sampleIndices.count >= sampleSize { break }
        }
        
        let sampledEmbeddings = sampleIndices.map { embeddings[$0] }
        
        // Cluster the sample
        let sampleClusters = agglomerativeClustering(sampledEmbeddings)
        
        // Build cluster centroids from sample
        var clusterCentroids: [Int: [Float]] = [:]
        var clusterCounts: [Int: Int] = [:]
        
        for (idx, cluster) in sampleClusters.enumerated() {
            let embedding = sampledEmbeddings[idx].embedding
            if clusterCentroids[cluster.clusterId] == nil {
                clusterCentroids[cluster.clusterId] = embedding
                clusterCounts[cluster.clusterId] = 1
            } else {
                // Running average
                let count = clusterCounts[cluster.clusterId]!
                var centroid = clusterCentroids[cluster.clusterId]!
                for i in centroid.indices {
                    centroid[i] = (centroid[i] * Float(count) + embedding[i]) / Float(count + 1)
                }
                clusterCentroids[cluster.clusterId] = centroid
                clusterCounts[cluster.clusterId] = count + 1
            }
        }
        
        // Assign all embeddings to nearest centroid
        var result: [(time: Double, clusterId: Int)] = []
        
        for embedding in embeddings {
            var bestCluster = 0
            var bestSimilarity: Float = -Float.infinity
            
            for (clusterId, centroid) in clusterCentroids {
                let sim = cosineSimilarity(embedding.embedding, centroid)
                if sim > bestSimilarity {
                    bestSimilarity = sim
                    bestCluster = clusterId
                }
            }
            
            result.append((time: embedding.time, clusterId: bestCluster))
        }
        
        return result.sorted { $0.time < $1.time }
    }
    
    /// Standard agglomerative clustering for smaller datasets
    private func agglomerativeClustering(_ embeddings: [(time: Double, embedding: [Float])]) -> [(time: Double, clusterId: Int)] {
        var clusters: [[Int]] = embeddings.indices.map { [$0] }
        var clusterEmbeddings: [[Float]] = embeddings.map { $0.embedding }
        
        // Keep merging until we hit constraints
        while clusters.count > 1 {
            // Find most similar pair
            var bestI = 0, bestJ = 1
            var bestSimilarity: Float = -Float.infinity
            
            for i in 0..<clusters.count {
                for j in (i + 1)..<clusters.count {
                    let sim = cosineSimilarity(clusterEmbeddings[i], clusterEmbeddings[j])
                    if sim > bestSimilarity {
                        bestSimilarity = sim
                        bestI = i
                        bestJ = j
                    }
                }
            }
            
            // Stop conditions:
            // 1. If we're at maxSpeakers and similarity is below threshold, stop
            // 2. If similarity is very low (< 0.2), voices are too different
            let shouldStop = (clusters.count <= config.maxSpeakers && bestSimilarity < config.clusteringThreshold) ||
                             bestSimilarity < 0.2
            
            if shouldStop {
                break
            }
            
            // Merge the most similar clusters
            clusters[bestI].append(contentsOf: clusters[bestJ])
            clusters.remove(at: bestJ)
            
            // Update centroid
            let newCentroid = averageEmbedding(clusters[bestI].map { embeddings[$0].embedding })
            clusterEmbeddings[bestI] = newCentroid
            clusterEmbeddings.remove(at: bestJ)
        }
        
        // Assign cluster IDs to each frame
        var result: [(time: Double, clusterId: Int)] = []
        
        for (clusterIdx, cluster) in clusters.enumerated() {
            for frameIdx in cluster {
                result.append((time: embeddings[frameIdx].time, clusterId: clusterIdx))
            }
        }
        
        return result.sorted { $0.time < $1.time }
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        
        return dot  // Already normalized
    }
    
    private func averageEmbedding(_ embeddings: [[Float]]) -> [Float] {
        guard let first = embeddings.first else { return [] }
        
        var result = [Float](repeating: 0, count: first.count)
        
        for embedding in embeddings {
            for i in result.indices {
                result[i] += embedding[i]
            }
        }
        
        let count = Float(embeddings.count)
        for i in result.indices {
            result[i] /= count
        }
        
        return result
    }
    
    // MARK: - Segment Building
    
    private func buildSegments(from clusters: [(time: Double, clusterId: Int)], hopSize: Double) -> [SpeakerSegment] {
        guard !clusters.isEmpty else { return [] }
        
        var segments: [SpeakerSegment] = []
        var currentSpeaker = clusters[0].clusterId
        var segmentStart = clusters[0].time
        
        for i in 1..<clusters.count {
            if clusters[i].clusterId != currentSpeaker {
                // End current segment
                let segment = SpeakerSegment(
                    speakerId: "SPEAKER_\(String(format: "%02d", currentSpeaker))",
                    start: segmentStart,
                    end: clusters[i - 1].time + hopSize,
                    confidence: 0.8  // Placeholder
                )
                segments.append(segment)
                
                // Start new segment
                currentSpeaker = clusters[i].clusterId
                segmentStart = clusters[i].time
            }
        }
        
        // Add final segment
        if let last = clusters.last {
            let segment = SpeakerSegment(
                speakerId: "SPEAKER_\(String(format: "%02d", currentSpeaker))",
                start: segmentStart,
                end: last.time + hopSize,
                confidence: 0.8
            )
            segments.append(segment)
        }
        
        return segments
    }
    
    private func mergeShortSegments(_ segments: [SpeakerSegment]) -> [SpeakerSegment] {
        guard segments.count > 1 else { return segments }
        
        var merged: [SpeakerSegment] = []
        var current = segments[0]
        
        for i in 1..<segments.count {
            let next = segments[i]
            
            // Merge if same speaker and short gap, or if segment too short
            let gap = next.start - current.end
            let shouldMerge = (current.speakerId == next.speakerId && gap < 0.3) ||
                              current.duration < config.minSegmentDuration
            
            if shouldMerge && current.speakerId == next.speakerId {
                current = SpeakerSegment(
                    speakerId: current.speakerId,
                    start: current.start,
                    end: next.end,
                    confidence: (current.confidence + next.confidence) / 2
                )
            } else {
                if current.duration >= config.minSegmentDuration {
                    merged.append(current)
                }
                current = next
            }
        }
        
        if current.duration >= config.minSegmentDuration {
            merged.append(current)
        }
        
        return merged
    }
    
    private func buildSpeakerProfiles(
        from segments: [SpeakerSegment],
        embeddings: [(time: Double, embedding: [Float])]
    ) -> [Speaker] {
        // Group segments by speaker
        var speakerSegments: [String: [SpeakerSegment]] = [:]
        
        for segment in segments {
            speakerSegments[segment.speakerId, default: []].append(segment)
        }
        
        // Build profiles
        var speakers: [Speaker] = []
        
        for (speakerId, segs) in speakerSegments.sorted(by: { $0.key < $1.key }) {
            let totalTime = segs.reduce(0) { $0 + $1.duration }
            
            // Get embeddings for this speaker
            let speakerEmbeddings = embeddings.filter { emb in
                segs.contains { seg in
                    emb.time >= seg.start && emb.time < seg.end
                }
            }.map { $0.embedding }
            
            let avgEmbedding = speakerEmbeddings.isEmpty ? nil : averageEmbedding(speakerEmbeddings)
            
            let speaker = Speaker(
                id: speakerId,
                label: nil,
                embedding: avgEmbedding,
                totalSpeakingTime: totalTime,
                segmentCount: segs.count
            )
            speakers.append(speaker)
        }
        
        return speakers.sorted { $0.totalSpeakingTime > $1.totalSpeakingTime }
    }
}
