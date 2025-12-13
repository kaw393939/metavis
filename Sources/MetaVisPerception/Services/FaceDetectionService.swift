import Foundation
import Vision
import CoreImage
import MetaVisCore

/// A service that uses the Vision framework to detect faces in an image.
public actor FaceDetectionService: AIInferenceService {
    
    public let name = "FaceDetectionService"
    
    private let context = NeuralEngineContext.shared
    
    // We reuse requests to keep things fast
    private var faceRequest: VNDetectFaceRectanglesRequest?
    
    public init() {}
    
    public func isSupported() async -> Bool {
        // Vision face detection is supported on all target platforms
        return true
    }
    
    public func warmUp() async throws {
        // Create the request
        if faceRequest == nil {
            faceRequest = VNDetectFaceRectanglesRequest()
            // We can try to tune it, but standard settings are usually best for generic video
        }
    }
    
    public func coolDown() async {
        faceRequest = nil
    }
    
    /// Requests face detection on a CVPixelBuffer.
    /// Returns normalized CGRects (0-1) where (0,0) is top-left (Vision default is bottom-left, we map to MetaVis standard).
    /// Requests face detection on a CVPixelBuffer.
    /// Returns normalized CGRects (0-1) where (0,0) is top-left (Vision default is bottom-left, we map to MetaVis standard).
    public func detectFaces(in pixelBuffer: CVPixelBuffer) async throws -> [CGRect] {
        if faceRequest == nil {
            try await warmUp()
        }
        
        guard let request = faceRequest else { return [] }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([request])
        
        guard let observations = request.results else { return [] }
        
        return observations.map { normalizeObservation($0) }
    }
    
    // MARK: - Tracking (Diarization)
    
    // Last frame's observations for continuity
    private var lastObservations: [VNDetectedObjectObservation] = []
    
    /// Tracks faces across frames.
    /// Returns a map of Tracking UUID -> Normalized Rect.
    /// This allows effects to stick to a specific "Person 1" or "Person 2".
    public func trackFaces(in pixelBuffer: CVPixelBuffer) async throws -> [UUID: CGRect] {
        // 1. If no previous tracks, detect first
        if lastObservations.isEmpty {
            _ = try await detectFaces(in: pixelBuffer)
            // Create dummy observations for tracking init if needed, or rely on next cycle?
            // VNTrackObjectRequest needs an initial observation to start tracking.
            // Simplified: If empty, detect and return UUIDs next frame? 
            // Better: Run detection, then convert to Tracking Request for next frame.
            
            // For now, just return detections with random UUIDs? No, that defeats tracking.
            // We need a proper tracking loop.
            // Vision Tracking requires state management.
            
            // Logic:
            // 1. Detect Faces (VNDetectFaceRectanglesRequest)
            // 2. Convert to VNDetectedObjectObservation
            // 3. Store for next frame.
            // 4. Next Frame: VNTrackObjectRequest(input: lastObservations)
            
            // Re-detect faces
            try await warmUp()
            guard let request = faceRequest else { return [:] }
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try handler.perform([request])
            
            guard let faces = request.results else { return [:] }
            
            var results: [UUID: CGRect] = [:]
            self.lastObservations = faces // Store faces to track next frame? No, tracking starts from these.
            
            for face in faces {
                results[face.uuid] = normalizeObservation(face)
            }
            return results
        }
        
        // 2. Continuous Tracking
        // VNTrackObjectRequest(detectedObjectObservations:) is the correct init signature, 
        // but maybe compiler issues with empty array?
        // Let's try explicit label.
        // 2. Continuous Tracking
        // Tracking: Create request with detected detectedObjectObservations from previous frame?
        // VNTrackObjectRequest(detectedObjectObservations: [...])
        // If that fails, let's use the standard init and set property if configurable.
        // Actually, init(detectedObjectObservations:) IS the designated initializer.
        // If compiler says "takes no arguments", maybe the array is typed wrong?
        // Trying to cast specifically.
        
        // 2. Continuous Tracking
        // VNTrackObjectRequest tracks ONE object. We need one request per face.
        var requests: [VNTrackObjectRequest] = []
        
        for observation in lastObservations {
            let req = VNTrackObjectRequest(detectedObjectObservation: observation)
            req.trackingLevel = .fast
            requests.append(req)
        }
        
        if requests.isEmpty {
            return [:]
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform(requests)
        } catch {
            // Tracking lost? Reset.
            lastObservations = []
            return try await trackFaces(in: pixelBuffer) // Retry with detection
        }
        
        // Collect all results
        var newObservations: [VNDetectedObjectObservation] = []
        var results: [UUID: CGRect] = [:]
        
        for req in requests {
            if let output = req.results?.first as? VNDetectedObjectObservation {
                newObservations.append(output)
                results[output.uuid] = normalizeObservation(output)
            }
        }
        
        self.lastObservations = newObservations
        
        // If system lost all tracks
        if newObservations.isEmpty {
            lastObservations = []
        }
        
        return results
    }

    private func normalizeObservation(_ observation: VNDetectedObjectObservation) -> CGRect {
        // Vision coordinates: (0,0) is bottom-left.
        // MetaVis/Metal coordinates: (0,0) is top-left.
        // We need to flip Y.
        
        let oldRect = observation.boundingBox
        let newY = 1.0 - (oldRect.origin.y + oldRect.height)
        
        return CGRect(x: oldRect.origin.x, y: newY, width: oldRect.width, height: oldRect.height)
    }
    
    // Protocol Conformance (Stubbed generic interface)
    // In a real implementation, we would define specific Request/Result structs for the generic method,
    // but explicit methods are better for type safety in this specific domain.
    public func infer<Request, Result>(request: Request) async throws -> Result where Request : AIInferenceRequest, Result : AIInferenceResult {
        throw MetaVisPerceptionError.unsupportedGenericInfer(
            service: name,
            requestType: String(describing: Request.self),
            resultType: String(describing: Result.self)
        )
    }
}
