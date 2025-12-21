import Foundation

public struct ParameterWhitelist: Codable, Sendable, Equatable {
    public struct NumericRange: Codable, Sendable, Equatable {
        public var min: Double
        public var max: Double
        public var maxDeltaPerCycle: Double

        public init(min: Double, max: Double, maxDeltaPerCycle: Double) {
            self.min = min
            self.max = max
            self.maxDeltaPerCycle = maxDeltaPerCycle
        }
    }

    /// Keyed by a stable parameter path, e.g. "chain[0].params.globalGainDB".
    public var numeric: [String: NumericRange]

    public init(numeric: [String: NumericRange] = [:]) {
        self.numeric = numeric
    }

    /// Clamp a proposed numeric value to the whitelist bounds and per-cycle delta.
    /// Returns the updated value and an optional machine-readable violation code.
    public func applyNumericEdit(path: String, current: Double, proposed: Double) -> (value: Double, violation: String?) {
        guard let range = numeric[path] else {
            return (current, "WHITELIST_DENIED")
        }

        let clamped = min(max(proposed, range.min), range.max)
        let delta = clamped - current
        if abs(delta) > range.maxDeltaPerCycle {
            let stepped = current + (delta > 0 ? range.maxDeltaPerCycle : -range.maxDeltaPerCycle)
            return (stepped, "WHITELIST_MAX_DELTA_EXCEEDED")
        }
        if clamped != proposed {
            return (clamped, "WHITELIST_CLAMPED")
        }
        return (clamped, nil)
    }
}

public struct EvidencePack: Codable, Sendable, Equatable {
    public struct Budgets: Codable, Sendable, Equatable {
        public var maxFrames: Int
        public var maxVideoClips: Int
        public var videoClipSeconds: Double
        public var maxAudioClips: Int
        public var audioClipSeconds: Double

        public init(maxFrames: Int, maxVideoClips: Int, videoClipSeconds: Double, maxAudioClips: Int, audioClipSeconds: Double) {
            self.maxFrames = maxFrames
            self.maxVideoClips = maxVideoClips
            self.videoClipSeconds = videoClipSeconds
            self.maxAudioClips = maxAudioClips
            self.audioClipSeconds = audioClipSeconds
        }
    }

    public struct BudgetsUsed: Codable, Sendable, Equatable {
        public var frames: Int
        public var videoClips: Int
        public var audioClips: Int
        public var totalAudioSeconds: Double
        public var totalVideoSeconds: Double

        public init(frames: Int, videoClips: Int, audioClips: Int, totalAudioSeconds: Double, totalVideoSeconds: Double) {
            self.frames = frames
            self.videoClips = videoClips
            self.audioClips = audioClips
            self.totalAudioSeconds = totalAudioSeconds
            self.totalVideoSeconds = totalVideoSeconds
        }
    }

    public struct Manifest: Codable, Sendable, Equatable {
        public var cycleIndex: Int
        public var seed: String
        public var policyVersion: String
        public var budgetsConfigured: Budgets
        public var budgetsUsed: BudgetsUsed
        public var timestampsSelected: [Double]
        public var selectionNotes: [String]

        public init(
            cycleIndex: Int,
            seed: String,
            policyVersion: String,
            budgetsConfigured: Budgets,
            budgetsUsed: BudgetsUsed,
            timestampsSelected: [Double],
            selectionNotes: [String]
        ) {
            self.cycleIndex = cycleIndex
            self.seed = seed
            self.policyVersion = policyVersion
            self.budgetsConfigured = budgetsConfigured
            self.budgetsUsed = budgetsUsed
            self.timestampsSelected = timestampsSelected
            self.selectionNotes = selectionNotes
        }
    }

    public struct FrameAsset: Codable, Sendable, Equatable {
        public var path: String
        public var timeSeconds: Double
        public var rationaleTags: [String]

        public init(path: String, timeSeconds: Double, rationaleTags: [String]) {
            self.path = path
            self.timeSeconds = timeSeconds
            self.rationaleTags = rationaleTags
        }
    }

    public struct VideoClipAsset: Codable, Sendable, Equatable {
        public var path: String
        public var startSeconds: Double
        public var endSeconds: Double
        public var rationaleTags: [String]

        public init(path: String, startSeconds: Double, endSeconds: Double, rationaleTags: [String]) {
            self.path = path
            self.startSeconds = startSeconds
            self.endSeconds = endSeconds
            self.rationaleTags = rationaleTags
        }
    }

    public struct AudioClipAsset: Codable, Sendable, Equatable {
        public var path: String
        public var startSeconds: Double
        public var endSeconds: Double
        public var rationaleTags: [String]

        public init(path: String, startSeconds: Double, endSeconds: Double, rationaleTags: [String]) {
            self.path = path
            self.startSeconds = startSeconds
            self.endSeconds = endSeconds
            self.rationaleTags = rationaleTags
        }
    }

    public struct Assets: Codable, Sendable, Equatable {
        public var frames: [FrameAsset]
        public var videoClips: [VideoClipAsset]
        public var audioClips: [AudioClipAsset]

        public init(frames: [FrameAsset] = [], videoClips: [VideoClipAsset] = [], audioClips: [AudioClipAsset] = []) {
            self.frames = frames
            self.videoClips = videoClips
            self.audioClips = audioClips
        }
    }

    public var schemaVersion: Int
    public var manifest: Manifest
    public var assets: Assets
    public var textSummary: String

    public init(schemaVersion: Int = 1, manifest: Manifest, assets: Assets, textSummary: String) {
        self.schemaVersion = schemaVersion
        self.manifest = manifest
        self.assets = assets
        self.textSummary = textSummary
    }
}

public struct AcceptanceReport: Codable, Sendable, Equatable {
    public struct SuggestedEdit: Codable, Sendable, Equatable {
        public var path: String
        public var value: Double

        public init(path: String, value: Double) {
            self.path = path
            self.value = value
        }
    }

    public struct RequestedEvidenceEscalation: Codable, Sendable, Equatable {
        public var addFramesAtSeconds: [Double]?
        public var extendOneAudioClipToSeconds: Double?
        public var notes: [String]

        public init(addFramesAtSeconds: [Double]? = nil, extendOneAudioClipToSeconds: Double? = nil, notes: [String] = []) {
            self.addFramesAtSeconds = addFramesAtSeconds
            self.extendOneAudioClipToSeconds = extendOneAudioClipToSeconds
            self.notes = notes
        }
    }

    public var accepted: Bool
    public var qualityAccepted: Bool
    public var qaPerformed: Bool
    public var score: Double?
    public var reasons: [String]
    public var violations: [String]
    public var suggestedEdits: [SuggestedEdit]
    public var requestedEvidenceEscalation: RequestedEvidenceEscalation?
    public var summary: String

    public init(
        accepted: Bool,
        qualityAccepted: Bool,
        qaPerformed: Bool,
        summary: String,
        score: Double? = nil,
        reasons: [String] = [],
        violations: [String] = [],
        suggestedEdits: [SuggestedEdit] = [],
        requestedEvidenceEscalation: RequestedEvidenceEscalation? = nil
    ) {
        self.accepted = accepted
        self.qualityAccepted = qualityAccepted
        self.qaPerformed = qaPerformed
        self.score = score
        self.reasons = reasons
        self.violations = violations
        self.suggestedEdits = suggestedEdits
        self.requestedEvidenceEscalation = requestedEvidenceEscalation
        self.summary = summary
    }
}
