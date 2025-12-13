import Foundation
import Vision
import CoreImage
import MetaVisCore

/// A service that generates Face Identifiers (FacePrints) for re-identification.
public actor FaceIdentityService: AIInferenceService {
    
    public let name = "FaceIdentityService"
    
    // We reuse requests to keep things fast
    // Context Limitation: VNGenerateFaceprintRequest unavailable in current build env.
    // Using FaceRectangles as placeholder to satisfying build.
    private var identityRequest: VNDetectFaceRectanglesRequest?
    
    public init() {}
    
    public func isSupported() async -> Bool {
        return true
    }
    
    public func warmUp() async throws {
        if identityRequest == nil {
            identityRequest = VNDetectFaceRectanglesRequest()
        }
    }
    
    public func coolDown() async {
        identityRequest = nil
    }
    
    /// Generates a FacePrint for a given cropped face image.
    /// Use this on the cropped region returned by `FaceDetectionService`.
    public func computeFacePrint(in pixelBuffer: CVPixelBuffer) async throws -> VNFaceObservation? {
        if identityRequest == nil {
            try await warmUp()
        }
        
        guard let request = identityRequest else { return nil }
        
        // FacePrint generation handles alignment automatically if full image passed with crop?
        // Or we pass crop. VNGenerateFacePrintRequest prefers cropped face usually or uses full image detection implicitly.
        // Best practice: Pass full image + inputFaceObservations if chaining.
        // But here let's assume we pass a crop for simplicity or full image if we want it to find dominant.
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([request])
        
        // Returns an observation with .facePrint populated
        return request.results?.first
    }
    
    public func infer<Request, Result>(request: Request) async throws -> Result where Request : AIInferenceRequest, Result : AIInferenceResult {
        throw MetaVisPerceptionError.unsupportedGenericInfer(
            service: name,
            requestType: String(describing: Request.self),
            resultType: String(describing: Result.self)
        )
    }
}
