import Foundation
import AVFoundation

// MARK: - Ingest Options

/// Options for the ingestion pipeline
public struct IngestOptions: Sendable {
    public let extractAudio: Bool
    public let transcribe: Bool
    public let diarize: Bool
    public let analyzeVision: Bool
    public let generateThumbnails: Bool
    public let language: String
    
    public init(
        extractAudio: Bool = true,
        transcribe: Bool = false,
        diarize: Bool = false,
        analyzeVision: Bool = true,
        generateThumbnails: Bool = false,
        language: String = "en-US"
    ) {
        self.extractAudio = extractAudio
        self.transcribe = transcribe
        self.diarize = diarize
        self.analyzeVision = analyzeVision
        self.generateThumbnails = generateThumbnails
        self.language = language
    }
    
    public static let minimal = IngestOptions(
        extractAudio: false,
        transcribe: false,
        diarize: false,
        analyzeVision: false
    )
    
    public static let full = IngestOptions(
        extractAudio: true,
        transcribe: true,
        diarize: true,
        analyzeVision: true,
        generateThumbnails: true
    )
}

// MARK: - Footage Ingest Service

public class FootageIngestService {
    private let visionEngine: VisionAnalysisEngine
    private let audioExtractor: AudioExtractor
    private let audioAnalyzer: AudioMetricsAnalyzer
    private let transcriptionEngine: TranscriptionEngine
    private let speakerDiarizer: SpeakerDiarizer
    
    public init(
        visionEngine: VisionAnalysisEngine = VisionAnalysisEngine(),
        language: String = "en-US"
    ) {
        self.visionEngine = visionEngine
        self.audioExtractor = AudioExtractor()
        self.audioAnalyzer = AudioMetricsAnalyzer()
        self.transcriptionEngine = TranscriptionEngine(language: language)
        self.speakerDiarizer = SpeakerDiarizer()
    }
    
    // MARK: - Legacy API (backward compatible)
    
    public func ingestClip(url: URL) async throws -> FootageIndexRecord {
        // 1. Probe Metadata
        let profile = try await MediaProbe.probe(url: url)
        
        // 2. Generate Tags based on metadata
        var tags: [String] = []
        if profile.resolution.x >= 3840 { tags.append("4k") }
        if profile.fps > 59 { tags.append("hfr") }
        if let codec = Optional(profile.codec), codec.contains("hvc1") { tags.append("hevc") }
        
        return FootageIndexRecord(
            profile: profile,
            tags: tags
        )
    }
    
    // MARK: - Full Ingestion Pipeline
    
    /// Ingest a media file with full analysis pipeline
    /// Returns IndexedFootageRecord with all analysis results
    public func ingestClipFull(
        url: URL,
        options: IngestOptions = IngestOptions()
    ) async throws -> IndexedFootageRecord {
        let startTime = Date()
        var issues: [String] = []
        
        // Validate file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            return IndexedFootageRecord(
                sourcePath: url.path,
                status: .failed,
                error: "File not found"
            )
        }
        
        // Step 1: Probe media file
        let mediaProfile: EnhancedMediaProfile
        do {
            mediaProfile = try await EnhancedMediaProbe.probe(url)
        } catch {
            return IndexedFootageRecord(
                sourcePath: url.path,
                status: .failed,
                error: "Failed to probe media: \(error.localizedDescription)"
            )
        }
        
        // Step 2: Extract and analyze audio (if requested)
        var audioMetrics: AudioMetrics? = nil
        var transcript: Transcript? = nil
        var diarization: DiarizationResult? = nil
        
        if options.extractAudio && mediaProfile.hasAudio {
            do {
                // Extract audio to temp file
                let audioResult = try await audioExtractor.extract(from: url)
                
                // Compute audio metrics
                audioMetrics = try await computeAudioMetrics(from: audioResult.outputURL)
                
                // Transcribe if requested
                if options.transcribe {
                    do {
                        transcript = try await transcriptionEngine.transcribe(audioURL: audioResult.outputURL)
                    } catch {
                        issues.append("Transcription failed: \(error.localizedDescription)")
                    }
                }
                
                // Diarize if requested
                if options.diarize {
                    do {
                        diarization = try await speakerDiarizer.diarize(url: audioResult.outputURL)
                    } catch {
                        issues.append("Diarization failed: \(error.localizedDescription)")
                    }
                }
                
                // Clean up temp audio file
                try? FileManager.default.removeItem(at: audioResult.outputURL)
                
            } catch {
                issues.append("Audio extraction failed: \(error.localizedDescription)")
            }
        }
        
        // Step 3: Vision analysis (if requested)
        var sceneDetection: SceneDetectionResult? = nil
        
        if options.analyzeVision && mediaProfile.hasVideo {
            do {
                sceneDetection = try await analyzeVideoContent(url: url, profile: mediaProfile)
            } catch {
                issues.append("Vision analysis failed: \(error.localizedDescription)")
            }
        }
        
        // Step 4: Compute quality score
        let qualityScore = computeQualityScore(
            profile: mediaProfile,
            audioMetrics: audioMetrics,
            issues: issues
        )
        
        // Step 5: Detect any quality issues
        issues.append(contentsOf: detectQualityIssues(profile: mediaProfile))
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        return IndexedFootageRecord(
            sourcePath: url.path,
            mediaProfile: mediaProfile,
            sceneDetection: sceneDetection,
            audioMetrics: audioMetrics,
            transcript: transcript,
            diarization: diarization,
            qualityScore: qualityScore,
            issues: issues,
            status: .complete,
            processingTime: processingTime
        )
    }
    
    // MARK: - Private Helpers
    
    private func computeAudioMetrics(from audioURL: URL) async throws -> AudioMetrics {
        // Use the AudioMetricsAnalyzer for detailed analysis
        return try await audioAnalyzer.analyze(url: audioURL)
    }
    
    private func analyzeVideoContent(url: URL, profile: EnhancedMediaProfile) async throws -> SceneDetectionResult {
        // Use SceneDetector for proper scene analysis
        let detector = SceneDetector()
        return try await detector.detectShots(in: url)
    }
    
    private func computeQualityScore(
        profile: EnhancedMediaProfile,
        audioMetrics: AudioMetrics?,
        issues: [String]
    ) -> Float {
        var score: Float = 1.0
        
        // Penalize for issues
        score -= Float(issues.count) * 0.1
        
        // Boost for high resolution
        if let video = profile.video {
            if video.width >= 3840 { score += 0.1 }
            if video.width >= 1920 { score += 0.05 }
        }
        
        // Penalize for low bitrate (if available)
        if let video = profile.video, let bitrate = video.bitrate, bitrate < 5_000_000 {
            score -= 0.1
        }
        
        return max(0, min(1, score))
    }
    
    private func detectQualityIssues(profile: EnhancedMediaProfile) -> [String] {
        var issues: [String] = []
        
        // Check video quality
        if let video = profile.video {
            if video.width < 1280 {
                issues.append("Low resolution: \(video.width)x\(video.height)")
            }
            if let bitrate = video.bitrate, bitrate < 2_000_000 {
                issues.append("Low bitrate: \(bitrate / 1000)kbps")
            }
        }
        
        // Check for missing audio
        if !profile.hasAudio {
            issues.append("No audio track")
        }
        
        // Check duration
        if profile.duration < 1.0 {
            issues.append("Very short duration: \(profile.duration)s")
        }
        
        return issues
    }
}

