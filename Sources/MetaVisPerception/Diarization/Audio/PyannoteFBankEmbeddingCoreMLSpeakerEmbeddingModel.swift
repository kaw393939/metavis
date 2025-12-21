import Foundation
import CoreML
import MetaVisCore

/// Speaker embedding model for the FluidInference `speaker-diarization-coreml` "pyannote community-1" assets.
///
/// Pipeline:
/// - `FBank.mlmodelc`: raw audio (16 kHz) -> fbank features
/// - `Embedding.mlmodelc`: (fbank features, weights) -> embedding vector
public struct PyannoteFBankEmbeddingCoreMLSpeakerEmbeddingModel: SpeakerEmbeddingModel {

    public enum ModelError: Error, Sendable, Equatable {
        case modelNotFound(String)
        case cannotAutoDetectInput
        case cannotAutoDetectOutput
        case missingFeature(String)
        case invalidOutputType
        case invalidWindowSize(expectedSamples: Int, got: Int)
    }

    public let name: String
    public let windowSeconds: Double
    public let sampleRate: Double
    public let embeddingDimension: Int

    private let fbankModel: MLModel
    private let embeddingModel: MLModel

    private let fbankInputName: String
    private let fbankOutputName: String

    private let embeddingInputFBankName: String
    private let embeddingInputWeightsName: String
    private let embeddingOutputName: String

    private let expectedSamples: Int
    private let weightsFrames: Int
    private let focusFrames: Int

    /// - Parameters:
    ///   - focusSeconds: Controls how much of the 10s window contributes to the embedding. Smaller values
    ///     reduce multi-speaker mixing for diarization. Default focuses on the central 2 seconds.
    public init(
        fbankModelURL: URL,
        embeddingModelURL: URL,
        sampleRate: Double = 16_000,
        focusSeconds: Double = 2.0,
        computeUnit: AIComputeUnit = .all
    ) throws {
        self.name = "pyannote-community-1"
        self.sampleRate = sampleRate

        guard FileManager.default.fileExists(atPath: fbankModelURL.path) else {
            throw ModelError.modelNotFound(fbankModelURL.path)
        }
        guard FileManager.default.fileExists(atPath: embeddingModelURL.path) else {
            throw ModelError.modelNotFound(embeddingModelURL.path)
        }

        let ctx = NeuralEngineContext.shared
        let cfg = ctx.makeConfiguration(useANE: computeUnit != .cpuOnly)

        self.fbankModel = try MLModel(contentsOf: fbankModelURL, configuration: cfg)
        self.embeddingModel = try MLModel(contentsOf: embeddingModelURL, configuration: cfg)

        // FBank model IO names: prefer known names, fall back to first multiarray IO.
        let fDesc = fbankModel.modelDescription
        if fDesc.inputDescriptionsByName.keys.contains("audio") {
            self.fbankInputName = "audio"
        } else if let inferred = fDesc.inputDescriptionsByName.first(where: { $0.value.type == .multiArray })?.key {
            self.fbankInputName = inferred
        } else {
            throw ModelError.cannotAutoDetectInput
        }

        if fDesc.outputDescriptionsByName.keys.contains("fbank_features") {
            self.fbankOutputName = "fbank_features"
        } else if let inferred = fDesc.outputDescriptionsByName.first(where: { $0.value.type == .multiArray })?.key {
            self.fbankOutputName = inferred
        } else {
            throw ModelError.cannotAutoDetectOutput
        }

        // Infer expected sample count from fixed input shape, e.g. [B, 1, 160000]
        if let inDesc = fDesc.inputDescriptionsByName[self.fbankInputName],
           let constraint = inDesc.multiArrayConstraint {
            let shape = constraint.shape.map { $0.intValue }
            self.expectedSamples = shape.last ?? Int(sampleRate * 10.0)
        } else {
            self.expectedSamples = Int(sampleRate * 10.0)
        }
        self.windowSeconds = Double(expectedSamples) / sampleRate

        // Embedding model IO names.
        let eDesc = embeddingModel.modelDescription

        let inferredEmbeddingFBankName: String
        if eDesc.inputDescriptionsByName.keys.contains("fbank_features") {
            inferredEmbeddingFBankName = "fbank_features"
        } else if let inferred = eDesc.inputDescriptionsByName.first(where: { $0.value.type == .multiArray })?.key {
            inferredEmbeddingFBankName = inferred
        } else {
            throw ModelError.cannotAutoDetectInput
        }
        self.embeddingInputFBankName = inferredEmbeddingFBankName

        if eDesc.inputDescriptionsByName.keys.contains("weights") {
            self.embeddingInputWeightsName = "weights"
        } else {
            // Fall back: find the other multiarray input.
            let keys = eDesc.inputDescriptionsByName.filter { $0.value.type == .multiArray }.map { $0.key }
            if keys.count >= 2 {
                self.embeddingInputWeightsName = keys.first(where: { $0 != inferredEmbeddingFBankName }) ?? keys[1]
            } else {
                throw ModelError.cannotAutoDetectInput
            }
        }

        if eDesc.outputDescriptionsByName.keys.contains("embedding") {
            self.embeddingOutputName = "embedding"
        } else if let inferred = eDesc.outputDescriptionsByName.first(where: { $0.value.type == .multiArray })?.key {
            self.embeddingOutputName = inferred
        } else {
            throw ModelError.cannotAutoDetectOutput
        }

        if let wDesc = eDesc.inputDescriptionsByName[self.embeddingInputWeightsName],
           let wConstraint = wDesc.multiArrayConstraint {
            // Expected shape [B, 589]
            self.weightsFrames = wConstraint.shape.last?.intValue ?? 589
        } else {
            self.weightsFrames = 589
        }

        // Choose a center-focused weighting window to reduce mixing.
        let framesPerSecond = Double(weightsFrames) / max(1e-6, windowSeconds)
        self.focusFrames = max(1, min(weightsFrames, Int((focusSeconds * framesPerSecond).rounded(.toNearestOrAwayFromZero))))

        // Infer embedding dimension if available.
        if let outDesc = eDesc.outputDescriptionsByName[self.embeddingOutputName],
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
    }

    public func embed(windowedMonoPCM: [Float]) throws -> [Float] {
        guard windowedMonoPCM.count == expectedSamples else {
            throw ModelError.invalidWindowSize(expectedSamples: expectedSamples, got: windowedMonoPCM.count)
        }

        // 1) PCM -> FBanks
        let audio = try MLMultiArray(shape: [1, 1, NSNumber(value: expectedSamples)], dataType: .float32)
        for i in 0..<expectedSamples {
            audio[i] = NSNumber(value: windowedMonoPCM[i])
        }

        let fIn = try MLDictionaryFeatureProvider(dictionary: [fbankInputName: audio])
        let fOut = try fbankModel.prediction(from: fIn)

        guard fOut.featureNames.contains(fbankOutputName) else {
            throw ModelError.missingFeature(fbankOutputName)
        }
        guard let fbankArr = fOut.featureValue(for: fbankOutputName)?.multiArrayValue else {
            throw ModelError.invalidOutputType
        }

        // 2) Create weights [1, weightsFrames] focusing on center.
        let weights = try MLMultiArray(shape: [1, NSNumber(value: weightsFrames)], dataType: .float32)
        for i in 0..<weightsFrames { weights[i] = 0 }

        let center = weightsFrames / 2
        let half = max(0, focusFrames / 2)
        let start = max(0, center - half)
        let end = min(weightsFrames, center + half)
        if end > start {
            for i in start..<end {
                // Simple triangular window over the focus region.
                let t = Float(i - start) / Float(max(1, end - start - 1))
                let w = 1.0 - abs(2.0 * t - 1.0)
                weights[i] = NSNumber(value: w)
            }
        } else {
            weights[center] = 1
        }

        // 3) FBanks + weights -> embedding
        let eIn = try MLDictionaryFeatureProvider(dictionary: [
            embeddingInputFBankName: fbankArr,
            embeddingInputWeightsName: weights,
        ])
        let eOut = try embeddingModel.prediction(from: eIn)

        guard eOut.featureNames.contains(embeddingOutputName) else {
            throw ModelError.missingFeature(embeddingOutputName)
        }
        guard let embArr = eOut.featureValue(for: embeddingOutputName)?.multiArrayValue else {
            throw ModelError.invalidOutputType
        }

        var vec: [Float] = []
        vec.reserveCapacity(embArr.count)
        for i in 0..<embArr.count {
            vec.append(embArr[i].floatValue)
        }
        return SpeakerEmbeddingMath.l2Normalize(vec)
    }
}
