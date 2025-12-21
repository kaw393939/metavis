import Foundation
import CoreML
import CoreVideo
import CoreImage
import MetaVisCore

/// Tier-1 promptable segmentation device (MobileSAM).
///
/// This is intentionally designed to be safe-by-default:
/// - If models are not present locally, it returns an explicit governed confidence with
///   `.mobilesam_model_missing` and no mask (no crashes, no silent behavior).
/// - Tests should be env-gated because models are not bundled in the repo by default.
public actor MobileSAMDevice {

    public struct Options: Sendable, Equatable {
        /// Optional directory containing MobileSAM models.
        ///
        /// If nil, we check `METAVIS_MOBILESAM_MODEL_DIR`, then repo defaults.
        public var modelDirectory: String?

        /// Preferred compute unit for CoreML.
        public var computeUnit: AIComputeUnit

        /// Square input size expected by MobileSAM encoder.
        public var encoderInputSize: Int

        /// Threshold applied to mask logits/probabilities.
        public var maskThreshold: Float

        /// If true, cache the most recent image encoder embedding for the last-seen input frame.
        ///
        /// This is intended to accelerate interactive prompting on the same frame.
        public var enableEmbeddingCache: Bool

        /// Maximum number of cached encoder embeddings when using a caller-supplied cache key.
        ///
        /// This keeps memory bounded for interactive workflows.
        public var maxEmbeddingCacheEntries: Int

        public init(
            modelDirectory: String? = nil,
            computeUnit: AIComputeUnit = .all,
            encoderInputSize: Int = 1024,
            maskThreshold: Float = 0.0,
            enableEmbeddingCache: Bool = true,
            maxEmbeddingCacheEntries: Int = 4
        ) {
            self.modelDirectory = modelDirectory
            self.computeUnit = computeUnit
            self.encoderInputSize = encoderInputSize
            self.maskThreshold = maskThreshold
            self.enableEmbeddingCache = enableEmbeddingCache
            self.maxEmbeddingCacheEntries = maxEmbeddingCacheEntries
        }
    }

    public struct PointPrompt: Sendable, Equatable {
        /// Normalized image coordinates in top-left origin space.
        public var pointTopLeft: CGPoint
        /// 1 = positive, 0 = negative
        public var label: Int

        public init(pointTopLeft: CGPoint, label: Int = 1) {
            self.pointTopLeft = pointTopLeft
            self.label = label
        }
    }

    public struct MobileSAMMetrics: Sendable, Equatable {
        public var maskCoverage: Double?
        public var encoderReused: Bool?

        public init(maskCoverage: Double?, encoderReused: Bool? = nil) {
            self.maskCoverage = maskCoverage
            self.encoderReused = encoderReused
        }
    }

    public struct MobileSAMResult: @unchecked Sendable, Equatable {
        public var mask: CVPixelBuffer?
        public var metrics: MobileSAMMetrics
        public var evidenceConfidence: ConfidenceRecordV1

        public init(mask: CVPixelBuffer?, metrics: MobileSAMMetrics, evidenceConfidence: ConfidenceRecordV1) {
            self.mask = mask
            self.metrics = metrics
            self.evidenceConfidence = evidenceConfidence
        }
    }

    public enum MobileSAMDeviceError: Error, Sendable, Equatable {
        case modelNotFound
        case modelLoadFailed
        case invalidPrompt
        case inferenceFailed
        case preprocessingFailed
        case outputUnsupported
    }

    private let options: Options

    private var imageEncoder: MLModel?
    private var promptEncoder: MLModel?
    private var maskDecoder: MLModel?

    private var cachedModelDir: String?

    private var cachedImageEmbeddingPixelBufferID: ObjectIdentifier?
    private var cachedImageEmbedding: MLMultiArray?

    private var cachedEmbeddingsByKey: [String: MLMultiArray] = [:]
    private var cachedEmbeddingKeyOrder: [String] = []

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    public init(options: Options = Options()) {
        self.options = options
    }

    public func warmUp() async throws {
        _ = try loadModelsIfAvailable()
    }

    public func coolDown() async {
        imageEncoder = nil
        promptEncoder = nil
        maskDecoder = nil
        cachedModelDir = nil
        cachedImageEmbeddingPixelBufferID = nil
        cachedImageEmbedding = nil
        cachedEmbeddingsByKey.removeAll()
        cachedEmbeddingKeyOrder.removeAll()
    }

    /// Segments a single object using a point prompt.
    ///
    /// If models are missing, returns `mask=nil` and governed evidence confidence.
    public func segment(
        pixelBuffer: CVPixelBuffer,
        prompt: PointPrompt
    ) async -> MobileSAMResult {
        await segment(pixelBuffer: pixelBuffer, prompt: prompt, cacheKey: nil)
    }

    /// Segments a single object using a point prompt, optionally reusing an encoder embedding.
    ///
    /// - Parameter cacheKey: Caller-supplied key to reuse an encoder embedding across frame copies
    ///   (e.g. assetID+timeSeconds+keyframeIndex). When nil, falls back to single-entry reuse based
    ///   on the `CVPixelBuffer` object identity.
    public func segment(
        pixelBuffer: CVPixelBuffer,
        prompt: PointPrompt,
        cacheKey: String?
    ) async -> MobileSAMResult {
        guard prompt.pointTopLeft.x.isFinite, prompt.pointTopLeft.y.isFinite else {
            let conf = ConfidenceRecordV1.evidence(
                score: 0.0,
                sources: [.vision],
                reasons: [.mobilesam_infer_failed],
                evidenceRefs: []
            )
            return MobileSAMResult(mask: nil, metrics: .init(maskCoverage: nil), evidenceConfidence: conf)
        }

        do {
            guard let bundle = try loadModelsIfAvailable() else {
                let conf = ConfidenceRecordV1.evidence(
                    score: 0.0,
                    sources: [.vision],
                    reasons: [.mobilesam_model_missing],
                    evidenceRefs: []
                )
                return MobileSAMResult(mask: nil, metrics: .init(maskCoverage: nil), evidenceConfidence: conf)
            }

            var encoderReused = false
            let imageEmbedding: MLMultiArray

            if options.enableEmbeddingCache, let k = cacheKey?.trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty {
                if let cached = cachedEmbeddingsByKey[k] {
                    encoderReused = true
                    imageEmbedding = cached
                } else {
                    let embedding = try await encodeImageEmbedding(pixelBuffer: pixelBuffer, bundle: bundle)
                    cacheEmbedding(embedding, forKey: k)
                    imageEmbedding = embedding
                }
            } else {
                // Fall back to single-entry caching based on CVPixelBuffer identity.
                let pbID = ObjectIdentifier(pixelBuffer as AnyObject)
                if options.enableEmbeddingCache, cachedImageEmbeddingPixelBufferID == pbID, let cached = cachedImageEmbedding {
                    encoderReused = true
                    imageEmbedding = cached
                } else {
                    let embedding = try await encodeImageEmbedding(pixelBuffer: pixelBuffer, bundle: bundle)
                    cachedImageEmbeddingPixelBufferID = pbID
                    cachedImageEmbedding = embedding
                    imageEmbedding = embedding
                }
            }

            // 2) Prompt encoder (point only).
            // We do best-effort auto-detect: first multiarray input is points, second is labels.
            // If the model is different, caller can set METAVIS_MOBILESAM_MODEL_DIR to a known-compatible package.
            let (pointsName, labelsName) = firstTwoMultiArrayInputNames(of: bundle.promptEncoder)

            let points = try makePointsMultiArray(pointTopLeft: prompt.pointTopLeft, label: prompt.label, size: options.encoderInputSize)
            let labels = try makeLabelsMultiArray(label: prompt.label)

            let promptProvider = try MLDictionaryFeatureProvider(dictionary: [
                pointsName: MLFeatureValue(multiArray: points),
                labelsName: MLFeatureValue(multiArray: labels)
            ])
            let promptOutName = firstMultiArrayOutputName(of: bundle.promptEncoder)
            let promptOut = try await bundle.promptEncoder.prediction(from: promptProvider)
            guard let promptEmbedding = promptOut.featureValue(for: promptOutName)?.multiArrayValue else {
                throw MobileSAMDeviceError.outputUnsupported
            }

            // 3) Mask decoder.
            // Best-effort: feed the first 2 multiarray inputs with [imageEmbedding, promptEmbedding].
            let (decIn0, decIn1) = firstTwoMultiArrayInputNames(of: bundle.maskDecoder)
            let decOutName = firstMultiArrayOutputName(of: bundle.maskDecoder)

            let decProvider = try MLDictionaryFeatureProvider(dictionary: [
                decIn0: MLFeatureValue(multiArray: imageEmbedding),
                decIn1: MLFeatureValue(multiArray: promptEmbedding)
            ])

            let decOut = try await bundle.maskDecoder.prediction(from: decProvider)
            guard let maskArray = decOut.featureValue(for: decOutName)?.multiArrayValue else {
                throw MobileSAMDeviceError.outputUnsupported
            }

            let maskPB = try maskMultiArrayToOneComponent8(maskArray, threshold: options.maskThreshold)
            let coverage = meanByteValue(maskPB) / 255.0

            let conf = ConfidenceRecordV1.evidence(
                score: 0.75,
                sources: [.vision],
                reasons: [],
                evidenceRefs: [
                    .metric("mobilesam.maskCoverage", value: coverage)
                ]
            )

            return MobileSAMResult(
                mask: maskPB,
                metrics: .init(maskCoverage: coverage, encoderReused: encoderReused),
                evidenceConfidence: conf
            )
        } catch {
            let conf = ConfidenceRecordV1.evidence(
                score: 0.0,
                sources: [.vision],
                reasons: [.mobilesam_infer_failed],
                evidenceRefs: []
            )
            return MobileSAMResult(mask: nil, metrics: .init(maskCoverage: nil), evidenceConfidence: conf)
        }
    }

    private func encodeImageEmbedding(pixelBuffer: CVPixelBuffer, bundle: ModelBundle) async throws -> MLMultiArray {
        // Preprocess image.
        let inputImage = try resizeToSquareBGRA(pixelBuffer: pixelBuffer, size: options.encoderInputSize)

        // Image encoder.
        let encInName = firstImageInputName(of: bundle.imageEncoder)
        let encOutName = firstMultiArrayOutputName(of: bundle.imageEncoder)

        let encProvider = try MLDictionaryFeatureProvider(dictionary: [encInName: MLFeatureValue(pixelBuffer: inputImage)])
        let encOut = try await bundle.imageEncoder.prediction(from: encProvider)
        guard let embedding = encOut.featureValue(for: encOutName)?.multiArrayValue else {
            throw MobileSAMDeviceError.outputUnsupported
        }
        return embedding
    }

    private func cacheEmbedding(_ embedding: MLMultiArray, forKey key: String) {
        cachedEmbeddingsByKey[key] = embedding

        // Deterministic LRU-ish: keep insertion order, evict oldest.
        cachedEmbeddingKeyOrder.removeAll(where: { $0 == key })
        cachedEmbeddingKeyOrder.append(key)

        let cap = max(1, options.maxEmbeddingCacheEntries)
        while cachedEmbeddingKeyOrder.count > cap {
            let evict = cachedEmbeddingKeyOrder.removeFirst()
            cachedEmbeddingsByKey.removeValue(forKey: evict)
        }
    }

    // MARK: - Model loading

    private struct ModelBundle {
        let imageEncoder: MLModel
        let promptEncoder: MLModel
        let maskDecoder: MLModel
    }

    private func loadModelsIfAvailable() throws -> ModelBundle? {
        if let imageEncoder, let promptEncoder, let maskDecoder {
            return ModelBundle(imageEncoder: imageEncoder, promptEncoder: promptEncoder, maskDecoder: maskDecoder)
        }

        guard let dir = resolveModelDirectory() else {
            return nil
        }

        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) {
            return nil
        }

        func findModelURL(_ name: String) -> URL? {
            let base = URL(fileURLWithPath: dir)

            let mlmodelc = base.appendingPathComponent("\(name).mlmodelc")
            if fm.fileExists(atPath: mlmodelc.path) { return mlmodelc }

            let mlpackage = base.appendingPathComponent("\(name).mlpackage")
            if fm.fileExists(atPath: mlpackage.path) { return mlpackage }

            return nil
        }

        guard
            let encURL = findModelURL("ImageEncoder"),
            let prmURL = findModelURL("PromptEncoder"),
            let decURL = findModelURL("MaskDecoder")
        else {
            return nil
        }

        let ctx = NeuralEngineContext.shared
        let cfg = ctx.makeConfiguration(useANE: options.computeUnit != .cpuOnly)

        do {
            let enc = try MLModel(contentsOf: encURL, configuration: cfg)
            let prm = try MLModel(contentsOf: prmURL, configuration: cfg)
            let dec = try MLModel(contentsOf: decURL, configuration: cfg)

            self.imageEncoder = enc
            self.promptEncoder = prm
            self.maskDecoder = dec
            self.cachedModelDir = dir

            return ModelBundle(imageEncoder: enc, promptEncoder: prm, maskDecoder: dec)
        } catch {
            throw MobileSAMDeviceError.modelLoadFailed
        }
    }

    private func resolveModelDirectory() -> String? {
        if let p = options.modelDirectory, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return p
        }

        if let env = ProcessInfo.processInfo.environment["METAVIS_MOBILESAM_MODEL_DIR"], !env.isEmpty {
            return env
        }

        // Repo defaults:
        // 1) Prefer precompiled models.
        let cwd = FileManager.default.currentDirectoryPath
        let compiled = URL(fileURLWithPath: cwd).appendingPathComponent("assets/models/mobilesam/compiled").path
        if FileManager.default.fileExists(atPath: compiled) {
            return compiled
        }

        // 2) Fall back to downloaded .mlpackage bundles.
        let coreml = URL(fileURLWithPath: cwd).appendingPathComponent("assets/models/mobilesam/coreml").path
        if FileManager.default.fileExists(atPath: coreml) {
            return coreml
        }

        return nil
    }

    // MARK: - IO heuristics

    private func firstImageInputName(of model: MLModel) -> String {
        // Prefer image input.
        if let hit = model.modelDescription.inputDescriptionsByName.first(where: { $0.value.type == .image }) {
            return hit.key
        }
        // Fall back to first input.
        return model.modelDescription.inputDescriptionsByName.keys.sorted().first ?? "image"
    }

    private func firstMultiArrayOutputName(of model: MLModel) -> String {
        if let hit = model.modelDescription.outputDescriptionsByName.first(where: { $0.value.type == .multiArray }) {
            return hit.key
        }
        return model.modelDescription.outputDescriptionsByName.keys.sorted().first ?? "output"
    }

    private func firstTwoMultiArrayInputNames(of model: MLModel) -> (String, String) {
        let names = model.modelDescription.inputDescriptionsByName
            .filter { $0.value.type == .multiArray }
            .map { $0.key }
            .sorted()
        if names.count >= 2 {
            return (names[0], names[1])
        }

        // Extremely defensive fallback.
        let all = model.modelDescription.inputDescriptionsByName.keys.sorted()
        let a = all.first ?? "input0"
        let b = all.dropFirst().first ?? "input1"
        return (a, b)
    }

    // MARK: - Pre/Post

    private func resizeToSquareBGRA(pixelBuffer: CVPixelBuffer, size: Int) throws -> CVPixelBuffer {
        let src = CIImage(cvPixelBuffer: pixelBuffer)

        // Scale to fit within square then letterbox.
        let w = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let h = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        guard w > 0.5, h > 0.5 else { throw MobileSAMDeviceError.preprocessingFailed }

        let target = CGFloat(size)
        let scale = min(target / w, target / h)
        let scaled = src.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let x = (target - scaled.extent.width) * 0.5
        let y = (target - scaled.extent.height) * 0.5
        let placed = scaled.transformed(by: CGAffineTransform(translationX: x, y: y))

        let canvas = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: target, height: target))
        let composed = placed.composited(over: canvas)

        var out: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: size,
            kCVPixelBufferHeightKey as String: size,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, size, size, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out)
        guard status == kCVReturnSuccess, let pb = out else { throw MobileSAMDeviceError.preprocessingFailed }

        ciContext.render(composed, to: pb)
        return pb
    }

    private func makePointsMultiArray(pointTopLeft: CGPoint, label: Int, size: Int) throws -> MLMultiArray {
        // Best-effort canonical SAM point encoding: shape [1, 1, 2] float32.
        // Coordinates are in model input pixel space (top-left origin).
        let pts = try MLMultiArray(shape: [1, 1, 2], dataType: .float32)
        let x = Float(max(0.0, min(1.0, pointTopLeft.x))) * Float(size)
        let y = Float(max(0.0, min(1.0, pointTopLeft.y))) * Float(size)
        pts[[0, 0, 0]] = NSNumber(value: x)
        pts[[0, 0, 1]] = NSNumber(value: y)
        _ = label // reserved; labels are separate.
        return pts
    }

    private func makeLabelsMultiArray(label: Int) throws -> MLMultiArray {
        // Best-effort canonical SAM labels: shape [1, 1] float32.
        let arr = try MLMultiArray(shape: [1, 1], dataType: .float32)
        arr[[0, 0]] = NSNumber(value: Float(label))
        return arr
    }

    private func maskMultiArrayToOneComponent8(_ arr: MLMultiArray, threshold: Float) throws -> CVPixelBuffer {
        // Heuristic: interpret the last 2 dimensions as HxW.
        let shape = arr.shape.map { $0.intValue }
        guard shape.count >= 2 else { throw MobileSAMDeviceError.outputUnsupported }

        let h = shape[shape.count - 2]
        let w = shape[shape.count - 1]
        guard w > 0, h > 0 else { throw MobileSAMDeviceError.outputUnsupported }

        var out: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_OneComponent8),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_OneComponent8, attrs as CFDictionary, &out)
        guard status == kCVReturnSuccess, let pb = out else { throw MobileSAMDeviceError.outputUnsupported }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { throw MobileSAMDeviceError.outputUnsupported }
        let bpr = CVPixelBufferGetBytesPerRow(pb)

        // Flatten access; we only support float32/float16/double/int32-ish by reading as Double.
        let total = arr.count
        if total < w * h {
            throw MobileSAMDeviceError.outputUnsupported
        }

        for y in 0..<h {
            let row = base.advanced(by: y * bpr).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w {
                let idx = y * w + x
                let v = arr[idx].doubleValue
                row[x] = (Float(v) > threshold) ? 255 : 0
            }
        }

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
