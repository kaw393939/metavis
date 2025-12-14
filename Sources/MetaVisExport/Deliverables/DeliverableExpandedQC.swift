import Foundation

public struct DeliverableContentQCReport: Codable, Sendable, Equatable {
    public struct Sample: Codable, Sendable, Equatable {
        public struct LumaStats: Codable, Sendable, Equatable {
            public var meanLuma: Double
            public var lowLumaFraction: Double
            public var highLumaFraction: Double
            public var peakLumaBin: Int

            public init(meanLuma: Double, lowLumaFraction: Double, highLumaFraction: Double, peakLumaBin: Int) {
                self.meanLuma = meanLuma
                self.lowLumaFraction = lowLumaFraction
                self.highLumaFraction = highLumaFraction
                self.peakLumaBin = peakLumaBin
            }
        }

        public var label: String
        public var timeSeconds: Double
        public var fingerprint: Fingerprint
        public var lumaStats: LumaStats?

        public init(label: String, timeSeconds: Double, fingerprint: Fingerprint, lumaStats: LumaStats? = nil) {
            self.label = label
            self.timeSeconds = timeSeconds
            self.fingerprint = fingerprint
            self.lumaStats = lumaStats
        }
    }

    public struct Fingerprint: Codable, Sendable, Equatable {
        public var meanR: Double
        public var meanG: Double
        public var meanB: Double
        public var stdR: Double
        public var stdG: Double
        public var stdB: Double

        public init(meanR: Double, meanG: Double, meanB: Double, stdR: Double, stdG: Double, stdB: Double) {
            self.meanR = meanR
            self.meanG = meanG
            self.meanB = meanB
            self.stdR = stdR
            self.stdG = stdG
            self.stdB = stdB
        }
    }

    public struct AdjacentDistance: Codable, Sendable, Equatable {
        public var fromLabel: String
        public var toLabel: String
        public var distance: Double

        public init(fromLabel: String, toLabel: String, distance: Double) {
            self.fromLabel = fromLabel
            self.toLabel = toLabel
            self.distance = distance
        }
    }

    public var minDistance: Double
    public var samples: [Sample]
    public var adjacentDistances: [AdjacentDistance]

    /// Whether temporal variety gating was enforced for this export.
    public var enforced: Bool?

    /// Adjacent pairs that fell below `minDistance`.
    public var violations: [AdjacentDistance]?

    public init(
        minDistance: Double,
        samples: [Sample],
        adjacentDistances: [AdjacentDistance],
        enforced: Bool? = nil,
        violations: [AdjacentDistance]? = nil
    ) {
        self.minDistance = minDistance
        self.samples = samples
        self.adjacentDistances = adjacentDistances
        self.enforced = enforced
        self.violations = violations
    }
}

public struct DeliverableMetadataQCReport: Codable, Sendable, Equatable {
    public var hasVideoTrack: Bool
    public var hasAudioTrack: Bool

    public var videoCodecFourCC: String?
    public var videoFormatName: String?
    public var videoBitsPerComponent: Int?
    public var videoFullRangeVideo: Bool?
    public var videoIsHDR: Bool?
    public var colorPrimaries: String?
    public var transferFunction: String?
    public var yCbCrMatrix: String?

    public var audioChannelCount: Int?
    public var audioSampleRateHz: Double?

    public init(
        hasVideoTrack: Bool,
        hasAudioTrack: Bool,
        videoCodecFourCC: String? = nil,
        videoFormatName: String? = nil,
        videoBitsPerComponent: Int? = nil,
        videoFullRangeVideo: Bool? = nil,
        videoIsHDR: Bool? = nil,
        colorPrimaries: String? = nil,
        transferFunction: String? = nil,
        yCbCrMatrix: String? = nil,
        audioChannelCount: Int? = nil,
        audioSampleRateHz: Double? = nil
    ) {
        self.hasVideoTrack = hasVideoTrack
        self.hasAudioTrack = hasAudioTrack
        self.videoCodecFourCC = videoCodecFourCC
        self.videoFormatName = videoFormatName
        self.videoBitsPerComponent = videoBitsPerComponent
        self.videoFullRangeVideo = videoFullRangeVideo
        self.videoIsHDR = videoIsHDR
        self.colorPrimaries = colorPrimaries
        self.transferFunction = transferFunction
        self.yCbCrMatrix = yCbCrMatrix
        self.audioChannelCount = audioChannelCount
        self.audioSampleRateHz = audioSampleRateHz
    }
}

public struct DeliverableSidecarQCReport: Codable, Sendable, Equatable {
    public struct Requested: Codable, Sendable, Equatable {
        public var kind: DeliverableSidecarKind
        public var fileName: String
        public var required: Bool

        public init(kind: DeliverableSidecarKind, fileName: String, required: Bool) {
            self.kind = kind
            self.fileName = fileName
            self.required = required
        }
    }

    public struct Entry: Codable, Sendable, Equatable {
        public var kind: DeliverableSidecarKind
        public var fileName: String
        public var fileBytes: Int

        public init(kind: DeliverableSidecarKind, fileName: String, fileBytes: Int) {
            self.kind = kind
            self.fileName = fileName
            self.fileBytes = fileBytes
        }
    }

    public var requested: [DeliverableSidecar]
    public var requestedWithRequirements: [Requested]?
    public var written: [Entry]

    /// Optional sidecars that failed to write or validated as empty.
    public var optionalFailures: [DeliverableSidecar]?

    public init(
        requested: [DeliverableSidecar],
        requestedWithRequirements: [Requested]? = nil,
        written: [Entry],
        optionalFailures: [DeliverableSidecar]? = nil
    ) {
        self.requested = requested
        self.requestedWithRequirements = requestedWithRequirements
        self.written = written
        self.optionalFailures = optionalFailures
    }
}
