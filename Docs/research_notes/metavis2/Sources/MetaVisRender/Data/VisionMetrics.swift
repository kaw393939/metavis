import Foundation
import CoreGraphics

public struct VisionFrameMetrics: Sendable {
    public let saliencyMap: [Float] // Downsampled heatmap
    public let faces: [VisionFaceObservation]
    public let textRegions: [VisionTextObservation]
    public let depthMap: [Float]?
    
    public init(saliencyMap: [Float] = [], faces: [VisionFaceObservation] = [], textRegions: [VisionTextObservation] = [], depthMap: [Float]? = nil) {
        self.saliencyMap = saliencyMap
        self.faces = faces
        self.textRegions = textRegions
        self.depthMap = depthMap
    }
}

/// Legacy face observation type (use FaceObservation from VisionProvider for new code)
public struct VisionFaceObservation: Sendable {
    public let bounds: CGRect // Normalized 0-1
    public let yaw: Float?
    public let pitch: Float?
    
    public init(bounds: CGRect, yaw: Float? = nil, pitch: Float? = nil) {
        self.bounds = bounds
        self.yaw = yaw
        self.pitch = pitch
    }
}

/// Legacy text observation type (use TextObservation from VisionProvider for new code)
public struct VisionTextObservation: Sendable {
    public let text: String
    public let bounds: CGRect // Normalized 0-1
    public let confidence: Float
    
    public init(text: String, bounds: CGRect, confidence: Float) {
        self.text = text
        self.bounds = bounds
        self.confidence = confidence
    }
}
