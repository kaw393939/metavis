import Foundation
import Metal
import QuartzCore

// MARK: - Unified Scene Analysis Result

/// Complete scene analysis combining all vision and metric results
public struct UnifiedSceneAnalysis: Sendable {
    // Vision results
    public let saliency: SaliencyMap?
    public let segmentation: SegmentationMask?
    public let faces: [FaceObservation]
    public let textRegions: [TextObservation]
    public let sceneInfo: SceneAnalysis?
    public let horizon: HorizonObservation?
    public let opticalFlow: OpticalFlow?
    
    // Depth results
    public let depthMap: DepthMap?
    
    // Computed metrics
    public let sharpness: Float?
    public let exposure: ExposureStats?
    public let composition: CompositionScore?
    
    // Safe placement zones
    public let safeZones: [CGRect]
    
    // Timing
    public let analysisTime: CFTimeInterval
    public let timestamp: CFTimeInterval
    
    public init(
        saliency: SaliencyMap? = nil,
        segmentation: SegmentationMask? = nil,
        faces: [FaceObservation] = [],
        textRegions: [TextObservation] = [],
        sceneInfo: SceneAnalysis? = nil,
        horizon: HorizonObservation? = nil,
        opticalFlow: OpticalFlow? = nil,
        depthMap: DepthMap? = nil,
        sharpness: Float? = nil,
        exposure: ExposureStats? = nil,
        composition: CompositionScore? = nil,
        safeZones: [CGRect] = [],
        analysisTime: CFTimeInterval = 0,
        timestamp: CFTimeInterval = CACurrentMediaTime()
    ) {
        self.saliency = saliency
        self.segmentation = segmentation
        self.faces = faces
        self.textRegions = textRegions
        self.sceneInfo = sceneInfo
        self.horizon = horizon
        self.opticalFlow = opticalFlow
        self.depthMap = depthMap
        self.sharpness = sharpness
        self.exposure = exposure
        self.composition = composition
        self.safeZones = safeZones
        self.analysisTime = analysisTime
        self.timestamp = timestamp
    }
    
    /// Returns true if the scene has a detected person
    public var hasPerson: Bool {
        return segmentation != nil || !faces.isEmpty
    }
    
    /// Returns the primary subject bounds (face or segmentation)
    public var primarySubjectBounds: CGRect? {
        if let face = faces.first {
            return face.bounds
        }
        if let seg = segmentation, seg.bounds != .zero {
            return seg.bounds
        }
        return nil
    }
    
    /// Returns the best safe zone for text placement
    public var bestTextZone: CGRect? {
        // Prefer lower third zones
        let lowerThirdZones = safeZones.filter { $0.minY > 0.6 }
        if let zone = lowerThirdZones.first {
            return zone
        }
        return safeZones.first
    }
}

// MARK: - Analysis Configuration

/// Configuration for scene analysis
public struct SceneAnalysisConfig: Sendable {
    public var enableSaliency: Bool = true
    public var enableSegmentation: Bool = true
    public var enableFaceDetection: Bool = true
    public var enableFaceLandmarks: Bool = false
    public var enableTextDetection: Bool = false
    public var enableTextRecognition: Bool = false
    public var enableSceneClassification: Bool = true
    public var enableHorizonDetection: Bool = true
    public var enableDepthEstimation: Bool = true
    public var enableSharpnessMetric: Bool = false
    public var enableExposureMetric: Bool = false
    public var enableCompositionMetric: Bool = true
    public var findSafeZones: Bool = true
    
    public var saliencyMode: VisionProvider.SaliencyMode = .attention
    public var segmentationQuality: VisionProvider.SegmentationQuality = .balanced
    
    public var safeZoneMinWidth: Float = 0.15
    public var safeZoneMinHeight: Float = 0.05
    public var saliencyThreshold: Float = 0.3
    
    public init() {}
    
    /// Preset for real-time analysis (30fps)
    public static var realtime: SceneAnalysisConfig {
        var config = SceneAnalysisConfig()
        config.segmentationQuality = .fast
        config.enableFaceLandmarks = false
        config.enableTextDetection = false
        config.enableSharpnessMetric = false
        config.enableExposureMetric = false
        return config
    }
    
    /// Preset for balanced quality/speed
    public static var balanced: SceneAnalysisConfig {
        var config = SceneAnalysisConfig()
        config.segmentationQuality = .balanced
        return config
    }
    
    /// Preset for maximum quality (offline)
    public static var cinema: SceneAnalysisConfig {
        var config = SceneAnalysisConfig()
        config.segmentationQuality = .accurate
        config.enableFaceLandmarks = true
        config.enableTextRecognition = true
        config.enableSharpnessMetric = true
        config.enableExposureMetric = true
        return config
    }
}

// MARK: - SceneAnalyzer

/// Unified scene analysis coordinator that combines all vision capabilities
public actor SceneAnalyzer {
    
    private let device: MTLDevice
    private let visionProvider: VisionProvider
    private let depthEstimator: MLDepthEstimator?
    
    // Caching
    private var lastAnalysis: UnifiedSceneAnalysis?
    private var lastFrameHash: Int?
    
    public init(device: MTLDevice? = nil) {
        let dev = device ?? MTLCreateSystemDefaultDevice()!
        self.device = dev
        self.visionProvider = VisionProvider(device: dev)
        self.depthEstimator = try? MLDepthEstimator(device: dev)
    }
    
    /// Perform full scene analysis with configurable features
    public func analyze(
        frame: MTLTexture,
        previousFrame: MTLTexture? = nil,
        config: SceneAnalysisConfig = .balanced
    ) async throws -> UnifiedSceneAnalysis {
        let startTime = CACurrentMediaTime()
        
        // Run analyses in parallel based on config
        async let saliencyTask = config.enableSaliency 
            ? try? visionProvider.detectSaliency(in: frame, mode: config.saliencyMode)
            : nil
        
        async let segmentationTask: SegmentationMask? = config.enableSegmentation
            ? try? await runSegmentation(frame: frame, quality: config.segmentationQuality)
            : nil
        
        async let facesTask = config.enableFaceDetection
            ? (try? visionProvider.detectFaces(in: frame, landmarks: config.enableFaceLandmarks)) ?? []
            : []
        
        async let textTask = config.enableTextDetection
            ? (try? visionProvider.detectText(in: frame, recognizeText: config.enableTextRecognition)) ?? []
            : []
        
        async let sceneTask = config.enableSceneClassification
            ? try? visionProvider.analyzeScene(frame)
            : nil
        
        async let horizonTask = config.enableHorizonDetection
            ? try? visionProvider.detectHorizon(in: frame)
            : nil
        
        async let depthTask: DepthMap? = config.enableDepthEstimation
            ? try? await depthEstimator?.estimateDepth(from: frame)
            : nil
        
        async let flowTask: OpticalFlow? = previousFrame != nil
            ? try? await runOpticalFlow(from: previousFrame!, to: frame)
            : nil
        
        // Await all results
        let (saliency, segmentation, faces, textRegions, sceneInfo, horizon, depthMap, opticalFlow) = await (
            saliencyTask,
            segmentationTask,
            facesTask,
            textTask,
            sceneTask,
            horizonTask,
            depthTask,
            flowTask
        )
        
        // Calculate metrics
        var sharpness: Float? = nil
        var exposure: ExposureStats? = nil
        
        if config.enableSharpnessMetric {
            sharpness = MetricCalculator.calculateSharpness(from: frame, device: device)
        }
        
        if config.enableExposureMetric {
            exposure = MetricCalculator.calculateExposureStats(from: frame)
        }
        
        // Calculate composition score
        var composition: CompositionScore? = nil
        if config.enableCompositionMetric {
            let saliencyRects = saliency?.regions.map { $0.bounds } ?? []
            let faceRects = faces.map { $0.bounds }
            composition = MetricCalculator.calculateCompositionScore(
                saliencyRegions: saliencyRects,
                faceRegions: faceRects
            )
        }
        
        // Find safe zones for text
        var safeZones: [CGRect] = []
        if config.findSafeZones, let saliency = saliency {
            safeZones = findSafeZones(
                saliency: saliency,
                segmentation: segmentation,
                faces: faces,
                config: config
            )
        }
        
        let analysisTime = CACurrentMediaTime() - startTime
        
        let analysis = UnifiedSceneAnalysis(
            saliency: saliency,
            segmentation: segmentation,
            faces: faces,
            textRegions: textRegions,
            sceneInfo: sceneInfo,
            horizon: horizon,
            opticalFlow: opticalFlow,
            depthMap: depthMap,
            sharpness: sharpness,
            exposure: exposure,
            composition: composition,
            safeZones: safeZones,
            analysisTime: analysisTime
        )
        
        lastAnalysis = analysis
        
        return analysis
    }
    
    /// Quick analysis for real-time use (may return cached results)
    public func analyzeQuick(frame: MTLTexture) async throws -> UnifiedSceneAnalysis {
        // Simple hash based on texture properties (not content)
        let frameHash = frame.width ^ frame.height ^ Int(frame.pixelFormat.rawValue)
        
        if let cached = lastAnalysis, lastFrameHash == frameHash,
           CACurrentMediaTime() - cached.timestamp < 0.1 {
            return cached
        }
        
        lastFrameHash = frameHash
        return try await analyze(frame: frame, config: .realtime)
    }
    
    /// Clear cached analysis
    public func clearCache() {
        lastAnalysis = nil
        lastFrameHash = nil
    }
    
    // MARK: - Private Helpers
    
    @available(macOS 12.0, iOS 15.0, *)
    private func runSegmentation(frame: MTLTexture, quality: VisionProvider.SegmentationQuality) async throws -> SegmentationMask {
        return try await visionProvider.segmentPeople(in: frame, quality: quality)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    private func runOpticalFlow(from frame1: MTLTexture, to frame2: MTLTexture) async throws -> OpticalFlow {
        return try await visionProvider.computeOpticalFlow(from: frame1, to: frame2)
    }
    
    private func findSafeZones(
        saliency: SaliencyMap,
        segmentation: SegmentationMask?,
        faces: [FaceObservation],
        config: SceneAnalysisConfig
    ) -> [CGRect] {
        // Start with screen space
        var zones: [CGRect] = [
            // Lower third regions
            CGRect(x: 0.05, y: 0.70, width: 0.4, height: 0.25),
            CGRect(x: 0.55, y: 0.70, width: 0.4, height: 0.25),
            // Upper regions
            CGRect(x: 0.05, y: 0.05, width: 0.4, height: 0.15),
            CGRect(x: 0.55, y: 0.05, width: 0.4, height: 0.15),
            // Side regions
            CGRect(x: 0.02, y: 0.3, width: 0.2, height: 0.3),
            CGRect(x: 0.78, y: 0.3, width: 0.2, height: 0.3)
        ]
        
        // Filter out zones that overlap with subjects
        let subjectRegions: [CGRect] = {
            var regions = saliency.regions.map { $0.bounds }
            regions += faces.map { $0.bounds }
            if let seg = segmentation, seg.bounds != .zero {
                regions.append(seg.bounds)
            }
            return regions
        }()
        
        zones = zones.filter { zone in
            for subject in subjectRegions {
                if zone.intersects(subject) {
                    let intersection = zone.intersection(subject)
                    let overlapRatio = (intersection.width * intersection.height) / (zone.width * zone.height)
                    if overlapRatio > 0.3 {
                        return false
                    }
                }
            }
            return true
        }
        
        return zones
    }
}
