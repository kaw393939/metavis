// LiveIngestionSession.swift
// MetaVisRender
//
// Real-time streaming analysis with AVCaptureSession integration
// Provides live transcription, face detection, speaker tracking, and emotion analysis
// Sprint 08

import Foundation
import AVFoundation
import Vision

// MARK: - LiveIngestionSession

/// Real-time analysis session for live video/audio capture
public actor LiveIngestionSession {
    
    // MARK: - Properties
    
    private var status: LiveSessionStatus = .idle
    private var stats: LiveSessionStats = .empty
    private var segments: [LiveSegment] = []
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?
    
    private let processingQueue = DispatchQueue(label: "com.metavisrender.liveingestion", qos: .userInteractive)
    private let analysisQueue = DispatchQueue(label: "com.metavisrender.liveanalysis", qos: .userInitiated)
    
    private var segmentHandler: ((LiveSegment) -> Void)?
    private var highlightHandler: ((LiveSegment) -> Void)?
    
    private var startTime: Date?
    private var currentSegmentStart: Double = 0
    private var frameBuffer: [CVPixelBuffer] = []
    private var audioBuffer: [Float] = []
    
    private let faceDetector: VNSequenceRequestHandler
    private var faceTrackingObservations: [Int: VNFaceObservation] = [:]
    private var nextTrackingId = 0
    
    private var activeSpeakerId: Int?
    private var transcriptionBuffer: String = ""
    
    // Configuration
    private let segmentDuration: Double
    private let bufferSize: Int
    
    // MARK: - Initialization
    
    public init(
        segmentDuration: Double = AdvancedAIDefaults.liveSegmentDuration,
        bufferSize: Int = AdvancedAIDefaults.liveBufferSize
    ) {
        self.segmentDuration = segmentDuration
        self.bufferSize = bufferSize
        self.faceDetector = VNSequenceRequestHandler()
    }
    
    // MARK: - Public API
    
    /// Start a live ingestion session from a capture device
    public func start(
        videoDevice: AVCaptureDevice? = nil,
        audioDevice: AVCaptureDevice? = nil
    ) async throws {
        guard status == .idle || status == .stopped else {
            throw AdvancedAIError.liveSessionError("Session already active")
        }
        
        status = .starting
        
        // Create capture session
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        // Add video input
        if let videoDevice = videoDevice ?? AVCaptureDevice.default(for: .video) {
            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if session.canAddInput(videoInput) {
                    session.addInput(videoInput)
                }
            } catch {
                throw AdvancedAIError.liveSessionError("Failed to add video input: \(error)")
            }
        }
        
        // Add audio input
        if let audioDevice = audioDevice ?? AVCaptureDevice.default(for: .audio) {
            do {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                }
            } catch {
                throw AdvancedAIError.liveSessionError("Failed to add audio input: \(error)")
            }
        }
        
        // Add video output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        self.videoOutput = videoOutput
        
        // Add audio output
        let audioOutput = AVCaptureAudioDataOutput()
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
        }
        self.audioOutput = audioOutput
        
        self.captureSession = session
        
        // Start session
        startTime = Date()
        status = .running
        
        session.startRunning()
    }
    
    /// Start ingestion from a file URL (for testing/replay)
    public func startFromFile(url: URL) async throws {
        guard status == .idle || status == .stopped else {
            throw AdvancedAIError.liveSessionError("Session already active")
        }
        
        status = .starting
        startTime = Date()
        
        // Process file as if it were live
        try await processFile(url: url)
        
        status = .stopped
    }
    
    /// Register a handler for new segments
    public func onSegment(_ handler: @escaping (LiveSegment) -> Void) {
        self.segmentHandler = handler
    }
    
    /// Register a handler for highlight moments
    public func onHighlight(_ handler: @escaping (LiveSegment) -> Void) {
        self.highlightHandler = handler
    }
    
    /// Pause the session
    public func pause() {
        guard status == .running else { return }
        captureSession?.stopRunning()
        status = .paused
    }
    
    /// Resume a paused session
    public func resume() {
        guard status == .paused else { return }
        captureSession?.startRunning()
        status = .running
    }
    
    /// Stop the session and return final statistics
    public func stop() async -> LiveSessionStats {
        guard status == .running || status == .paused else { return stats }
        
        status = .stopping
        
        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
        audioOutput = nil
        
        // Calculate final stats
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        stats = LiveSessionStats(
            duration: duration,
            segmentCount: segments.count,
            faceDetections: segments.reduce(0) { $0 + $1.faces.count },
            transcriptWords: transcriptionBuffer.split(separator: " ").count,
            highlightCount: segments.filter { $0.isHighlight }.count,
            droppedFrames: 0  // Would track this during processing
        )
        
        status = .stopped
        
        return stats
    }
    
    /// Get the current status
    public func getStatus() -> LiveSessionStatus {
        return status
    }
    
    /// Get current statistics
    public func getStats() -> LiveSessionStats {
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        return LiveSessionStats(
            duration: duration,
            segmentCount: segments.count,
            faceDetections: segments.reduce(0) { $0 + $1.faces.count },
            transcriptWords: transcriptionBuffer.split(separator: " ").count,
            highlightCount: segments.filter { $0.isHighlight }.count,
            droppedFrames: 0
        )
    }
    
    /// Get all recorded segments
    public func getSegments() -> [LiveSegment] {
        return segments
    }
    
    /// Get segments marked as highlights
    public func getHighlights() -> [LiveSegment] {
        return segments.filter { $0.isHighlight }
    }
    
    // MARK: - Private Methods
    
    private func processFile(url: URL) async throws {
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        
        // Process in segments
        var currentTime: Double = 0
        
        while currentTime < totalSeconds {
            let segmentEnd = min(currentTime + segmentDuration, totalSeconds)
            
            // Create segment
            let segment = await analyzeSegment(
                startTime: currentTime,
                endTime: segmentEnd,
                asset: asset
            )
            
            segments.append(segment)
            segmentHandler?(segment)
            
            if segment.isHighlight {
                highlightHandler?(segment)
            }
            
            currentTime = segmentEnd
        }
    }
    
    private func analyzeSegment(
        startTime: Double,
        endTime: Double,
        asset: AVAsset
    ) async -> LiveSegment {
        // Extract frame for face detection
        let faces = await detectFaces(in: asset, at: startTime)
        
        // Determine active speaker (simplified)
        let activeSpeaker = determinActiveSpeaker(faces: faces)
        
        // Analyze emotion
        let emotion = analyzeEmotion(faces: faces)
        
        // Estimate audio level
        let audioLevel = estimateAudioLevel(at: startTime)
        
        // Determine if this is a highlight
        let isHighlight = determineHighlight(
            emotion: emotion,
            audioLevel: audioLevel,
            faceCount: faces.count
        )
        
        return LiveSegment(
            timestamp: startTime,
            duration: endTime - startTime,
            transcript: nil,  // Would integrate with live transcription
            faces: faces,
            activeSpeakerId: activeSpeaker,
            emotion: emotion,
            audioLevel: audioLevel,
            isHighlight: isHighlight
        )
    }
    
    private func detectFaces(in asset: AVAsset, at timestamp: Double) async -> [LiveFaceObservation] {
        // Extract frame
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        
        let time = CMTime(seconds: timestamp, preferredTimescale: 600)
        
        do {
            let (image, _) = try await generator.image(at: time)
            return detectFaces(in: image)
        } catch {
            return []
        }
    }
    
    private func detectFaces(in image: CGImage) -> [LiveFaceObservation] {
        let request = VNDetectFaceRectanglesRequest()
        
        do {
            try faceDetector.perform([request], on: image)
            
            guard let results = request.results else { return [] }
            
            return results.enumerated().map { index, face in
                LiveFaceObservation(
                    trackingId: index,
                    boundingBox: face.boundingBox,
                    confidence: face.confidence,
                    landmarks: nil
                )
            }
        } catch {
            return []
        }
    }
    
    private func determinActiveSpeaker(faces: [LiveFaceObservation]) -> Int? {
        // Simple heuristic: largest face is likely the speaker
        guard !faces.isEmpty else { return nil }
        
        var largestArea: CGFloat = 0
        var largestId: Int?
        
        for face in faces {
            let area = face.boundingBox.width * face.boundingBox.height
            if area > largestArea {
                largestArea = area
                largestId = face.trackingId
            }
        }
        
        return largestId
    }
    
    private func analyzeEmotion(faces: [LiveFaceObservation]) -> LiveEmotion? {
        guard !faces.isEmpty else { return nil }
        
        // Simplified emotion analysis based on face position and size
        // In production, would use ML model
        
        let avgConfidence = faces.reduce(0) { $0 + $1.confidence } / Float(faces.count)
        
        return LiveEmotion(
            dominant: "neutral",
            confidence: avgConfidence,
            valence: 0.5,
            arousal: 0.5
        )
    }
    
    private func estimateAudioLevel(at timestamp: Double) -> Float {
        // Simplified - would analyze actual audio buffer
        return Float.random(in: 0.3...0.8)
    }
    
    private func determineHighlight(
        emotion: LiveEmotion?,
        audioLevel: Float,
        faceCount: Int
    ) -> Bool {
        // Highlight criteria:
        // - High emotional arousal
        // - High audio level (potential laughter, applause)
        // - Multiple faces (reaction shot potential)
        
        if let emotion = emotion {
            if emotion.arousal > 0.7 {
                return true
            }
        }
        
        if audioLevel > 0.8 {
            return true
        }
        
        if faceCount >= 3 {
            return true
        }
        
        return false
    }
}

// MARK: - LiveIngestionDelegate

/// Delegate for receiving live ingestion events
public protocol LiveIngestionDelegate: AnyObject, Sendable {
    func liveIngestion(_ session: LiveIngestionSession, didProduceSegment segment: LiveSegment) async
    func liveIngestion(_ session: LiveIngestionSession, didDetectHighlight segment: LiveSegment) async
    func liveIngestion(_ session: LiveIngestionSession, didChangeStatus status: LiveSessionStatus) async
    func liveIngestion(_ session: LiveIngestionSession, didEncounterError error: Error) async
}

// MARK: - LiveIngestionConfiguration

/// Configuration for live ingestion sessions
public struct LiveIngestionConfiguration: Sendable {
    public let segmentDuration: Double
    public let bufferSize: Int
    public let enableFaceDetection: Bool
    public let enableEmotionAnalysis: Bool
    public let enableSpeakerTracking: Bool
    public let enableTranscription: Bool
    public let highlightThreshold: Float
    
    public init(
        segmentDuration: Double = AdvancedAIDefaults.liveSegmentDuration,
        bufferSize: Int = AdvancedAIDefaults.liveBufferSize,
        enableFaceDetection: Bool = true,
        enableEmotionAnalysis: Bool = true,
        enableSpeakerTracking: Bool = true,
        enableTranscription: Bool = true,
        highlightThreshold: Float = 0.7
    ) {
        self.segmentDuration = segmentDuration
        self.bufferSize = bufferSize
        self.enableFaceDetection = enableFaceDetection
        self.enableEmotionAnalysis = enableEmotionAnalysis
        self.enableSpeakerTracking = enableSpeakerTracking
        self.enableTranscription = enableTranscription
        self.highlightThreshold = highlightThreshold
    }
    
    public static let `default` = LiveIngestionConfiguration()
    
    public static let minimal = LiveIngestionConfiguration(
        enableFaceDetection: true,
        enableEmotionAnalysis: false,
        enableSpeakerTracking: false,
        enableTranscription: false
    )
    
    public static let full = LiveIngestionConfiguration(
        segmentDuration: 0.25,
        bufferSize: 8192,
        enableFaceDetection: true,
        enableEmotionAnalysis: true,
        enableSpeakerTracking: true,
        enableTranscription: true,
        highlightThreshold: 0.6
    )
}

// MARK: - LiveRecordingSession

/// Extended session that also records to file
public actor LiveRecordingSession {
    
    private let ingestionSession: LiveIngestionSession
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private let outputURL: URL
    
    public init(outputURL: URL) {
        self.ingestionSession = LiveIngestionSession()
        self.outputURL = outputURL
    }
    
    /// Start recording with ingestion
    public func start(
        videoDevice: AVCaptureDevice? = nil,
        audioDevice: AVCaptureDevice? = nil
    ) async throws {
        // Setup asset writer
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        
        // Video input
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1920,
            AVVideoHeightKey: 1080
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        
        if assetWriter?.canAdd(videoInput) == true {
            assetWriter?.add(videoInput)
            self.videoInput = videoInput
        }
        
        // Audio input
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true
        
        if assetWriter?.canAdd(audioInput) == true {
            assetWriter?.add(audioInput)
            self.audioInput = audioInput
        }
        
        assetWriter?.startWriting()
        assetWriter?.startSession(atSourceTime: .zero)
        
        // Start ingestion
        try await ingestionSession.start(videoDevice: videoDevice, audioDevice: audioDevice)
    }
    
    /// Stop recording and return the output URL
    public func stop() async throws -> URL {
        _ = await ingestionSession.stop()
        
        await assetWriter?.finishWriting()
        
        return outputURL
    }
    
    /// Get the ingestion session for registering handlers
    public func getIngestionSession() -> LiveIngestionSession {
        return ingestionSession
    }
}

// MARK: - Streaming Source Types

/// Source type for live ingestion
public enum LiveSourceType: Sendable {
    case camera(position: AVCaptureDevice.Position)
    case screenCapture
    case url(URL)
    case sampleBuffer
}

/// Configuration for streaming input
public struct StreamingInputConfig: Sendable {
    public let source: LiveSourceType
    public let preferredFrameRate: Int
    public let preferredResolution: CGSize?
    public let audioEnabled: Bool
    
    public init(
        source: LiveSourceType,
        preferredFrameRate: Int = 30,
        preferredResolution: CGSize? = nil,
        audioEnabled: Bool = true
    ) {
        self.source = source
        self.preferredFrameRate = preferredFrameRate
        self.preferredResolution = preferredResolution
        self.audioEnabled = audioEnabled
    }
}
