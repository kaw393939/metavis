import Foundation
import MetaVisCore

public enum AutoSpeakerAudioEnhancer {

    public struct Options: Sendable, Equatable {
        public var preferSafetyWhenClipRisk: Bool

        public init(preferSafetyWhenClipRisk: Bool = true) {
            self.preferSafetyWhenClipRisk = preferSafetyWhenClipRisk
        }
    }

    public static func propose(from sensors: MasterSensors, options: Options = Options()) -> AutoEnhance.SpeakerAudioProposal {
        let reasons = sensors.warnings.flatMap { $0.governedReasonCodes }
        let hasNoiseRisk = reasons.contains(.audio_noise_risk)
        let hasClipRisk = reasons.contains(.audio_clip_risk)

        if !hasNoiseRisk {
            return .identity
        }

        // v1: enable deterministic dialog cleanup when noise risk is present.
        // If clip risk is also present, reduce the preset gain to avoid pushing peaks.
        var gainDB: Double = 6.0
        if options.preferSafetyWhenClipRisk && hasClipRisk {
            gainDB = 3.0
        }

        return AutoEnhance.SpeakerAudioProposal(
            enableDialogCleanwaterV1: true,
            dialogCleanwaterGlobalGainDB: gainDB
        ).clamped()
    }
}
