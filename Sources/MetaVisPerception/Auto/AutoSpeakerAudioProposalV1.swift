import Foundation
import MetaVisCore

public enum AutoSpeakerAudioProposalV1 {

    public static let policyVersion = "audio_proposal_v1"

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

    public struct ChainOp: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable, Equatable {
            case effect
            case command
        }

        public var kind: Kind
        public var effectId: String?
        public var commandId: String?
        public var params: [String: Double]?
        public var args: [String: String]?

        public init(effectId: String, params: [String: Double]) {
            self.kind = .effect
            self.effectId = effectId
            self.commandId = nil
            self.params = params
            self.args = nil
        }

        public init(commandId: String, args: [String: String]) {
            self.kind = .command
            self.effectId = nil
            self.commandId = commandId
            self.params = nil
            self.args = args
        }
    }

    public struct MetricsSnapshot: Codable, Sendable, Equatable {
        public var approxPeakDB: Double
        public var approxRMSdBFS: Double

        public init(approxPeakDB: Double, approxRMSdBFS: Double) {
            self.approxPeakDB = approxPeakDB
            self.approxRMSdBFS = approxRMSdBFS
        }
    }

    public struct AudioProposal: Codable, Sendable, Equatable {
        public var schemaVersion: Int
        public var proposalId: String
        public var seed: String

        public var targetingPolicy: TargetingPolicy
        public var target: Target

        public var chain: [ChainOp]
        public var confidence: Double
        public var flags: [String]
        public var whitelist: ParameterWhitelist
        public var metricsSnapshot: MetricsSnapshot?
        public var reasoning: [String]

        public init(
            schemaVersion: Int = 1,
            proposalId: String,
            seed: String,
            targetingPolicy: TargetingPolicy,
            target: Target,
            chain: [ChainOp],
            confidence: Double,
            flags: [String],
            whitelist: ParameterWhitelist,
            metricsSnapshot: MetricsSnapshot?,
            reasoning: [String]
        ) {
            self.schemaVersion = schemaVersion
            self.proposalId = proposalId
            self.seed = seed
            self.targetingPolicy = targetingPolicy
            self.target = target
            self.chain = chain
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

    public static func propose(from sensors: MasterSensors, options: Options = Options()) -> AudioProposal {
        let seed = options.seed

        let raw = AutoSpeakerAudioEnhancer.propose(from: sensors)

        let allReasons = sensors.warnings.flatMap { $0.governedReasonCodes }
        let hasNoiseRisk = allReasons.contains(.audio_noise_risk)
        let hasClipRisk = allReasons.contains(.audio_clip_risk)

        let silenceSeconds = sensors.audioSegments
            .filter { $0.kind == .silence }
            .map { max(0.0, $0.end - $0.start) }
            .reduce(0.0, +)
        let analyzed = max(0.0001, sensors.summary.analyzedSeconds)
        let silenceFrac = silenceSeconds / analyzed
        let silenceHeavy = silenceFrac > 0.25

        var flags: [String] = []
        if hasNoiseRisk { flags.append("noiseRisk") }
        if hasClipRisk { flags.append("clipRisk") }
        if silenceHeavy { flags.append("silenceHeavy") }

        var chain: [ChainOp] = []
        var reasoning: [String] = []

        if raw.enableDialogCleanwaterV1 {
            let gainDB = raw.dialogCleanwaterGlobalGainDB
            chain.append(.init(effectId: "audio.dialogCleanwater.v1", params: ["globalGainDB": gainDB]))
            reasoning.append("noise risk present → enable audio.dialogCleanwater.v1")
            if hasClipRisk {
                reasoning.append("clip risk present → prefer safety (lower gain)")
            }
        } else {
            reasoning.append("no noise risk → identity")
        }

        // Whitelist: conservative bounds, with per-cycle max delta.
        var whitelist = ParameterWhitelist()
        // v1 chain has at most one effect with globalGainDB.
        whitelist.numeric["chain[0].params.globalGainDB"] = .init(min: -6.0, max: 6.0, maxDeltaPerCycle: 2.0)

        let metrics = MetricsSnapshot(
            approxPeakDB: Double(sensors.summary.audio.approxPeakDB),
            approxRMSdBFS: Double(sensors.summary.audio.approxRMSdBFS)
        )

        // Confidence: conservative.
        let confidence: Double
        if raw.enableDialogCleanwaterV1 {
            confidence = hasClipRisk ? 0.55 : 0.65
        } else {
            confidence = 0.9
        }

        let proposalId = computeProposalId(
            sensors: sensors,
            seed: seed,
            policyVersion: policyVersion,
            chain: chain,
            flags: flags
        )

        return AudioProposal(
            proposalId: proposalId,
            seed: seed,
            targetingPolicy: .firstClip,
            target: .init(firstClip: true),
            chain: chain,
            confidence: confidence,
            flags: flags,
            whitelist: whitelist,
            metricsSnapshot: metrics,
            reasoning: reasoning
        )
    }

    private struct HashInputs: Codable {
        var policyVersion: String
        var seed: String
        var analyzedSeconds: Double
        var approxPeakDB: Double
        var approxRMSdBFS: Double
        var warningReasons: [String]
        var chain: [ChainOp]
        var flags: [String]
    }

    public static func computeProposalId(
        sensors: MasterSensors,
        seed: String,
        policyVersion: String,
        chain: [ChainOp],
        flags: [String]
    ) -> String {
        let reasons = sensors.warnings
            .flatMap { $0.governedReasonCodes.map { $0.rawValue } }
            .sorted()

        let inputs = HashInputs(
            policyVersion: policyVersion,
            seed: seed,
            analyzedSeconds: sensors.summary.analyzedSeconds,
            approxPeakDB: Double(sensors.summary.audio.approxPeakDB),
            approxRMSdBFS: Double(sensors.summary.audio.approxRMSdBFS),
            warningReasons: reasons,
            chain: chain,
            flags: flags.sorted()
        )

        let data = (try? JSONWriting.encode(inputs)) ?? Data()
        return StableHash.sha256Hex(data)
    }
}
