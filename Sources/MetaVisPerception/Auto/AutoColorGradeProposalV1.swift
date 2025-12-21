import Foundation
import MetaVisCore

public enum AutoColorGradeProposalV1 {

    public static let policyVersion = "color_grade_proposal_v1"

    public enum TargetingPolicy: String, Codable, Sendable, Equatable {
        case firstClip
        case allClips
        case selectedClips
    }

    public struct Target: Codable, Sendable, Equatable {
        public var firstClip: Bool

        public init(firstClip: Bool = true) {
            self.firstClip = firstClip
        }
    }

    public struct GradeOp: Codable, Sendable, Equatable {
        public var effectId: String
        public var params: [String: Double]

        public init(effectId: String, params: [String: Double]) {
            self.effectId = effectId
            self.params = params
        }
    }

    public struct ColorMetricsSnapshot: Codable, Sendable, Equatable {
        public var meanLuma: Double
        public var minLuma: Double
        public var maxLuma: Double

        public init(meanLuma: Double, minLuma: Double, maxLuma: Double) {
            self.meanLuma = meanLuma
            self.minLuma = minLuma
            self.maxLuma = maxLuma
        }
    }

    public struct GradeProposal: Codable, Sendable, Equatable {
        public var schemaVersion: Int
        public var proposalId: String
        public var seed: String

        public var targetingPolicy: TargetingPolicy
        public var target: Target

        public var grade: GradeOp
        public var confidence: Double
        public var flags: [String]
        public var whitelist: ParameterWhitelist
        public var metricsSnapshot: ColorMetricsSnapshot?
        public var reasoning: [String]

        public init(
            schemaVersion: Int = 1,
            proposalId: String,
            seed: String,
            targetingPolicy: TargetingPolicy,
            target: Target,
            grade: GradeOp,
            confidence: Double,
            flags: [String],
            whitelist: ParameterWhitelist,
            metricsSnapshot: ColorMetricsSnapshot?,
            reasoning: [String]
        ) {
            self.schemaVersion = schemaVersion
            self.proposalId = proposalId
            self.seed = seed
            self.targetingPolicy = targetingPolicy
            self.target = target
            self.grade = grade
            self.confidence = confidence
            self.flags = flags
            self.whitelist = whitelist
            self.metricsSnapshot = metricsSnapshot
            self.reasoning = reasoning
        }
    }

    public struct Options: Sendable, Equatable {
        public var seed: String

        public init(seed: String = "default") {
            self.seed = seed
        }
    }

    public static func propose(from sensors: MasterSensors, options: Options = Options()) -> GradeProposal {
        let seed = options.seed

        let color = AutoColorCorrector.propose(from: sensors)
        let params = color.asGradeSimpleParameters()

        let descriptors = sensors.descriptors ?? []
        let avoidHeavy = descriptors.contains(where: { ($0.label == .avoidHeavyGrade || $0.label == .gradeConfidenceLow) && ($0.veto ?? false) })

        var flags: [String] = []
        if avoidHeavy { flags.append("avoidHeavyGrade") }

        var reasoning: [String] = []
        if !sensors.videoSamples.isEmpty {
            let mean = sensors.videoSamples.reduce(0.0) { $0 + $1.meanLuma } / Double(sensors.videoSamples.count)
            reasoning.append(String(format: "meanLuma≈%.3f → exposure=%.3f", mean, color.exposure))
        } else {
            reasoning.append("no videoSamples → conservative identity-ish grade")
        }
        reasoning.append(String(format: "contrast=%.3f saturation=%.3f temperature=%.3f tint=%.3f", color.contrast, color.saturation, color.temperature, color.tint))
        if avoidHeavy {
            reasoning.append("descriptor veto present → conservative clamp")
        }

        // Whitelist: conservative bounds + per-cycle deltas.
        var whitelist = ParameterWhitelist()
        whitelist.numeric["grade.params.exposure"] = .init(min: -0.5, max: 0.5, maxDeltaPerCycle: 0.10)
        whitelist.numeric["grade.params.contrast"] = .init(min: 0.9, max: 1.25, maxDeltaPerCycle: 0.05)
        whitelist.numeric["grade.params.saturation"] = .init(min: 0.85, max: 1.25, maxDeltaPerCycle: 0.05)
        whitelist.numeric["grade.params.temperature"] = .init(min: -1.0, max: 1.0, maxDeltaPerCycle: 0.20)
        whitelist.numeric["grade.params.tint"] = .init(min: -0.35, max: 0.35, maxDeltaPerCycle: 0.10)

        let stats: ColorMetricsSnapshot? = {
            guard !sensors.videoSamples.isEmpty else { return nil }
            let lumas = sensors.videoSamples.map { $0.meanLuma }
            let mean = lumas.reduce(0.0, +) / Double(lumas.count)
            let minV = lumas.min() ?? mean
            let maxV = lumas.max() ?? mean
            return ColorMetricsSnapshot(meanLuma: mean, minLuma: minV, maxLuma: maxV)
        }()

        let confidence: Double = avoidHeavy ? 0.60 : 0.80

        let gradeOp = GradeOp(effectId: "com.metavis.fx.grade.simple", params: params)

        let proposalId = computeProposalId(
            sensors: sensors,
            seed: seed,
            policyVersion: policyVersion,
            grade: gradeOp,
            flags: flags
        )

        return GradeProposal(
            proposalId: proposalId,
            seed: seed,
            targetingPolicy: .firstClip,
            target: .init(firstClip: true),
            grade: gradeOp,
            confidence: confidence,
            flags: flags,
            whitelist: whitelist,
            metricsSnapshot: stats,
            reasoning: reasoning
        )
    }

    private struct HashInputs: Codable {
        var policyVersion: String
        var seed: String
        var analyzedSeconds: Double
        var meanLuma: Double
        var minLuma: Double
        var maxLuma: Double
        var descriptorLabels: [String]
        var grade: GradeOp
        var flags: [String]
    }

    public static func computeProposalId(
        sensors: MasterSensors,
        seed: String,
        policyVersion: String,
        grade: GradeOp,
        flags: [String]
    ) -> String {
        let lumas = sensors.videoSamples.map { $0.meanLuma }
        let mean = lumas.isEmpty ? 0.0 : (lumas.reduce(0.0, +) / Double(lumas.count))
        let minV = lumas.min() ?? mean
        let maxV = lumas.max() ?? mean

        let labels = (sensors.descriptors ?? [])
            .map { $0.label.rawValue }
            .sorted()

        let inputs = HashInputs(
            policyVersion: policyVersion,
            seed: seed,
            analyzedSeconds: sensors.summary.analyzedSeconds,
            meanLuma: mean,
            minLuma: minV,
            maxLuma: maxV,
            descriptorLabels: labels,
            grade: grade,
            flags: flags.sorted()
        )

        let data = (try? JSONWriting.encode(inputs)) ?? Data()
        return StableHash.sha256Hex(data)
    }
}
