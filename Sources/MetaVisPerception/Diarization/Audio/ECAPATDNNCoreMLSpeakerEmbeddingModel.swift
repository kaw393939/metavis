import Foundation
import CoreML
import MetaVisCore

public struct ECAPATDNNCoreMLSpeakerEmbeddingModel: SpeakerEmbeddingModel {

    public enum ModelError: Error, Sendable, Equatable {
        case modelNotFound(String)
        case invalidWindowSize(expectedSamples: Int, got: Int)
        case invalidOutputType
        case missingFeature(String)
        case multiArrayShapeMismatch
        case cannotAutoDetectInput
        case cannotAutoDetectOutput
    }

    public let name: String
    public let windowSeconds: Double
    public let sampleRate: Double
    public let embeddingDimension: Int

    private let model: MLModel
    private let inputName: String
    private let outputName: String
    private let expectedSamplesOverride: Int?

    public init(
        modelURL: URL,
        inputName: String,
        outputName: String,
        windowSeconds: Double = 3.0,
        sampleRate: Double = 16_000,
        embeddingDimension: Int,
        computeUnit: AIComputeUnit = .all
    ) throws {
        self.name = "ecapa-tdnn"
        self.windowSeconds = windowSeconds
        self.sampleRate = sampleRate
        self.embeddingDimension = embeddingDimension
        self.inputName = inputName
        self.outputName = outputName
        self.expectedSamplesOverride = nil

        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw ModelError.modelNotFound(modelURL.path)
        }

        let ctx = NeuralEngineContext.shared
        let cfg = ctx.makeConfiguration(useANE: computeUnit != .cpuOnly)
        self.model = try MLModel(contentsOf: modelURL, configuration: cfg)
    }

    /// Convenience initializer that auto-detects CoreML input/output names and embedding dimension.
    ///
    /// - If `inputName` / `outputName` are nil or empty, the first multiarray input/output is used.
    /// - If `embeddingDimension` is nil, it is inferred from the output multiarray element count.
    /// - If the input multiarray shape is fixed (e.g. [1, 48000]), the expected sample count is inferred
    ///   and used to validate input windows (and `windowSeconds` is recomputed from `sampleRate`).
    public init(
        modelURL: URL,
        inputName: String? = nil,
        outputName: String? = nil,
        windowSeconds: Double = 3.0,
        sampleRate: Double = 16_000,
        embeddingDimension: Int? = nil,
        computeUnit: AIComputeUnit = .all
    ) throws {
        self.name = "ecapa-tdnn"
        self.sampleRate = sampleRate

        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw ModelError.modelNotFound(modelURL.path)
        }

        let ctx = NeuralEngineContext.shared
        let cfg = ctx.makeConfiguration(useANE: computeUnit != .cpuOnly)
        let loaded = try MLModel(contentsOf: modelURL, configuration: cfg)
        self.model = loaded

        let desc = loaded.modelDescription

        // Auto-detect input name.
        if let inputName, !inputName.isEmpty {
            self.inputName = inputName
        } else if let inferred = desc.inputDescriptionsByName.first(where: { $0.value.type == .multiArray })?.key {
            self.inputName = inferred
        } else {
            throw ModelError.cannotAutoDetectInput
        }

        // Auto-detect output name.
        if let outputName, !outputName.isEmpty {
            self.outputName = outputName
        } else if let inferred = desc.outputDescriptionsByName.first(where: { $0.value.type == .multiArray })?.key {
            self.outputName = inferred
        } else {
            throw ModelError.cannotAutoDetectOutput
        }

        // Infer expected sample count from fixed input shape if possible.
        var inferredExpectedSamples: Int? = nil
        if let inDesc = desc.inputDescriptionsByName[self.inputName],
           let constraint = inDesc.multiArrayConstraint {
            let shape = constraint.shape.map { $0.intValue }
            if shape.count >= 1, shape.allSatisfy({ $0 > 0 }) {
                // Common shapes: [1, N] or [N]
                if shape.count == 1 {
                    inferredExpectedSamples = shape[0]
                } else {
                    inferredExpectedSamples = shape.last
                }
            }
        }
        self.expectedSamplesOverride = inferredExpectedSamples

        if let inferredExpectedSamples {
            self.windowSeconds = Double(inferredExpectedSamples) / sampleRate
        } else {
            self.windowSeconds = windowSeconds
        }

        // Infer embedding dimension if needed.
        if let embeddingDimension, embeddingDimension > 0 {
            self.embeddingDimension = embeddingDimension
        } else {
            guard desc.outputDescriptionsByName.keys.contains(self.outputName) else {
                throw ModelError.missingFeature(self.outputName)
            }
            // Run a tiny shape probe by reading constraints when available; fall back to runtime inference during first embed.
            if let outDesc = desc.outputDescriptionsByName[self.outputName],
               let constraint = outDesc.multiArrayConstraint {
                let shape = constraint.shape.map { $0.intValue }
                if shape.allSatisfy({ $0 > 0 }) {
                    let dim = shape.reduce(1, *)
                    self.embeddingDimension = dim
                } else {
                    // Unknown/flexible shape: defer; we'll validate at runtime from output count.
                    self.embeddingDimension = 0
                }
            } else {
                self.embeddingDimension = 0
            }
        }
    }

    public func embed(windowedMonoPCM: [Float]) throws -> [Float] {
        let expected = expectedSamplesOverride ?? Int((windowSeconds * sampleRate).rounded(.toNearestOrAwayFromZero))
        guard windowedMonoPCM.count == expected else {
            throw ModelError.invalidWindowSize(expectedSamples: expected, got: windowedMonoPCM.count)
        }

        // Create MLMultiArray [1, N]
        let n = expected
        let arr = try MLMultiArray(shape: [1, NSNumber(value: n)], dataType: .float32)
        for i in 0..<n {
            arr[i] = NSNumber(value: windowedMonoPCM[i])
        }

        let inProvider = try MLDictionaryFeatureProvider(dictionary: [inputName: arr])
        let out = try model.prediction(from: inProvider)

        guard out.featureNames.contains(outputName) else {
            throw ModelError.missingFeature(outputName)
        }

        guard let outArr = out.featureValue(for: outputName)?.multiArrayValue else {
            throw ModelError.invalidOutputType
        }

        // Flatten.
        let count = outArr.count
        if embeddingDimension > 0 {
            guard count == embeddingDimension else {
                throw ModelError.multiArrayShapeMismatch
            }
        }

        var vec: [Float] = []
        vec.reserveCapacity(count)
        for i in 0..<count {
            vec.append(outArr[i].floatValue)
        }

        return SpeakerEmbeddingMath.l2Normalize(vec)
    }
}
