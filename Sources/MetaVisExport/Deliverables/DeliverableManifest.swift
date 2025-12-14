import Foundation
import MetaVisCore
import MetaVisTimeline

public struct TimelineSummary: Codable, Sendable, Equatable {
    public var durationSeconds: Double
    public var trackCount: Int
    public var clipCount: Int

    public init(durationSeconds: Double, trackCount: Int, clipCount: Int) {
        self.durationSeconds = durationSeconds
        self.trackCount = trackCount
        self.clipCount = clipCount
    }

    public static func fromTimeline(_ timeline: Timeline) -> TimelineSummary {
        let trackCount = timeline.tracks.count
        let clipCount = timeline.tracks.reduce(0) { $0 + $1.clips.count }
        return TimelineSummary(durationSeconds: timeline.duration.seconds, trackCount: trackCount, clipCount: clipCount)
    }
}

public struct DeterministicQCReport: Codable, Sendable, Equatable {
    public var durationSeconds: Double
    public var width: Int
    public var height: Int
    public var nominalFrameRate: Double
    public var estimatedDataRate: Float
    public var videoSampleCount: Int

    public init(
        durationSeconds: Double,
        width: Int,
        height: Int,
        nominalFrameRate: Double,
        estimatedDataRate: Float,
        videoSampleCount: Int
    ) {
        self.durationSeconds = durationSeconds
        self.width = width
        self.height = height
        self.nominalFrameRate = nominalFrameRate
        self.estimatedDataRate = estimatedDataRate
        self.videoSampleCount = videoSampleCount
    }
}

public struct DeliverableManifest: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var createdAt: Date

    public var deliverable: ExportDeliverable

    public var timeline: TimelineSummary

    public var quality: QualityProfile
    public var frameRate: Int32

    /// Stored as a string because `AVVideoCodecType` is not `Codable`.
    public var codec: String

    public var audioPolicy: AudioPolicy

    public var governance: ExportGovernance

    public var qcPolicy: DeterministicQCPolicy
    public var qcReport: DeterministicQCReport

    public var qcContentReport: DeliverableContentQCReport?
    public var qcMetadataReport: DeliverableMetadataQCReport?
    public var qcSidecarReport: DeliverableSidecarQCReport?

    public var sidecars: [DeliverableSidecar]

    public init(
        schemaVersion: Int = 4,
        createdAt: Date = Date(),
        deliverable: ExportDeliverable,
        timeline: TimelineSummary,
        quality: QualityProfile,
        frameRate: Int32,
        codec: String,
        audioPolicy: AudioPolicy,
        governance: ExportGovernance,
        qcPolicy: DeterministicQCPolicy,
        qcReport: DeterministicQCReport,
        qcContentReport: DeliverableContentQCReport? = nil,
        qcMetadataReport: DeliverableMetadataQCReport? = nil,
        qcSidecarReport: DeliverableSidecarQCReport? = nil,
        sidecars: [DeliverableSidecar] = []
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.deliverable = deliverable
        self.timeline = timeline
        self.quality = quality
        self.frameRate = frameRate
        self.codec = codec
        self.audioPolicy = audioPolicy
        self.governance = governance
        self.qcPolicy = qcPolicy
        self.qcReport = qcReport
        self.qcContentReport = qcContentReport
        self.qcMetadataReport = qcMetadataReport
        self.qcSidecarReport = qcSidecarReport
        self.sidecars = sidecars
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case createdAt
        case deliverable
        case timeline
        case quality
        case frameRate
        case codec
        case audioPolicy
        case governance
        case qcPolicy
        case qcReport
        case qcContentReport
        case qcMetadataReport
        case qcSidecarReport
        case sidecars
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.deliverable = try container.decode(ExportDeliverable.self, forKey: .deliverable)
        self.timeline = try container.decode(TimelineSummary.self, forKey: .timeline)
        self.quality = try container.decode(QualityProfile.self, forKey: .quality)
        self.frameRate = try container.decode(Int32.self, forKey: .frameRate)
        self.codec = try container.decode(String.self, forKey: .codec)
        self.audioPolicy = try container.decode(AudioPolicy.self, forKey: .audioPolicy)
        self.governance = try container.decode(ExportGovernance.self, forKey: .governance)
        self.qcPolicy = try container.decode(DeterministicQCPolicy.self, forKey: .qcPolicy)
        self.qcReport = try container.decode(DeterministicQCReport.self, forKey: .qcReport)
        self.qcContentReport = try container.decodeIfPresent(DeliverableContentQCReport.self, forKey: .qcContentReport)
        self.qcMetadataReport = try container.decodeIfPresent(DeliverableMetadataQCReport.self, forKey: .qcMetadataReport)
        self.qcSidecarReport = try container.decodeIfPresent(DeliverableSidecarQCReport.self, forKey: .qcSidecarReport)
        self.sidecars = try container.decodeIfPresent([DeliverableSidecar].self, forKey: .sidecars) ?? []
    }
}
