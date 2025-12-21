import Foundation
import AVFoundation
import MetaVisCore
import MetaVisTimeline

public protocol VideoExporting: Sendable {
    func export(
        timeline: Timeline,
        to outputURL: URL,
        quality: QualityProfile,
        frameRate: Int,
        codec: AVVideoCodecType,
        audioPolicy: AudioPolicy,
        governance: ExportGovernance
    ) async throws
}

public extension VideoExporting {
    func export(
        timeline: Timeline,
        to outputURL: URL,
        quality: QualityProfile,
        frameRate: Int32,
        codec: AVVideoCodecType,
        audioPolicy: AudioPolicy,
        governance: ExportGovernance
    ) async throws {
        try await export(
            timeline: timeline,
            to: outputURL,
            quality: quality,
            frameRate: Int(frameRate),
            codec: codec,
            audioPolicy: audioPolicy,
            governance: governance
        )
    }

    func export(
        timeline: Timeline,
        to outputURL: URL,
        quality: QualityProfile,
        codec: AVVideoCodecType,
        audioPolicy: AudioPolicy,
        governance: ExportGovernance
    ) async throws {
        try await export(
            timeline: timeline,
            to: outputURL,
            quality: quality,
            frameRate: 24,
            codec: codec,
            audioPolicy: audioPolicy,
            governance: governance
        )
    }
}
