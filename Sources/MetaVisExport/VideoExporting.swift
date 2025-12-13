import Foundation
import AVFoundation
import MetaVisCore
import MetaVisTimeline

public protocol VideoExporting: Sendable {
    func export(
        timeline: Timeline,
        to outputURL: URL,
        quality: QualityProfile,
        frameRate: Int32,
        codec: AVVideoCodecType,
        audioPolicy: AudioPolicy,
        governance: ExportGovernance
    ) async throws
}
