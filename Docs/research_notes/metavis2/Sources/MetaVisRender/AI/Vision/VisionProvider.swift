@preconcurrency import Metal
@preconcurrency import Vision
import CoreImage
import CoreVideo
import QuartzCore

// MARK: - Data Types

/// A region of visual saliency
public struct SaliencyRegion: Sendable {
    public let bounds: CGRect  // Normalized coordinates (0-1)
    public let confidence: Float
    
    public init(bounds: CGRect, confidence: Float) {
        self.bounds = bounds
        self.confidence = confidence
    }
}

/// A saliency map with detected regions
public struct SaliencyMap: Sendable {
    public let texture: MTLTexture?
    public let regions: [SaliencyRegion]
    public let mode: VisionProvider.SaliencyMode
    
    public init(texture: MTLTexture?, regions: [SaliencyRegion], mode: VisionProvider.SaliencyMode) {
        self.texture = texture
        self.regions = regions
        self.mode = mode
    }
}

/// Labels for segmentation masks
public enum SegmentationLabel: String, Sendable {
    case person
    case background
    case unknown
}

/// A segmentation mask with labeled regions
public struct SegmentationMask: Sendable {
    public let texture: MTLTexture
    public let labels: [SegmentationLabel]
    public let quality: VisionProvider.SegmentationQuality
    public let bounds: CGRect  // Bounding box of segmented region (normalized)
    
    public init(texture: MTLTexture, labels: [SegmentationLabel], quality: VisionProvider.SegmentationQuality, bounds: CGRect) {
        self.texture = texture
        self.labels = labels
        self.quality = quality
        self.bounds = bounds
    }
}

/// Optical flow between two frames
public struct OpticalFlow: Sendable {
    public let texture: MTLTexture?  // RG32Float: R=horizontal, G=vertical motion
    public let averageMagnitude: Float
    public let dominantDirection: SIMD2<Float>
    public let timestamp: CFTimeInterval
    
    public init(texture: MTLTexture?, averageMagnitude: Float, dominantDirection: SIMD2<Float>, timestamp: CFTimeInterval = CACurrentMediaTime()) {
        self.texture = texture
        self.averageMagnitude = averageMagnitude
        self.dominantDirection = dominantDirection
        self.timestamp = timestamp
    }
}

/// Scene type classification
public enum SceneType: String, Sendable {
    case indoor
    case outdoor
    case portrait
    case landscape
    case urban
    case nature
    case unknown
}

/// Scene analysis results
public struct SceneAnalysis: Sendable {
    public let sceneType: SceneType
    public let tags: [String]
    public let horizonAngle: Float?  // In radians, nil if not detected
    public let confidence: Float
    
    public init(sceneType: SceneType, tags: [String], horizonAngle: Float?, confidence: Float) {
        self.sceneType = sceneType
        self.tags = tags
        self.horizonAngle = horizonAngle
        self.confidence = confidence
    }
}

/// Face observation with landmarks and pose
public struct FaceObservation: Sendable {
    public let bounds: CGRect  // Normalized bounding box
    public let confidence: Float
    public let roll: Float?  // Head tilt
    public let yaw: Float?   // Head turn left/right
    public let pitch: Float? // Head tilt up/down
    public let landmarks: FaceLandmarks?
    
    public init(bounds: CGRect, confidence: Float, roll: Float? = nil, yaw: Float? = nil, pitch: Float? = nil, landmarks: FaceLandmarks? = nil) {
        self.bounds = bounds
        self.confidence = confidence
        self.roll = roll
        self.yaw = yaw
        self.pitch = pitch
        self.landmarks = landmarks
    }
}

/// Face landmarks for detailed face analysis
public struct FaceLandmarks: Sendable {
    public let leftEye: CGPoint?
    public let rightEye: CGPoint?
    public let nose: CGPoint?
    public let mouth: CGPoint?
    public let leftEyebrow: [CGPoint]?
    public let rightEyebrow: [CGPoint]?
    public let outerLips: [CGPoint]?
    public let faceContour: [CGPoint]?
    
    public init(leftEye: CGPoint? = nil, rightEye: CGPoint? = nil, nose: CGPoint? = nil, mouth: CGPoint? = nil, leftEyebrow: [CGPoint]? = nil, rightEyebrow: [CGPoint]? = nil, outerLips: [CGPoint]? = nil, faceContour: [CGPoint]? = nil) {
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.nose = nose
        self.mouth = mouth
        self.leftEyebrow = leftEyebrow
        self.rightEyebrow = rightEyebrow
        self.outerLips = outerLips
        self.faceContour = faceContour
    }
}

/// Detected text region with recognized content
public struct TextObservation: Sendable {
    public let bounds: CGRect  // Normalized bounding box
    public let text: String?   // Recognized text (if OCR enabled)
    public let confidence: Float
    
    public init(bounds: CGRect, text: String? = nil, confidence: Float) {
        self.bounds = bounds
        self.text = text
        self.confidence = confidence
    }
}

/// Horizon detection result
public struct HorizonObservation: Sendable {
    public let angle: Float  // In radians
    public let transform: CGAffineTransform  // Transform to level the image
    
    public init(angle: Float, transform: CGAffineTransform) {
        self.angle = angle
        self.transform = transform
    }
}

// MARK: - Errors

public enum VisionProviderError: Error, LocalizedError {
    case noSaliencyResults
    case noSegmentationResults
    case noFlowResults
    case noClassificationResults
    case noFaceResults
    case noTextResults
    case noHorizonResults
    case textureConversionFailed
    case pixelBufferCreationFailed
    
    public var errorDescription: String? {
        switch self {
        case .noSaliencyResults: return "Saliency detection produced no results"
        case .noSegmentationResults: return "Person segmentation produced no results"
        case .noFlowResults: return "Optical flow computation produced no results"
        case .noClassificationResults: return "Scene classification produced no results"
        case .noFaceResults: return "Face detection produced no results"
        case .noTextResults: return "Text detection produced no results"
        case .noHorizonResults: return "Horizon detection produced no results"
        case .textureConversionFailed: return "Failed to convert texture"
        case .pixelBufferCreationFailed: return "Failed to create pixel buffer"
        }
    }
}

// MARK: - VisionProvider

/// Unified Vision framework integration for scene understanding
public final class VisionProvider: @unchecked Sendable {
    
    public enum SaliencyMode: Sendable {
        case attention  // Where humans naturally look
        case objectness // Distinct objects in the scene
    }
    
    public enum SegmentationQuality: Sendable {
        case fast       // Real-time, lower quality
        case balanced   // Good balance
        case accurate   // Best quality, slower
        
        @available(macOS 12.0, iOS 15.0, *)
        var vnQualityLevel: VNGeneratePersonSegmentationRequest.QualityLevel {
            switch self {
            case .fast: return .fast
            case .balanced: return .balanced
            case .accurate: return .accurate
            }
        }
    }
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    
    public init(device: MTLDevice? = nil) {
        self.device = device ?? MTLCreateSystemDefaultDevice()!
        self.commandQueue = self.device.makeCommandQueue()!
        self.ciContext = CIContext(mtlDevice: self.device)
    }
    
    // MARK: - Saliency Detection
    
    public func detectSaliency(
        in texture: MTLTexture,
        mode: SaliencyMode = .attention
    ) async throws -> SaliencyMap {
        let pixelBuffer = try await textureToPixelBuffer(texture)
        
        let request: VNImageBasedRequest
        if mode == .attention {
            request = VNGenerateAttentionBasedSaliencyImageRequest()
        } else {
            request = VNGenerateObjectnessBasedSaliencyImageRequest()
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                do {
                    try handler.perform([request])
                    
                    guard let observation = request.results?.first as? VNSaliencyImageObservation else {
                        continuation.resume(throwing: VisionProviderError.noSaliencyResults)
                        return
                    }
                    
                    // Extract salient regions
                    var regions: [SaliencyRegion] = []
                    if let salientObjects = observation.salientObjects {
                        for object in salientObjects {
                            regions.append(SaliencyRegion(
                                bounds: object.boundingBox,
                                confidence: object.confidence
                            ))
                        }
                    }
                    
                    let saliencyMap = SaliencyMap(
                        texture: nil,  // Could convert pixelBuffer to texture if needed
                        regions: regions,
                        mode: mode
                    )
                    
                    continuation.resume(returning: saliencyMap)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Person Segmentation
    
    @available(macOS 12.0, iOS 15.0, *)
    public func segmentPeople(
        in texture: MTLTexture,
        quality: SegmentationQuality = .balanced
    ) async throws -> SegmentationMask {
        let pixelBuffer = try await textureToPixelBuffer(texture)
        
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = quality.vnQualityLevel
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async { [self] in
                do {
                    try handler.perform([request])
                    
                    guard let observation = request.results?.first else {
                        continuation.resume(throwing: VisionProviderError.noSegmentationResults)
                        return
                    }
                    
                    let maskBuffer = observation.pixelBuffer
                    let maskTexture = try self.pixelBufferToMaskTexture(maskBuffer, targetTexture: texture)
                    
                    // Compute bounding box of mask
                    let bounds = self.computeMaskBounds(maskBuffer)
                    
                    let mask = SegmentationMask(
                        texture: maskTexture,
                        labels: [.person],
                        quality: quality,
                        bounds: bounds
                    )
                    
                    continuation.resume(returning: mask)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Optical Flow
    
    @available(macOS 11.0, iOS 14.0, *)
    public func computeOpticalFlow(
        from frame1: MTLTexture,
        to frame2: MTLTexture
    ) async throws -> OpticalFlow {
        let buffer1 = try await textureToPixelBuffer(frame1)
        let buffer2 = try await textureToPixelBuffer(frame2)
        
        let request = VNGenerateOpticalFlowRequest(targetedCVPixelBuffer: buffer2)
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer1, options: [:])
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                do {
                    try handler.perform([request])
                    
                    guard let observation = request.results?.first as? VNPixelBufferObservation else {
                        continuation.resume(throwing: VisionProviderError.noFlowResults)
                        return
                    }
                    
                    // Analyze flow field
                    let flowBuffer = observation.pixelBuffer
                    let (avgMagnitude, dominantDir) = self.analyzeFlowField(flowBuffer)
                    
                    let flow = OpticalFlow(
                        texture: nil,
                        averageMagnitude: avgMagnitude,
                        dominantDirection: dominantDir
                    )
                    
                    continuation.resume(returning: flow)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Scene Classification
    
    public func analyzeScene(_ texture: MTLTexture) async throws -> SceneAnalysis {
        let pixelBuffer = try await textureToPixelBuffer(texture)
        
        let classifyRequest = VNClassifyImageRequest()
        let horizonRequest = VNDetectHorizonRequest()
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                do {
                    try handler.perform([classifyRequest, horizonRequest])
                    
                    // Parse classification results
                    let classifications = (classifyRequest.results ?? [])
                        .sorted { $0.confidence > $1.confidence }
                    
                    let topTags = classifications.prefix(5).map { $0.identifier }
                    let sceneType = self.determineSceneType(from: Array(topTags))
                    
                    // Get horizon angle
                    let horizonAngle: Float? = horizonRequest.results?.first.map {
                        Float($0.angle)
                    }
                    
                    let analysis = SceneAnalysis(
                        sceneType: sceneType,
                        tags: Array(topTags),
                        horizonAngle: horizonAngle,
                        confidence: classifications.first?.confidence ?? 0
                    )
                    
                    continuation.resume(returning: analysis)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Face Detection
    
    /// Detect faces with optional landmarks and pose information
    public func detectFaces(
        in texture: MTLTexture,
        landmarks: Bool = false
    ) async throws -> [FaceObservation] {
        let pixelBuffer = try await textureToPixelBuffer(texture)
        
        let request: VNImageBasedRequest
        if landmarks {
            request = VNDetectFaceLandmarksRequest()
        } else {
            request = VNDetectFaceRectanglesRequest()
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                do {
                    try handler.perform([request])
                    
                    guard let results = request.results as? [VNFaceObservation], !results.isEmpty else {
                        continuation.resume(returning: [])
                        return
                    }
                    
                    let faces = results.map { observation -> FaceObservation in
                        var faceLandmarks: FaceLandmarks? = nil
                        
                        if let vnLandmarks = observation.landmarks {
                            faceLandmarks = FaceLandmarks(
                                leftEye: vnLandmarks.leftEye?.normalizedPoints.first.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) },
                                rightEye: vnLandmarks.rightEye?.normalizedPoints.first.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) },
                                nose: vnLandmarks.nose?.normalizedPoints.first.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) },
                                mouth: vnLandmarks.innerLips?.normalizedPoints.first.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) },
                                leftEyebrow: vnLandmarks.leftEyebrow?.normalizedPoints.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) },
                                rightEyebrow: vnLandmarks.rightEyebrow?.normalizedPoints.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) },
                                outerLips: vnLandmarks.outerLips?.normalizedPoints.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) },
                                faceContour: vnLandmarks.faceContour?.normalizedPoints.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
                            )
                        }
                        
                        return FaceObservation(
                            bounds: observation.boundingBox,
                            confidence: observation.confidence,
                            roll: observation.roll?.floatValue,
                            yaw: observation.yaw?.floatValue,
                            pitch: observation.pitch?.floatValue,
                            landmarks: faceLandmarks
                        )
                    }
                    
                    continuation.resume(returning: faces)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Text Detection
    
    /// Detect text regions with optional OCR recognition
    public func detectText(
        in texture: MTLTexture,
        recognizeText: Bool = false,
        languages: [String] = ["en"]
    ) async throws -> [TextObservation] {
        let pixelBuffer = try await textureToPixelBuffer(texture)
        
        let request: VNImageBasedRequest
        if recognizeText {
            let recognizeRequest = VNRecognizeTextRequest()
            recognizeRequest.recognitionLevel = .accurate
            recognizeRequest.recognitionLanguages = languages
            recognizeRequest.usesLanguageCorrection = true
            request = recognizeRequest
        } else {
            request = VNDetectTextRectanglesRequest()
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                do {
                    try handler.perform([request])
                    
                    var textObservations: [TextObservation] = []
                    
                    if recognizeText {
                        if let results = request.results as? [VNRecognizedTextObservation] {
                            textObservations = results.map { observation in
                                let topCandidate = observation.topCandidates(1).first
                                return TextObservation(
                                    bounds: observation.boundingBox,
                                    text: topCandidate?.string,
                                    confidence: topCandidate?.confidence ?? observation.confidence
                                )
                            }
                        }
                    } else {
                        if let results = request.results as? [VNTextObservation] {
                            textObservations = results.map { observation in
                                TextObservation(
                                    bounds: observation.boundingBox,
                                    text: nil,
                                    confidence: observation.confidence
                                )
                            }
                        }
                    }
                    
                    continuation.resume(returning: textObservations)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Horizon Detection
    
    /// Detect the horizon angle for auto-leveling
    public func detectHorizon(in texture: MTLTexture) async throws -> HorizonObservation? {
        let pixelBuffer = try await textureToPixelBuffer(texture)
        
        let request = VNDetectHorizonRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                do {
                    try handler.perform([request])
                    
                    guard let result = request.results?.first else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    let observation = HorizonObservation(
                        angle: Float(result.angle),
                        transform: result.transform
                    )
                    
                    continuation.resume(returning: observation)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func textureToPixelBuffer(_ texture: MTLTexture) async throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferWidthKey: texture.width,
            kCVPixelBufferHeightKey: texture.height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            texture.width,
            texture.height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw VisionProviderError.pixelBufferCreationFailed
        }
        
        // Use CIContext to render texture to pixel buffer (handles format conversion and private storage)
        guard let ciImage = CIImage(mtlTexture: texture, options: [.colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!]) else {
             throw VisionProviderError.textureConversionFailed
        }
        
        ciContext.render(ciImage, to: buffer)
        
        return buffer
    }
    
    private func pixelBufferToMaskTexture(_ buffer: CVPixelBuffer, targetTexture: MTLTexture) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: targetTexture.width,
            height: targetTexture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .shared
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw VisionProviderError.textureConversionFailed
        }
        
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        
        let srcWidth = CVPixelBufferGetWidth(buffer)
        let srcHeight = CVPixelBufferGetHeight(buffer)
        
        // If sizes match, direct copy
        if srcWidth == targetTexture.width && srcHeight == targetTexture.height {
            if let srcData = CVPixelBufferGetBaseAddress(buffer) {
                let region = MTLRegion(
                    origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: srcWidth, height: srcHeight, depth: 1)
                )
                texture.replace(
                    region: region,
                    mipmapLevel: 0,
                    withBytes: srcData,
                    bytesPerRow: CVPixelBufferGetBytesPerRow(buffer)
                )
            }
        } else {
            // Need to resize - use CIContext to scale
            let ciImage = CIImage(cvPixelBuffer: buffer)
            let scaleX = CGFloat(targetTexture.width) / CGFloat(srcWidth)
            let scaleY = CGFloat(targetTexture.height) / CGFloat(srcHeight)
            let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            
            let colorSpace = CGColorSpaceCreateDeviceGray()
            
            ciContext.render(
                scaledImage,
                to: texture,
                commandBuffer: nil,
                bounds: CGRect(x: 0, y: 0, width: targetTexture.width, height: targetTexture.height),
                colorSpace: colorSpace
            )
        }
        
        return texture
    }
    
    private func computeMaskBounds(_ buffer: CVPixelBuffer) -> CGRect {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return .zero
        }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let data = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        var minX = width
        var maxX = 0
        var minY = height
        var maxY = 0
        
        for y in 0..<height {
            for x in 0..<width {
                let value = data[y * bytesPerRow + x]
                if value > 127 {  // Threshold for mask
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }
        
        if minX > maxX || minY > maxY {
            return .zero
        }
        
        // Return normalized bounds
        return CGRect(
            x: CGFloat(minX) / CGFloat(width),
            y: CGFloat(minY) / CGFloat(height),
            width: CGFloat(maxX - minX) / CGFloat(width),
            height: CGFloat(maxY - minY) / CGFloat(height)
        )
    }
    
    private func analyzeFlowField(_ buffer: CVPixelBuffer) -> (Float, SIMD2<Float>) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return (0, SIMD2<Float>(0, 0))
        }
        
        // Optical flow is typically in a 2-channel float format
        // Analyze to compute average magnitude and dominant direction
        var totalMagnitude: Float = 0
        var totalX: Float = 0
        var totalY: Float = 0
        var count = 0
        
        // Sample every 4th pixel for speed
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let floatsPerRow = bytesPerRow / MemoryLayout<Float>.stride
        let data = baseAddress.assumingMemoryBound(to: Float.self)
        
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                let offset = y * floatsPerRow + x * 2
                if offset + 1 < height * floatsPerRow {
                    let flowX = data[offset]
                    let flowY = data[offset + 1]
                    
                    totalX += flowX
                    totalY += flowY
                    totalMagnitude += sqrt(flowX * flowX + flowY * flowY)
                    count += 1
                }
            }
        }
        
        guard count > 0 else {
            return (0, SIMD2<Float>(0, 0))
        }
        
        let avgMagnitude = totalMagnitude / Float(count)
        let dominantDir = SIMD2<Float>(totalX / Float(count), totalY / Float(count))
        
        return (avgMagnitude, dominantDir)
    }
    
    private func determineSceneType(from tags: [String]) -> SceneType {
        let tagSet = Set(tags.map { $0.lowercased() })
        
        // Check for specific scene indicators
        if tagSet.contains("person") || tagSet.contains("face") || tagSet.contains("portrait") {
            return .portrait
        }
        if tagSet.contains("indoor") || tagSet.contains("room") || tagSet.contains("interior") {
            return .indoor
        }
        if tagSet.contains("city") || tagSet.contains("building") || tagSet.contains("street") || tagSet.contains("urban") {
            return .urban
        }
        if tagSet.contains("nature") || tagSet.contains("forest") || tagSet.contains("tree") || tagSet.contains("plant") {
            return .nature
        }
        if tagSet.contains("landscape") || tagSet.contains("mountain") || tagSet.contains("sky") || tagSet.contains("outdoor") {
            return .landscape
        }
        if tagSet.contains("outdoor") {
            return .outdoor
        }
        
        return .unknown
    }
}
