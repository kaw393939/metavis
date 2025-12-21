import Foundation

/// Represents the results of computer vision analysis on a media asset.
/// This includes segmentation, object detection, and saliency.
public struct VisualAnalysis: Codable, Sendable, Equatable {
    /// Segmentation masks identifying specific regions (Person, Sky, etc.).
    public let segmentation: [SegmentationLayer]
    
    /// Objects detected in the scene.
    public let objects: [DetectedObject]
    
    /// Regions of high visual interest.
    public let saliency: [SaliencyRegion]
    
    /// Reference to the depth map asset (grayscale texture).
    public let depthMapAssetId: UUID?
    
    /// The version of the analysis engine used (for cache invalidation).
    public let engineVersion: String
    
    public init(
        segmentation: [SegmentationLayer] = [],
        objects: [DetectedObject] = [],
        saliency: [SaliencyRegion] = [],
        depthMapAssetId: UUID? = nil,
        engineVersion: String = "1.0"
    ) {
        self.segmentation = segmentation
        self.objects = objects
        self.saliency = saliency
        self.depthMapAssetId = depthMapAssetId
        self.engineVersion = engineVersion
    }
}

/// A segmented region of an image/video.
public struct SegmentationLayer: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    
    /// The semantic label of the region (e.g. "Person", "Sky", "Background").
    public let label: String
    
    /// Confidence score of the segmentation (0.0 - 1.0).
    public let confidence: Float
    
    /// The normalized bounding box of the region (0.0-1.0).
    public let bounds: Rect
    
    /// Reference to the mask data (stored separately, e.g. as a grayscale texture asset).
    public let maskAssetId: UUID?
    
    public init(
        id: UUID = UUID(),
        label: String,
        confidence: Float,
        bounds: Rect,
        maskAssetId: UUID? = nil
    ) {
        self.id = id
        self.label = label
        self.confidence = confidence
        self.bounds = bounds
        self.maskAssetId = maskAssetId
    }
}

/// An object detected in the scene.
public struct DetectedObject: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    
    /// The class of the object (e.g. "Car", "Dog", "Chair").
    public let label: String
    
    /// Confidence score (0.0 - 1.0).
    public let confidence: Float
    
    /// The normalized bounding box of the object.
    public let bounds: Rect
    
    /// Optional tracking ID if this object is tracked across frames.
    public let trackingId: Int?
    
    public init(
        id: UUID = UUID(),
        label: String,
        confidence: Float,
        bounds: Rect,
        trackingId: Int? = nil
    ) {
        self.id = id
        self.label = label
        self.confidence = confidence
        self.bounds = bounds
        self.trackingId = trackingId
    }
}

/// A region of visual interest.
public struct SaliencyRegion: Codable, Sendable, Equatable {
    /// The normalized bounding box.
    public let bounds: Rect
    
    /// The "heat" or importance of this region (0.0 - 1.0).
    public let value: Float
    
    public init(bounds: Rect, value: Float) {
        self.bounds = bounds
        self.value = value
    }
}

/// A normalized rectangle (0.0 - 1.0).
public struct Rect: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    
    public static let zero = Rect(x: 0, y: 0, width: 0, height: 0)
}
