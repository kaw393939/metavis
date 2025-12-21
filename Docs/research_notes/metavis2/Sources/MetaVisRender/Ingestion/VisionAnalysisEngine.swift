import Foundation
import CoreVideo
import Metal
@preconcurrency import Vision
import CoreImage

/// Vision analysis engine for frame-by-frame video analysis
/// Integrates with VisionProvider for face detection, saliency, and text recognition
public class VisionAnalysisEngine {
    
    private let device: MTLDevice?
    private let visionProvider: VisionProvider?
    private let ciContext: CIContext
    
    public init(device: MTLDevice? = nil) {
        self.device = device ?? MTLCreateSystemDefaultDevice()
        if let device = self.device {
            self.visionProvider = VisionProvider(device: device)
            self.ciContext = CIContext(mtlDevice: device)
        } else {
            self.visionProvider = nil
            self.ciContext = CIContext()
        }
    }
    
    /// Analyze a pixel buffer for faces, saliency, and text
    public func analyze(pixelBuffer: CVPixelBuffer) async throws -> VisionFrameMetrics {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Run face detection
        let faces = try await detectFaces(in: pixelBuffer)
        
        // Run saliency detection
        let saliencyMap = try await detectSaliency(in: pixelBuffer, width: width, height: height)
        
        // Run text detection
        let textRegions = try await detectText(in: pixelBuffer)
        
        return VisionFrameMetrics(
            saliencyMap: saliencyMap,
            faces: faces,
            textRegions: textRegions,
            depthMap: nil
        )
    }
    
    // MARK: - Face Detection
    
    private func detectFaces(in pixelBuffer: CVPixelBuffer) async throws -> [VisionFaceObservation] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                    
                    let faces = (request.results ?? []).map { observation in
                        VisionFaceObservation(
                            bounds: observation.boundingBox,
                            yaw: observation.yaw?.floatValue,
                            pitch: observation.pitch?.floatValue
                        )
                    }
                    
                    continuation.resume(returning: faces)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Saliency Detection
    
    private func detectSaliency(in pixelBuffer: CVPixelBuffer, width: Int, height: Int) async throws -> [Float] {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                    
                    guard let observation = request.results?.first as? VNSaliencyImageObservation else {
                        continuation.resume(returning: [])
                        return
                    }
                    
                    let saliencyPixelBuffer = observation.pixelBuffer
                    
                    // Convert saliency pixel buffer to float array
                    let saliencyMap = self.extractSaliencyValues(from: saliencyPixelBuffer)
                    continuation.resume(returning: saliencyMap)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func extractSaliencyValues(from pixelBuffer: CVPixelBuffer) -> [Float] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return []
        }
        
        // Downsample to 16x16 grid for efficiency
        let gridSize = 16
        var values: [Float] = []
        values.reserveCapacity(gridSize * gridSize)
        
        let stepX = width / gridSize
        let stepY = height / gridSize
        
        let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        for gy in 0..<gridSize {
            for gx in 0..<gridSize {
                let x = gx * stepX + stepX / 2
                let y = gy * stepY + stepY / 2
                let offset = y * bytesPerRow + x
                
                if offset < bytesPerRow * height {
                    let value = Float(pointer[offset]) / 255.0
                    values.append(value)
                }
            }
        }
        
        return values
    }
    
    // MARK: - Text Detection
    
    private func detectText(in pixelBuffer: CVPixelBuffer) async throws -> [VisionTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                    
                    let texts = (request.results ?? []).compactMap { observation -> VisionTextObservation? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        return VisionTextObservation(
                            text: candidate.string,
                            bounds: observation.boundingBox,
                            confidence: candidate.confidence
                        )
                    }
                    
                    continuation.resume(returning: texts)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

