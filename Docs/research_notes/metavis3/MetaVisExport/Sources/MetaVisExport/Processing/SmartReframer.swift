// SmartReframer.swift
// MetaVisRender
//
// Created for Sprint 13: Export & Delivery
// AI-based reframing using Vision framework for subject tracking

import Foundation
import Vision
import Metal
import CoreImage
import CoreVideo

// MARK: - SubjectTrackingMode

/// Mode for subject tracking
public enum SubjectTrackingMode: String, Codable, Sendable {
    /// Track faces only
    case face
    
    /// Track salient regions
    case saliency
    
    /// Combine face and saliency detection
    case hybrid
    
    /// Track specific object
    case objectTracking
}

// MARK: - ReframeResult

/// Result of a reframe analysis
public struct ReframeResult: Sendable {
    /// Suggested crop region (normalized 0-1)
    public let cropRegion: CropRegion
    
    /// Confidence score (0-1)
    public let confidence: Double
    
    /// Detected subjects
    public let subjects: [DetectedSubject]
    
    /// Center of interest
    public let centerOfInterest: SIMD2<Double>
    
    public init(
        cropRegion: CropRegion,
        confidence: Double,
        subjects: [DetectedSubject],
        centerOfInterest: SIMD2<Double>
    ) {
        self.cropRegion = cropRegion
        self.confidence = confidence
        self.subjects = subjects
        self.centerOfInterest = centerOfInterest
    }
}

// MARK: - DetectedSubject

/// A detected subject in the frame
public struct DetectedSubject: Sendable {
    /// Subject type
    public let type: SubjectType
    
    /// Bounding box (normalized 0-1)
    public let boundingBox: CGRect
    
    /// Confidence score
    public let confidence: Double
    
    public enum SubjectType: String, Sendable {
        case face
        case person
        case saliency
        case object
    }
}

// MARK: - SmartReframerError

public enum SmartReframerError: Error, LocalizedError, Sendable {
    case visionRequestFailed(String)
    case noSubjectsDetected
    case invalidAspectRatio
    case processingFailed
    
    public var errorDescription: String? {
        switch self {
        case .visionRequestFailed(let msg):
            return "Vision request failed: \(msg)"
        case .noSubjectsDetected:
            return "No subjects detected in frame"
        case .invalidAspectRatio:
            return "Invalid target aspect ratio"
        case .processingFailed:
            return "Processing failed"
        }
    }
}

// MARK: - SmartReframer

/// AI-based video reframing using Vision framework
///
/// Analyzes video frames to detect faces and salient regions,
/// then computes optimal crop regions for different aspect ratios.
///
/// ## Example
/// ```swift
/// let reframer = SmartReframer(
///     sourceAspect: 16.0/9.0,
///     targetAspect: 9.0/16.0,
///     mode: .hybrid
/// )
/// 
/// let result = try await reframer.analyze(pixelBuffer)
/// // Use result.cropRegion for processing
/// ```
public actor SmartReframer {
    
    // MARK: - Properties
    
    /// Source aspect ratio
    public let sourceAspect: Double
    
    /// Target aspect ratio
    public let targetAspect: Double
    
    /// Tracking mode
    public let mode: SubjectTrackingMode
    
    /// Smoothing factor for crop region changes (0 = no smoothing, 1 = maximum)
    public let smoothingFactor: Double
    
    /// Minimum confidence to use detected subject
    public let minConfidence: Double
    
    /// Previous crop region (for smoothing)
    private var previousCrop: CropRegion?
    
    /// Face detection request (lazy)
    private var faceRequest: VNDetectFaceRectanglesRequest?
    
    /// Saliency request (lazy)
    private var saliencyRequest: VNGenerateAttentionBasedSaliencyImageRequest?
    
    /// Sequence handler for tracking
    private var sequenceHandler: VNSequenceRequestHandler
    
    // MARK: - Initialization
    
    public init(
        sourceAspect: Double,
        targetAspect: Double,
        mode: SubjectTrackingMode = .hybrid,
        smoothingFactor: Double = 0.7,
        minConfidence: Double = 0.5
    ) {
        self.sourceAspect = sourceAspect
        self.targetAspect = targetAspect
        self.mode = mode
        self.smoothingFactor = smoothingFactor.clamped(to: 0...1)
        self.minConfidence = minConfidence
        self.sequenceHandler = VNSequenceRequestHandler()
    }
    
    // MARK: - Analysis
    
    /// Analyze a frame and get reframe suggestion
    public func analyze(_ pixelBuffer: CVPixelBuffer) async throws -> ReframeResult {
        var subjects: [DetectedSubject] = []
        
        // Detect based on mode
        switch mode {
        case .face:
            subjects = try await detectFaces(in: pixelBuffer)
            
        case .saliency:
            subjects = try await detectSaliency(in: pixelBuffer)
            
        case .hybrid:
            let faces = try await detectFaces(in: pixelBuffer)
            let saliency = try await detectSaliency(in: pixelBuffer)
            
            // Prioritize faces, fall back to saliency
            subjects = faces.isEmpty ? saliency : faces
            
        case .objectTracking:
            // For now, use saliency
            subjects = try await detectSaliency(in: pixelBuffer)
        }
        
        // Calculate center of interest
        let centerOfInterest = calculateCenterOfInterest(from: subjects)
        
        // Calculate optimal crop region
        let cropRegion = calculateCropRegion(
            centerOfInterest: centerOfInterest,
            subjects: subjects
        )
        
        // Apply smoothing
        let smoothedCrop = applySmoothingIfNeeded(cropRegion)
        previousCrop = smoothedCrop
        
        // Calculate confidence
        let confidence = subjects.isEmpty ? 0.3 : subjects.map { $0.confidence }.max() ?? 0.5
        
        return ReframeResult(
            cropRegion: smoothedCrop,
            confidence: confidence,
            subjects: subjects,
            centerOfInterest: centerOfInterest
        )
    }
    
    /// Analyze a Metal texture
    public func analyze(_ texture: MTLTexture) async throws -> ReframeResult {
        guard let pixelBuffer = textureToPixelBuffer(texture) else {
            throw SmartReframerError.processingFailed
        }
        return try await analyze(pixelBuffer)
    }
    
    /// Reset tracking state
    public func reset() {
        previousCrop = nil
        sequenceHandler = VNSequenceRequestHandler()
    }
    
    // MARK: - Detection
    
    private func detectFaces(in pixelBuffer: CVPixelBuffer) async throws -> [DetectedSubject] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: SmartReframerError.visionRequestFailed(error.localizedDescription))
                    return
                }
                
                let subjects = (request.results as? [VNFaceObservation])?.map { observation in
                    DetectedSubject(
                        type: .face,
                        boundingBox: observation.boundingBox,
                        confidence: Double(observation.confidence)
                    )
                } ?? []
                
                continuation.resume(returning: subjects)
            }
            
            do {
                try sequenceHandler.perform([request], on: pixelBuffer)
            } catch {
                continuation.resume(throwing: SmartReframerError.visionRequestFailed(error.localizedDescription))
            }
        }
    }
    
    private func detectSaliency(in pixelBuffer: CVPixelBuffer) async throws -> [DetectedSubject] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNGenerateAttentionBasedSaliencyImageRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: SmartReframerError.visionRequestFailed(error.localizedDescription))
                    return
                }
                
                guard let result = request.results?.first as? VNSaliencyImageObservation else {
                    continuation.resume(returning: [])
                    return
                }
                
                // Get salient objects
                let objects = result.salientObjects ?? []
                
                let subjects = objects.map { object in
                    DetectedSubject(
                        type: .saliency,
                        boundingBox: object.boundingBox,
                        confidence: Double(object.confidence)
                    )
                }
                
                continuation.resume(returning: subjects)
            }
            
            do {
                try sequenceHandler.perform([request], on: pixelBuffer)
            } catch {
                continuation.resume(throwing: SmartReframerError.visionRequestFailed(error.localizedDescription))
            }
        }
    }
    
    // MARK: - Crop Calculation
    
    private func calculateCenterOfInterest(from subjects: [DetectedSubject]) -> SIMD2<Double> {
        guard !subjects.isEmpty else {
            // Default to center
            return SIMD2(0.5, 0.5)
        }
        
        // Weighted average based on confidence
        var weightedX = 0.0
        var weightedY = 0.0
        var totalWeight = 0.0
        
        for subject in subjects {
            let weight = subject.confidence
            let centerX = subject.boundingBox.midX
            let centerY = subject.boundingBox.midY
            
            weightedX += Double(centerX) * weight
            weightedY += Double(centerY) * weight
            totalWeight += weight
        }
        
        if totalWeight > 0 {
            return SIMD2(weightedX / totalWeight, weightedY / totalWeight)
        }
        
        return SIMD2(0.5, 0.5)
    }
    
    private func calculateCropRegion(
        centerOfInterest: SIMD2<Double>,
        subjects: [DetectedSubject]
    ) -> CropRegion {
        // Calculate crop size based on aspect ratio change
        let cropWidth: Double
        let cropHeight: Double
        
        if sourceAspect > targetAspect {
            // Going from landscape to portrait - crop width
            cropWidth = targetAspect / sourceAspect
            cropHeight = 1.0
        } else {
            // Going from portrait to landscape - crop height
            cropWidth = 1.0
            cropHeight = sourceAspect / targetAspect
        }
        
        // Position crop centered on interest point
        var cropX = centerOfInterest.x - cropWidth / 2
        var cropY = centerOfInterest.y - cropHeight / 2
        
        // Clamp to valid range
        cropX = cropX.clamped(to: 0...(1 - cropWidth))
        cropY = cropY.clamped(to: 0...(1 - cropHeight))
        
        // Try to include all high-confidence subjects
        let highConfidenceSubjects = subjects.filter { $0.confidence >= minConfidence }
        
        if !highConfidenceSubjects.isEmpty {
            // Compute bounding box of all subjects
            let allBounds = highConfidenceSubjects.reduce(CGRect.null) { result, subject in
                result.union(subject.boundingBox)
            }
            
            // Adjust crop to include subjects if possible
            if allBounds.width < cropWidth && allBounds.height < cropHeight {
                // All subjects fit in crop - center on them
                let subjectCenterX = Double(allBounds.midX)
                let subjectCenterY = Double(allBounds.midY)
                
                cropX = (subjectCenterX - cropWidth / 2).clamped(to: 0...(1 - cropWidth))
                cropY = (subjectCenterY - cropHeight / 2).clamped(to: 0...(1 - cropHeight))
            }
        }
        
        return CropRegion(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
    }
    
    private func applySmoothingIfNeeded(_ newCrop: CropRegion) -> CropRegion {
        guard smoothingFactor > 0, let previous = previousCrop else {
            return newCrop
        }
        
        // Lerp between previous and new
        let alpha = 1.0 - smoothingFactor
        
        return CropRegion(
            x: previous.x * smoothingFactor + newCrop.x * alpha,
            y: previous.y * smoothingFactor + newCrop.y * alpha,
            width: previous.width * smoothingFactor + newCrop.width * alpha,
            height: previous.height * smoothingFactor + newCrop.height * alpha
        )
    }
    
    // MARK: - Helpers
    
    private func textureToPixelBuffer(_ texture: MTLTexture) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: texture.width,
            kCVPixelBufferHeightKey: texture.height,
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            texture.width,
            texture.height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
        
        texture.getBytes(baseAddress, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        return buffer
    }
}

// MARK: - Convenience Extensions

extension SmartReframer {
    /// Create reframer for landscape to portrait conversion
    public static func landscapeToPortrait(
        smoothing: Double = 0.7
    ) -> SmartReframer {
        SmartReframer(
            sourceAspect: 16.0 / 9.0,
            targetAspect: 9.0 / 16.0,
            mode: .hybrid,
            smoothingFactor: smoothing
        )
    }
    
    /// Create reframer for TikTok/Reels from landscape source
    public static func forShortFormContent(
        sourceWidth: Int,
        sourceHeight: Int
    ) -> SmartReframer {
        SmartReframer(
            sourceAspect: Double(sourceWidth) / Double(sourceHeight),
            targetAspect: 9.0 / 16.0,
            mode: .hybrid,
            smoothingFactor: 0.8,
            minConfidence: 0.4
        )
    }
    
    /// Create reframer from preset
    public static func forPreset(
        _ preset: ExportPreset,
        sourceResolution: ExportResolution
    ) -> SmartReframer {
        SmartReframer(
            sourceAspect: sourceResolution.aspectRatio,
            targetAspect: preset.resolution.aspectRatio,
            mode: .hybrid
        )
    }
}
