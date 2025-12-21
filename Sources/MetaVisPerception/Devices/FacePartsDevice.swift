import Foundation
import Vision
import CoreVideo
import CoreGraphics
import CoreML
import CoreImage
import MetaVisCore

/// Tier-0 face parts device stream.
///
/// Current behavior (Sprint 24a):
/// - Always runs fast Vision face landmarks to derive conservative ROI masks for key parts.
/// - Optionally supports a future face-parsing CoreML model (not yet bundled in this repo).
///
/// Teeth: treated as optional. Without a parsing model, we do not attempt to detect teeth pixels;
/// we only provide mouth/lip ROIs that can be used downstream.
public actor FacePartsDevice {

    public struct Options: Sendable, Equatable {
        /// Maximum faces to consider; we select the largest face.
        public var maxFaces: Int

        /// If set, attempts to load a face-parsing model at this path (mlmodelc or mlpackage).
        /// When nil, we check `METAVIS_FACEPARTS_MODEL_PATH`.
        public var modelPath: String?

        public init(maxFaces: Int = 6, modelPath: String? = nil) {
            self.maxFaces = maxFaces
            self.modelPath = modelPath
        }
    }

    public struct FacePartsMetrics: Sendable, Equatable {
        public var detectedFaceCount: Int
        public var primaryFaceRectTopLeft: CGRect?

        /// Normalized mouth ROI rect (top-left origin), derived from lip landmarks.
        public var mouthRectTopLeft: CGRect?

        public var mouthCoverage: Double?
        public var leftEyeCoverage: Double?
        public var rightEyeCoverage: Double?

        public init(
            detectedFaceCount: Int,
            primaryFaceRectTopLeft: CGRect?,
            mouthRectTopLeft: CGRect?,
            mouthCoverage: Double?,
            leftEyeCoverage: Double?,
            rightEyeCoverage: Double?
        ) {
            self.detectedFaceCount = detectedFaceCount
            self.primaryFaceRectTopLeft = primaryFaceRectTopLeft
            self.mouthRectTopLeft = mouthRectTopLeft
            self.mouthCoverage = mouthCoverage
            self.leftEyeCoverage = leftEyeCoverage
            self.rightEyeCoverage = rightEyeCoverage
        }
    }

    public struct FacePartsResult: @unchecked Sendable, Equatable {
        public struct DenseParsing: @unchecked Sendable, Equatable {
            /// Face-parsing crop rect in normalized top-left space (this is the region the label map corresponds to).
            public var parsingRectTopLeft: CGRect

            /// Dense label map (OneComponent8) in crop coordinates.
            /// Pixel values are model-specific class indices.
            public var labelMap: CVPixelBuffer

            /// Optional class count inferred from output shape.
            public var modelClassCount: Int?

            /// Optional derived masks (OneComponent8, 0/255) in crop coordinates.
            public var skinMask: CVPixelBuffer?
            public var hairMask: CVPixelBuffer?
            public var lipsMask: CVPixelBuffer?
            public var innerMouthMask: CVPixelBuffer?

            public init(
                parsingRectTopLeft: CGRect,
                labelMap: CVPixelBuffer,
                modelClassCount: Int?,
                skinMask: CVPixelBuffer?,
                hairMask: CVPixelBuffer?,
                lipsMask: CVPixelBuffer?,
                innerMouthMask: CVPixelBuffer?
            ) {
                self.parsingRectTopLeft = parsingRectTopLeft
                self.labelMap = labelMap
                self.modelClassCount = modelClassCount
                self.skinMask = skinMask
                self.hairMask = hairMask
                self.lipsMask = lipsMask
                self.innerMouthMask = innerMouthMask
            }
        }

        /// Primary face rect, normalized, top-left origin.
        public var faceRectTopLeft: CGRect?

        /// Normalized mouth ROI rect (top-left origin), derived from lip landmarks.
        public var mouthRectTopLeft: CGRect?

        /// Full-frame OneComponent8 masks (0/255). Nil when landmark region not available.
        public var mouthMask: CVPixelBuffer?
        public var leftEyeMask: CVPixelBuffer?
        public var rightEyeMask: CVPixelBuffer?

        /// Optional dense face parsing outputs (crop coordinate space).
        public var denseParsing: DenseParsing?

        public var metrics: FacePartsMetrics
        public var evidenceConfidence: ConfidenceRecordV1

        public init(
            faceRectTopLeft: CGRect?,
            mouthRectTopLeft: CGRect?,
            mouthMask: CVPixelBuffer?,
            leftEyeMask: CVPixelBuffer?,
            rightEyeMask: CVPixelBuffer?,
            denseParsing: DenseParsing?,
            metrics: FacePartsMetrics,
            evidenceConfidence: ConfidenceRecordV1
        ) {
            self.faceRectTopLeft = faceRectTopLeft
            self.mouthRectTopLeft = mouthRectTopLeft
            self.mouthMask = mouthMask
            self.leftEyeMask = leftEyeMask
            self.rightEyeMask = rightEyeMask
            self.denseParsing = denseParsing
            self.metrics = metrics
            self.evidenceConfidence = evidenceConfidence
        }
    }

    public enum FacePartsDeviceError: Error, Sendable, Equatable {
        case unableToCreateMask
    }

    private let options: Options

    // Reuse request for performance.
    private var landmarksRequest: VNDetectFaceLandmarksRequest?

    // Optional CoreML face parsing model (not required for Tier-0).
    private var faceParsingModel: MLModel?
    private var faceParsingModelPath: String?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    public init(options: Options = Options()) {
        self.options = options
    }

    public func warmUp() async throws {
        if landmarksRequest == nil {
            landmarksRequest = VNDetectFaceLandmarksRequest()
        }

        // Best-effort: do not throw if the parsing model is missing.
        _ = try? await loadFaceParsingModelIfPresent()
    }

    public func coolDown() async {
        landmarksRequest = nil
        faceParsingModel = nil
        faceParsingModelPath = nil
    }

    public func facePartsResult(in pixelBuffer: CVPixelBuffer) async throws -> FacePartsResult {
        if landmarksRequest == nil {
            try await warmUp()
        }

        guard let request = landmarksRequest else {
            let conf = ConfidenceRecordV1.evidence(
                score: 0.0,
                sources: [.vision],
                reasons: [.faceparts_infer_failed],
                evidenceRefs: []
            )
            let metrics = FacePartsMetrics(
                detectedFaceCount: 0,
                primaryFaceRectTopLeft: nil,
                mouthRectTopLeft: nil,
                mouthCoverage: nil,
                leftEyeCoverage: nil,
                rightEyeCoverage: nil
            )
            return FacePartsResult(
                faceRectTopLeft: nil,
                mouthRectTopLeft: nil,
                mouthMask: nil,
                leftEyeMask: nil,
                rightEyeMask: nil,
                denseParsing: nil,
                metrics: metrics,
                evidenceConfidence: conf
            )
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([request])

        let faces = request.results ?? []
        let detectedCount = faces.count

        guard let primary = selectPrimaryFace(faces: faces, maxFaces: options.maxFaces) else {
            let conf = ConfidenceRecordV1.evidence(
                score: 0.0,
                sources: [.vision],
                reasons: [.no_face_detected],
                evidenceRefs: []
            )
            let metrics = FacePartsMetrics(
                detectedFaceCount: detectedCount,
                primaryFaceRectTopLeft: nil,
                mouthRectTopLeft: nil,
                mouthCoverage: nil,
                leftEyeCoverage: nil,
                rightEyeCoverage: nil
            )
            return FacePartsResult(
                faceRectTopLeft: nil,
                mouthRectTopLeft: nil,
                mouthMask: nil,
                leftEyeMask: nil,
                rightEyeMask: nil,
                denseParsing: nil,
                metrics: metrics,
                evidenceConfidence: conf
            )
        }

        let faceRectTL = normalizeObservationToTopLeft(primary)

        // Landmark-derived masks.
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)

        let mouthPts = landmarksPolygonNormalizedTopLeft(primary, region: primary.landmarks?.outerLips)
            ?? landmarksPolygonNormalizedTopLeft(primary, region: primary.landmarks?.innerLips)

        let leftEyePts = landmarksPolygonNormalizedTopLeft(primary, region: primary.landmarks?.leftEye)
        let rightEyePts = landmarksPolygonNormalizedTopLeft(primary, region: primary.landmarks?.rightEye)

        let mouthRectTL = mouthPts.flatMap { boundingRectNormalizedTopLeft(points: $0) }

        let mouthMask = try mouthPts.map { try rasterizePolygonMaskOneComponent8(width: w, height: h, normalizedTopLeftPoints: $0) }
        let leftEyeMask = try leftEyePts.map { try rasterizePolygonMaskOneComponent8(width: w, height: h, normalizedTopLeftPoints: $0) }
        let rightEyeMask = try rightEyePts.map { try rasterizePolygonMaskOneComponent8(width: w, height: h, normalizedTopLeftPoints: $0) }

        let mouthCoverage = mouthMask.map { meanByteValue($0) / 255.0 }
        let leftEyeCoverage = leftEyeMask.map { meanByteValue($0) / 255.0 }
        let rightEyeCoverage = rightEyeMask.map { meanByteValue($0) / 255.0 }

        // Optional dense face parsing (reliability-first features).
        let parsingOutcome = await denseParsingOutcome(pixelBuffer: pixelBuffer, faceRectTopLeft: faceRectTL)

        var reasons: [ReasonCodeV1] = []

        switch parsingOutcome {
        case .missing:
            reasons.append(.faceparts_model_missing)
        case .failed:
            reasons.append(.faceparts_infer_failed)
        case .success:
            break
        }

        // If landmarks + dense parsing are both missing, keep the score conservative.
        let haveAnyPart = (mouthMask != nil) || (leftEyeMask != nil) || (rightEyeMask != nil) || (parsingOutcome.denseParsing != nil)
        if !haveAnyPart {
            reasons.append(.faceparts_infer_failed)
        }

        let score: Float
        if !haveAnyPart {
            score = 0.20
        } else {
            // Reliability-first: landmarks-only can be useful, but dense parsing provides more stable masks.
            if parsingOutcome.denseParsing != nil {
                score = 0.85
            } else if reasons.contains(.faceparts_model_missing) {
                score = 0.60
            } else {
                score = 0.70
            }
        }

        let denseRefs: [EvidenceRefV1] = parsingOutcome.denseEvidenceRefs
        let refs: [EvidenceRefV1] =
            (mouthCoverage.map { [.metric("faceparts.mouthCoverage", value: $0)] } ?? [])
            + (leftEyeCoverage.map { [.metric("faceparts.leftEyeCoverage", value: $0)] } ?? [])
            + (rightEyeCoverage.map { [.metric("faceparts.rightEyeCoverage", value: $0)] } ?? [])
            + denseRefs

        let conf = ConfidenceRecordV1.evidence(
            score: score,
            sources: [.vision],
            reasons: reasons,
            evidenceRefs: refs
        )

        let metrics = FacePartsMetrics(
            detectedFaceCount: detectedCount,
            primaryFaceRectTopLeft: faceRectTL,
            mouthRectTopLeft: mouthRectTL,
            mouthCoverage: mouthCoverage,
            leftEyeCoverage: leftEyeCoverage,
            rightEyeCoverage: rightEyeCoverage
        )

        return FacePartsResult(
            faceRectTopLeft: faceRectTL,
            mouthRectTopLeft: mouthRectTL,
            mouthMask: mouthMask,
            leftEyeMask: leftEyeMask,
            rightEyeMask: rightEyeMask,
            denseParsing: parsingOutcome.denseParsing,
            metrics: metrics,
            evidenceConfidence: conf
        )
    }

    // MARK: - Dense face parsing (optional)

    private enum DenseParsingOutcome {
        case missing
        case failed
        case success(FacePartsResult.DenseParsing)

        var denseParsing: FacePartsResult.DenseParsing? {
            switch self {
            case .success(let v): return v
            default: return nil
            }
        }

        var denseEvidenceRefs: [EvidenceRefV1] {
            guard let d = denseParsing else { return [] }
            var out: [EvidenceRefV1] = []
            if let m = d.skinMask { out.append(.metric("faceparts.parsing.skinCoverage", value: meanByteValueStatic(m) / 255.0)) }
            if let m = d.hairMask { out.append(.metric("faceparts.parsing.hairCoverage", value: meanByteValueStatic(m) / 255.0)) }
            if let m = d.lipsMask { out.append(.metric("faceparts.parsing.lipsCoverage", value: meanByteValueStatic(m) / 255.0)) }
            if let m = d.innerMouthMask { out.append(.metric("faceparts.parsing.innerMouthCoverage", value: meanByteValueStatic(m) / 255.0)) }
            if let n = d.modelClassCount { out.append(.metric("faceparts.parsing.classCount", value: Double(n))) }
            return out
        }
    }

    private func denseParsingOutcome(pixelBuffer: CVPixelBuffer, faceRectTopLeft: CGRect) async -> DenseParsingOutcome {
        do {
            guard let model = try await loadFaceParsingModelIfPresent() else {
                return .missing
            }

            // Use a padded face crop to capture hairline and reduce background.
            let paddedRectTL = padNormalizedTopLeftRect(faceRectTopLeft, padRatio: 0.10)
            let cropPB = try renderCropToBGRA(pixelBuffer: pixelBuffer, cropRectTopLeft: paddedRectTL, targetSquareSize: modelInputSize(model: model) ?? 512)

            let inName = firstImageInputName(of: model)
            let outName = firstMultiArrayOutputName(of: model)
            let provider = try MLDictionaryFeatureProvider(dictionary: [inName: MLFeatureValue(pixelBuffer: cropPB)])
            let pred = try await model.prediction(from: provider)
            guard let outArr = pred.featureValue(for: outName)?.multiArrayValue else {
                return .failed
            }

            let (labelMap, classCount) = try multiArrayToLabelMapOneComponent8(outArr)

            // Reliable, common face-parsing mapping (e.g., CelebAMask-HQ / face-parsing.pytorch style):
            // 0 background, 1 skin, 11 mouth, 12 upper lip, 13 lower lip, 17 hair, 18 hat.
            let skin = try maskFromLabelMap(labelMap, labels: [1])
            let hair = try maskFromLabelMap(labelMap, labels: [17])
            let lips = try maskFromLabelMap(labelMap, labels: [12, 13])
            let innerMouth = try maskFromLabelMap(labelMap, labels: [11, 12, 13])

            let dense = FacePartsResult.DenseParsing(
                parsingRectTopLeft: paddedRectTL,
                labelMap: labelMap,
                modelClassCount: classCount,
                skinMask: skin,
                hairMask: hair,
                lipsMask: lips,
                innerMouthMask: innerMouth
            )

            return .success(dense)
        } catch {
            return .failed
        }
    }

    private func loadFaceParsingModelIfPresent() async throws -> MLModel? {
        let p = resolveModelPath()
        if p == nil { return nil }
        guard let path = p else { return nil }

        if let faceParsingModel, faceParsingModelPath == path {
            return faceParsingModel
        }

        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        let cfg = NeuralEngineContext.shared.makeConfiguration(useANE: true)
        let loaded = try MLModel(contentsOf: URL(fileURLWithPath: path), configuration: cfg)
        faceParsingModel = loaded
        faceParsingModelPath = path
        return loaded
    }

    private func modelInputSize(model: MLModel) -> Int? {
        guard let inName = model.modelDescription.inputDescriptionsByName.first(where: { $0.value.type == .image })?.key else {
            return nil
        }
        guard let desc = model.modelDescription.inputDescriptionsByName[inName] else { return nil }
        guard let constraint = desc.imageConstraint else { return nil }
        let w = constraint.pixelsWide
        let h = constraint.pixelsHigh
        if w > 0 && h > 0 {
            return max(w, h)
        }
        return nil
    }

    private func firstImageInputName(of model: MLModel) -> String {
        if let hit = model.modelDescription.inputDescriptionsByName.first(where: { $0.value.type == .image }) {
            return hit.key
        }
        return model.modelDescription.inputDescriptionsByName.keys.sorted().first ?? "image"
    }

    private func firstMultiArrayOutputName(of model: MLModel) -> String {
        if let hit = model.modelDescription.outputDescriptionsByName.first(where: { $0.value.type == .multiArray }) {
            return hit.key
        }
        return model.modelDescription.outputDescriptionsByName.keys.sorted().first ?? "output"
    }

    private func padNormalizedTopLeftRect(_ r: CGRect, padRatio: CGFloat) -> CGRect {
        guard r.width > 0.0001, r.height > 0.0001 else { return r }
        let dx = r.width * padRatio
        let dy = r.height * padRatio
        return r.insetBy(dx: -dx, dy: -dy)
            .standardized
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private func renderCropToBGRA(pixelBuffer: CVPixelBuffer, cropRectTopLeft: CGRect, targetSquareSize: Int) throws -> CVPixelBuffer {
        let w = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let h = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        guard w > 1, h > 1 else { throw FacePartsDeviceError.unableToCreateMask }

        // Convert TL-normalized rect to pixel-space bottom-left rect for CoreImage.
        let pxTL = CGRect(
            x: cropRectTopLeft.origin.x * w,
            y: cropRectTopLeft.origin.y * h,
            width: cropRectTopLeft.width * w,
            height: cropRectTopLeft.height * h
        ).standardized

        let pxBL = CGRect(
            x: pxTL.origin.x,
            y: h - pxTL.origin.y - pxTL.height,
            width: pxTL.width,
            height: pxTL.height
        ).standardized
        let crop = pxBL.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard crop.width > 2, crop.height > 2 else { throw FacePartsDeviceError.unableToCreateMask }

        let src = CIImage(cvPixelBuffer: pixelBuffer)
        let cropped = src.cropped(to: crop)

        // Scale to square.
        let target = CGFloat(targetSquareSize)
        let scaleX = target / cropped.extent.width
        let scaleY = target / cropped.extent.height
        let scaled = cropped.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        let fitted = scaled.cropped(to: CGRect(x: 0, y: 0, width: target, height: target))

        var out: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: targetSquareSize,
            kCVPixelBufferHeightKey as String: targetSquareSize,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, targetSquareSize, targetSquareSize, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out)
        guard status == kCVReturnSuccess, let pb = out else { throw FacePartsDeviceError.unableToCreateMask }
        ciContext.render(fitted, to: pb)
        return pb
    }

    private func multiArrayToLabelMapOneComponent8(_ arr: MLMultiArray) throws -> (CVPixelBuffer, Int?) {
        let shape = arr.shape.map { $0.intValue }

        // Supported:
        // - [H, W] label indices
        // - [C, H, W] scores
        // - [1, C, H, W] scores
        if shape.count == 2 {
            let h = shape[0]
            let w = shape[1]
            let pb = try makeOneComponent8(width: w, height: h)
            CVPixelBufferLockBaseAddress(pb, [])
            defer { CVPixelBufferUnlockBaseAddress(pb, []) }
            guard let base = CVPixelBufferGetBaseAddress(pb) else { throw FacePartsDeviceError.unableToCreateMask }
            let bpr = CVPixelBufferGetBytesPerRow(pb)
            for y in 0..<h {
                let row = base.advanced(by: y * bpr).assumingMemoryBound(to: UInt8.self)
                for x in 0..<w {
                    let v = arr[[NSNumber(value: y), NSNumber(value: x)]].intValue
                    row[x] = UInt8(max(0, min(255, v)))
                }
            }
            return (pb, nil)
        }

        let is4D = shape.count == 4 && shape[0] == 1
        let is3D = shape.count == 3
        guard is3D || is4D else { throw FacePartsDeviceError.unableToCreateMask }

        let c = is4D ? shape[1] : shape[0]
        let h = is4D ? shape[2] : shape[1]
        let w = is4D ? shape[3] : shape[2]
        guard c > 1, h > 0, w > 0 else { throw FacePartsDeviceError.unableToCreateMask }

        let pb = try makeOneComponent8(width: w, height: h)
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { throw FacePartsDeviceError.unableToCreateMask }
        let bpr = CVPixelBufferGetBytesPerRow(pb)

        let strides = arr.strides.map { $0.intValue }

        func offset(_ i0: Int, _ i1: Int, _ i2: Int, _ i3: Int?) -> Int {
            if is4D {
                let i3v = i3 ?? 0
                return i0 * strides[0] + i1 * strides[1] + i2 * strides[2] + i3v * strides[3]
            } else {
                return i0 * strides[0] + i1 * strides[1] + i2 * strides[2]
            }
        }

        for y in 0..<h {
            let row = base.advanced(by: y * bpr).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w {
                var bestC = 0
                var bestV = -Double.infinity
                for ci in 0..<c {
                    let idx = is4D ? offset(0, ci, y, x) : offset(ci, y, x, nil)
                    let v = arr[idx].doubleValue
                    if v > bestV {
                        bestV = v
                        bestC = ci
                    }
                }
                row[x] = UInt8(max(0, min(255, bestC)))
            }
        }

        return (pb, c)
    }

    private func maskFromLabelMap(_ labelMap: CVPixelBuffer, labels: [UInt8]) throws -> CVPixelBuffer {
        let labelSet = Set(labels)
        let w = CVPixelBufferGetWidth(labelMap)
        let h = CVPixelBufferGetHeight(labelMap)
        guard w > 0, h > 0 else { throw FacePartsDeviceError.unableToCreateMask }
        let out = try makeOneComponent8(width: w, height: h)

        CVPixelBufferLockBaseAddress(labelMap, .readOnly)
        CVPixelBufferLockBaseAddress(out, [])
        defer {
            CVPixelBufferUnlockBaseAddress(out, [])
            CVPixelBufferUnlockBaseAddress(labelMap, .readOnly)
        }

        guard let srcBase = CVPixelBufferGetBaseAddress(labelMap), let dstBase = CVPixelBufferGetBaseAddress(out) else {
            throw FacePartsDeviceError.unableToCreateMask
        }

        let srcBpr = CVPixelBufferGetBytesPerRow(labelMap)
        let dstBpr = CVPixelBufferGetBytesPerRow(out)

        for y in 0..<h {
            let srcRow = srcBase.advanced(by: y * srcBpr).assumingMemoryBound(to: UInt8.self)
            let dstRow = dstBase.advanced(by: y * dstBpr).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w {
                dstRow[x] = labelSet.contains(srcRow[x]) ? 255 : 0
            }
        }

        return out
    }

    private func makeOneComponent8(width: Int, height: Int) throws -> CVPixelBuffer {
        var out: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_OneComponent8),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_OneComponent8, attrs as CFDictionary, &out)
        guard status == kCVReturnSuccess, let pb = out else { throw FacePartsDeviceError.unableToCreateMask }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        if let base = CVPixelBufferGetBaseAddress(pb) {
            let bpr = CVPixelBufferGetBytesPerRow(pb)
            for y in 0..<height {
                memset(base.advanced(by: y * bpr), 0, width)
            }
        }
        return pb
    }

    private static func meanByteValueStatic(_ pixelBuffer: CVPixelBuffer) -> Double {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_OneComponent8 else { return 0.0 }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0.0 }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)

        var sum: UInt64 = 0
        for y in 0..<height {
            let row = base.advanced(by: y * bpr).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                sum += UInt64(row[x])
            }
        }

        let denom = max(1, width * height)
        return Double(sum) / Double(denom)
    }

    private func boundingRectNormalizedTopLeft(points: [CGPoint]) -> CGRect? {
        guard !points.isEmpty else { return nil }

        var minX: CGFloat = .infinity
        var minY: CGFloat = .infinity
        var maxX: CGFloat = -.infinity
        var maxY: CGFloat = -.infinity

        for p in points {
            if !p.x.isFinite || !p.y.isFinite { continue }
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }

        if !minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite { return nil }

        let rect = CGRect(x: minX, y: minY, width: max(0.0, maxX - minX), height: max(0.0, maxY - minY))
            .standardized
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

        guard rect.width > 0.0001, rect.height > 0.0001 else { return nil }
        return rect
    }

    private func resolveModelPath() -> String? {
        if let p = options.modelPath, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return p
        }
        if let env = ProcessInfo.processInfo.environment["METAVIS_FACEPARTS_MODEL_PATH"], !env.isEmpty {
            return env
        }

        // Repo-default (mirrors other tools like diarization): load from assets if present.
        // We accept either compiled .mlmodelc or an uncompiled .mlpackage.
        let cwd = FileManager.default.currentDirectoryPath
        let base = URL(fileURLWithPath: cwd).appendingPathComponent("assets/models/face_parsing")

        let mlmodelc = base.appendingPathComponent("FaceParsing.mlmodelc").path
        if FileManager.default.fileExists(atPath: mlmodelc) {
            return mlmodelc
        }

        let mlpackage = base.appendingPathComponent("FaceParsing.mlpackage").path
        if FileManager.default.fileExists(atPath: mlpackage) {
            return mlpackage
        }

        return nil
    }

    private func selectPrimaryFace(faces: [VNFaceObservation], maxFaces: Int) -> VNFaceObservation? {
        guard !faces.isEmpty else { return nil }
        let limited = faces.prefix(max(1, maxFaces))
        return limited.max { a, b in
            (a.boundingBox.width * a.boundingBox.height) < (b.boundingBox.width * b.boundingBox.height)
        }
    }

    private func normalizeObservationToTopLeft(_ observation: VNFaceObservation) -> CGRect {
        let old = observation.boundingBox
        let newY = 1.0 - (old.origin.y + old.height)
        return CGRect(x: old.origin.x, y: newY, width: old.width, height: old.height)
    }

    private func landmarksPolygonNormalizedTopLeft(_ face: VNFaceObservation, region: VNFaceLandmarkRegion2D?) -> [CGPoint]? {
        guard let region else { return nil }
        let rectBL = face.boundingBox // normalized, origin bottom-left
        let pts = region.normalizedPoints
        if pts.isEmpty { return nil }

        var out: [CGPoint] = []
        out.reserveCapacity(pts.count)

        for p in pts {
            let xImg = rectBL.origin.x + CGFloat(p.x) * rectBL.width
            let yImgBL = rectBL.origin.y + CGFloat(p.y) * rectBL.height
            let yTL = 1.0 - yImgBL
            out.append(CGPoint(x: xImg, y: yTL))
        }

        return out
    }

    private func rasterizePolygonMaskOneComponent8(width: Int, height: Int, normalizedTopLeftPoints: [CGPoint]) throws -> CVPixelBuffer {
        guard normalizedTopLeftPoints.count >= 3 else { throw FacePartsDeviceError.unableToCreateMask }

        var out: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_OneComponent8),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_OneComponent8, attrs as CFDictionary, &out)
        guard status == kCVReturnSuccess, let pb = out else { throw FacePartsDeviceError.unableToCreateMask }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { throw FacePartsDeviceError.unableToCreateMask }
        let bpr = CVPixelBufferGetBytesPerRow(pb)

        // Clear buffer to 0.
        for y in 0..<height {
            memset(base.advanced(by: y * bpr), 0, width)
        }

        guard let ctx = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw FacePartsDeviceError.unableToCreateMask
        }

        ctx.setAllowsAntialiasing(false)
        ctx.setShouldAntialias(false)
        ctx.setFillColor(gray: 1.0, alpha: 1.0)

        let path = CGMutablePath()
        for (i, p) in normalizedTopLeftPoints.enumerated() {
            let x = max(0.0, min(CGFloat(width - 1), p.x * CGFloat(width)))
            let y = max(0.0, min(CGFloat(height - 1), p.y * CGFloat(height)))
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()

        ctx.addPath(path)
        ctx.fillPath()

        return pb
    }

    private func meanByteValue(_ pixelBuffer: CVPixelBuffer) -> Double {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_OneComponent8 else { return 0.0 }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0.0 }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)

        var sum: UInt64 = 0
        for y in 0..<height {
            let row = base.advanced(by: y * bpr).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                sum += UInt64(row[x])
            }
        }

        let denom = max(1, width * height)
        return Double(sum) / Double(denom)
    }
}
