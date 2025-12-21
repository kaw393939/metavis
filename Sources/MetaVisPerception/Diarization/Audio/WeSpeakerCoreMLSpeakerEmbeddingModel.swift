import Foundation
import CoreML
import MetaVisCore

/// Speaker embedding model using the (FBank -> WeSpeaker) CoreML pipeline.
///
/// This matches the structure used by the FluidInference speaker-diarization-coreml assets,
/// where the embedding network expects filterbank features, not raw PCM.
public struct WeSpeakerCoreMLSpeakerEmbeddingModel: SpeakerEmbeddingModel {

    public enum ModelError: Error, Sendable, Equatable {
        case modelNotFound(String)
        case cannotAutoDetectInput
        case cannotAutoDetectOutput
        case missingFeature(String)
        case invalidOutputType
        case invalidWindowSize(expectedSamples: Int, got: Int)
        case shapeMismatch(expectedCount: Int, got: Int)
    }

    public let name: String
    public let windowSeconds: Double
    public let sampleRate: Double
    public let embeddingDimension: Int

    private let fbankModel: MLModel
    private let wespeakerModel: MLModel

    private let fbankInputName: String
    private let fbankOutputName: String

    private let wespeakerInputName: String
    private let wespeakerOutputName: String

    private let expectedSamplesOverride: Int?

    public init(
        fbankModelURL: URL,
        wespeakerModelURL: URL,
        windowSeconds: Double = 3.0,
        sampleRate: Double = 16_000,
        computeUnit: AIComputeUnit = .all
    ) throws {
        self.name = "wespeaker"
        self.sampleRate = sampleRate

        guard FileManager.default.fileExists(atPath: fbankModelURL.path) else {
            throw ModelError.modelNotFound(fbankModelURL.path)
        }
        guard FileManager.default.fileExists(atPath: wespeakerModelURL.path) else {
            throw ModelError.modelNotFound(wespeakerModelURL.path)
        }

        let ctx = NeuralEngineContext.shared
        let cfg = ctx.makeConfiguration(useANE: computeUnit != .cpuOnly)

        self.fbankModel = try MLModel(contentsOf: fbankModelURL, configuration: cfg)
        self.wespeakerModel = try MLModel(contentsOf: wespeakerModelURL, configuration: cfg)

        let fDesc = fbankModel.modelDescription
        if let inferred = fDesc.inputDescriptionsByName.first(where: { $0.value.type == .multiArray })?.key {
            self.fbankInputName = inferred
        } else {
            throw ModelError.cannotAutoDetectInput
        }
        if let inferred = fDesc.outputDescriptionsByName.first(where: { $0.value.type == .multiArray })?.key {
            self.fbankOutputName = inferred
        } else {
            throw ModelError.cannotAutoDetectOutput
        }

        let wDesc = wespeakerModel.modelDescription
        if let inferred = wDesc.inputDescriptionsByName.first(where: { $0.value.type == .multiArray })?.key {
            self.wespeakerInputName = inferred
        } else {
            throw ModelError.cannotAutoDetectInput
        }
        if let inferred = wDesc.outputDescriptionsByName.first(where: { $0.value.type == .multiArray })?.key {
            self.wespeakerOutputName = inferred
        } else {
            throw ModelError.cannotAutoDetectOutput
        }

        // Infer embedding dimension from fixed output shape when possible.
        if let outDesc = wDesc.outputDescriptionsByName[self.wespeakerOutputName],
           let constraint = outDesc.multiArrayConstraint {
            let shape = constraint.shape.map { $0.intValue }
            if shape.allSatisfy({ $0 > 0 }) {
                self.embeddingDimension = shape.reduce(1, *)
            } else {
                self.embeddingDimension = 0
            }
        } else {
            self.embeddingDimension = 0
        }

        // Infer expected sample count from fixed FBank input shape if possible.
        var inferredExpectedSamples: Int? = nil
        if let inDesc = fDesc.inputDescriptionsByName[self.fbankInputName],
           let constraint = inDesc.multiArrayConstraint {
            let shape = constraint.shape.map { $0.intValue }
            if shape.count >= 1, shape.allSatisfy({ $0 > 0 }) {
                inferredExpectedSamples = shape.last
            }
        }
        self.expectedSamplesOverride = inferredExpectedSamples

        if let inferredExpectedSamples {
            self.windowSeconds = Double(inferredExpectedSamples) / sampleRate
        } else {
            self.windowSeconds = windowSeconds
        }
    }

    public func embed(windowedMonoPCM: [Float]) throws -> [Float] {
        let expected = expectedSamplesOverride ?? Int((windowSeconds * sampleRate).rounded(.toNearestOrAwayFromZero))
        guard windowedMonoPCM.count == expected else {
            throw ModelError.invalidWindowSize(expectedSamples: expected, got: windowedMonoPCM.count)
        }

        // 1) PCM -> FBank features
        let pcm = try MLMultiArray(shape: [1, NSNumber(value: expected)], dataType: .float32)
        for i in 0..<expected { pcm[i] = NSNumber(value: windowedMonoPCM[i]) }

        let fIn = try MLDictionaryFeatureProvider(dictionary: [fbankInputName: pcm])
        let fOut = try fbankModel.prediction(from: fIn)

        guard fOut.featureNames.contains(fbankOutputName) else {
            throw ModelError.missingFeature(fbankOutputName)
        }
        guard let fbankArr = fOut.featureValue(for: fbankOutputName)?.multiArrayValue else {
            throw ModelError.invalidOutputType
        }

        // 2) FBank -> WeSpeaker embedding
        // We may need to reshape to match the WeSpeaker input shape, but element counts should match.
        let wDesc = wespeakerModel.modelDescription
        let wInputDesc = wDesc.inputDescriptionsByName[wespeakerInputName]
        let desiredShape: [NSNumber]? = wInputDesc?.multiArrayConstraint?.shape

        let wInputArray: MLMultiArray
        if let desiredShape {
            let desiredCount = desiredShape.map { $0.intValue }.reduce(1, *)
            guard desiredCount == fbankArr.count else {
                throw ModelError.shapeMismatch(expectedCount: desiredCount, got: fbankArr.count)
            }
            let reshaped = try MLMultiArray(shape: desiredShape, dataType: fbankArr.dataType)
            for i in 0..<fbankArr.count {
                reshaped[i] = fbankArr[i]
            }
            wInputArray = reshaped
        } else {
            wInputArray = fbankArr
        }

        let wIn = try MLDictionaryFeatureProvider(dictionary: [wespeakerInputName: wInputArray])
        let wOut = try wespeakerModel.prediction(from: wIn)

        guard wOut.featureNames.contains(wespeakerOutputName) else {
            throw ModelError.missingFeature(wespeakerOutputName)
        }
        guard let embArr = wOut.featureValue(for: wespeakerOutputName)?.multiArrayValue else {
            throw ModelError.invalidOutputType
        }

        if embeddingDimension > 0, embArr.count != embeddingDimension {
            throw ModelError.shapeMismatch(expectedCount: embeddingDimension, got: embArr.count)
        }

        var vec: [Float] = []
        vec.reserveCapacity(embArr.count)
        for i in 0..<embArr.count {
            vec.append(embArr[i].floatValue)
        }
        return SpeakerEmbeddingMath.l2Normalize(vec)
    }
}
