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
        lastObservations = []
        trackRequests = []
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

    // Reused tracking requests (one per face).
    private var trackRequests: [VNTrackObjectRequest] = []

    private func ensureTrackRequestsMatchObservations() {
        // Rebuild only when the number of tracks changes; otherwise reuse request objects.
        if trackRequests.count != lastObservations.count {
            trackRequests = lastObservations.map { observation in
                let request = VNTrackObjectRequest(detectedObjectObservation: observation)
                request.trackingLevel = .fast
                return request
            }
            return
        }

        // Update inputs in-place for the next tracking step.
        for (index, observation) in lastObservations.enumerated() {
            trackRequests[index].inputObservation = observation
        }
    }
    
    /// Tracks faces across frames.
    /// Returns a map of Tracking UUID -> Normalized Rect.
    /// This allows effects to stick to a specific "Person 1" or "Person 2".
    public func trackFaces(in pixelBuffer: CVPixelBuffer) async throws -> [UUID: CGRect] {
        // 1. If no previous tracks, detect first
        if lastObservations.isEmpty {
            try await warmUp()
            guard let request = faceRequest else { return [:] }
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try handler.perform([request])
            
            guard let faces = request.results else { return [:] }
            
            self.lastObservations = faces
            ensureTrackRequestsMatchObservations()

            var results: [UUID: CGRect] = [:]
            results.reserveCapacity(faces.count)
            for face in faces {
                results[face.uuid] = normalizeObservation(face)
            }
            return results
        }
        
        // 2. Continuous Tracking
        ensureTrackRequestsMatchObservations()

        if trackRequests.isEmpty {
            return [:]
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform(trackRequests)
        } catch {
            // Tracking lost? Reset.
            lastObservations = []
            trackRequests = []
            return [:]
        }
        
        // Collect all results
        var newObservations: [VNDetectedObjectObservation] = []
        var results: [UUID: CGRect] = [:]

        newObservations.reserveCapacity(trackRequests.count)
        results.reserveCapacity(trackRequests.count)

        for request in trackRequests {
            if let output = request.results?.first as? VNDetectedObjectObservation {
                newObservations.append(output)
                results[output.uuid] = normalizeObservation(output)
            }
        }
        
        self.lastObservations = newObservations
        
        // If system lost all tracks
        if newObservations.isEmpty {
            lastObservations = []
            trackRequests = []
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
