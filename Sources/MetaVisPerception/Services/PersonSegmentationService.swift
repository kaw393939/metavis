import Foundation
import Vision
import CoreImage
import MetaVisCore

/// A service that generates a segmentation mask for all people in the scene.
public actor PersonSegmentationService: AIInferenceService {
    
    public let name = "PersonSegmentationService"
    
    private var segmentationRequest: VNGeneratePersonSegmentationRequest?
    
    public init() {}
    
    public func isSupported() async -> Bool {
        return true
    }
    
    public func warmUp() async throws {
        if segmentationRequest == nil {
            segmentationRequest = VNGeneratePersonSegmentationRequest()
            segmentationRequest?.qualityLevel = .balanced // .accurate is slower, .fast is chunky
            segmentationRequest?.outputPixelFormat = kCVPixelFormatType_OneComponent8
        }
    }
    
    public func coolDown() async {
        segmentationRequest = nil
    }
    
    /// Generates a segmentation mask (CVPixelBuffer, OneComponent8).
    /// White = Person, Black = Background.
    public func generateMask(in pixelBuffer: CVPixelBuffer) async throws -> CVPixelBuffer? {
        if segmentationRequest == nil {
            try await warmUp()
        }
        
        guard let request = segmentationRequest else { return nil }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([request])
        
        return request.results?.first?.pixelBuffer
    }
    
    public func infer<Request, Result>(request: Request) async throws -> Result where Request : AIInferenceRequest, Result : AIInferenceResult {
        throw MetaVisPerceptionError.unsupportedGenericInfer(
            service: name,
            requestType: String(describing: Request.self),
            resultType: String(describing: Result.self)
        )
    }
}
