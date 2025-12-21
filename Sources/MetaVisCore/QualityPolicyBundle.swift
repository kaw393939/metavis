import Foundation

public struct VideoContainerPolicy: Codable, Sendable, Equatable {
    public var minDurationSeconds: Double
    public var maxDurationSeconds: Double
    public var expectedWidth: Int
    public var expectedHeight: Int
    public var expectedNominalFrameRate: Double
    public var minVideoSampleCount: Int

    public init(
        minDurationSeconds: Double,
        maxDurationSeconds: Double,
        expectedWidth: Int,
        expectedHeight: Int,
        expectedNominalFrameRate: Double,
        minVideoSampleCount: Int
    ) {
        self.minDurationSeconds = minDurationSeconds
        self.maxDurationSeconds = maxDurationSeconds
        self.expectedWidth = expectedWidth
        self.expectedHeight = expectedHeight
        self.expectedNominalFrameRate = expectedNominalFrameRate
        self.minVideoSampleCount = minVideoSampleCount
    }
}

public struct VideoContentPolicy: Codable, Sendable, Equatable {
    public struct ColorStatsPolicy: Codable, Sendable, Equatable {
        public var enforce: Bool
        public var minMeanLuma: Float
        public var maxMeanLuma: Float
        public var maxChannelDelta: Float
        public var minLowLumaFraction: Float
        public var minHighLumaFraction: Float
        public var maxDimension: Int

        public init(
            enforce: Bool = false,
            minMeanLuma: Float = 0,
            maxMeanLuma: Float = 1,
            maxChannelDelta: Float = 1,
            minLowLumaFraction: Float = 0,
            minHighLumaFraction: Float = 0,
            maxDimension: Int = 256
        ) {
            self.enforce = enforce
            self.minMeanLuma = minMeanLuma
            self.maxMeanLuma = maxMeanLuma
            self.maxChannelDelta = maxChannelDelta
            self.minLowLumaFraction = minLowLumaFraction
            self.minHighLumaFraction = minHighLumaFraction
            self.maxDimension = maxDimension
        }
    }

    public var minAdjacentDistance: Double
    public var enforceTemporalVarietyIfMultipleClips: Bool
    public var colorStats: ColorStatsPolicy?

    public init(
        minAdjacentDistance: Double = 0.020,
        enforceTemporalVarietyIfMultipleClips: Bool = true,
        colorStats: ColorStatsPolicy? = nil
    ) {
        self.minAdjacentDistance = minAdjacentDistance
        self.enforceTemporalVarietyIfMultipleClips = enforceTemporalVarietyIfMultipleClips
        self.colorStats = colorStats
    }
}

public struct DeterministicQCPolicy: Codable, Sendable, Equatable {
    public var video: VideoContainerPolicy

    public var content: VideoContentPolicy?

    public var requireAudioTrack: Bool
    public var requireAudioNotSilent: Bool
    public var audioSampleSeconds: Double
    public var minAudioPeak: Float

    public init(
        video: VideoContainerPolicy,
        content: VideoContentPolicy? = nil,
        requireAudioTrack: Bool,
        requireAudioNotSilent: Bool,
        audioSampleSeconds: Double = 0.5,
        minAudioPeak: Float = 0.0005
    ) {
        self.video = video
        self.content = content
        self.requireAudioTrack = requireAudioTrack
        self.requireAudioNotSilent = requireAudioNotSilent
        self.audioSampleSeconds = audioSampleSeconds
        self.minAudioPeak = minAudioPeak
    }
}

public struct AIGatePolicy: Codable, Sendable, Equatable {
    public struct KeyFrame: Codable, Sendable, Equatable {
        public var timeSeconds: Double
        public var label: String
        public init(timeSeconds: Double, label: String) {
            self.timeSeconds = timeSeconds
            self.label = label
        }
    }

    public var expectedNarrative: String
    public var keyFrames: [KeyFrame]
    public var requireKey: Bool

    public init(expectedNarrative: String, keyFrames: [KeyFrame], requireKey: Bool) {
        self.expectedNarrative = expectedNarrative
        self.keyFrames = keyFrames
        self.requireKey = requireKey
    }
}

public struct PrivacyPolicy: Codable, Sendable, Equatable {
    public var allowRawMediaUpload: Bool
    public var allowDeliverablesUpload: Bool

    public init(allowRawMediaUpload: Bool = false, allowDeliverablesUpload: Bool = false) {
        self.allowRawMediaUpload = allowRawMediaUpload
        self.allowDeliverablesUpload = allowDeliverablesUpload
    }
}

public struct QualityPolicyBundle: Codable, Sendable, Equatable {
    public var export: ExportGovernance
    public var qc: DeterministicQCPolicy
    public var ai: AIGatePolicy?
    public var aiUsage: AIUsagePolicy?
    public var privacy: PrivacyPolicy

    public init(
        export: ExportGovernance,
        qc: DeterministicQCPolicy,
        ai: AIGatePolicy? = nil,
        aiUsage: AIUsagePolicy? = nil,
        privacy: PrivacyPolicy = PrivacyPolicy()
    ) {
        self.export = export
        self.qc = qc
        self.ai = ai
        self.aiUsage = aiUsage
        self.privacy = privacy
    }
}
