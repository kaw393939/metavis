import Foundation
import AVFoundation
import MetaVisCore
import MetaVisTimeline

/// Deterministic audio mixing and routing rules.
///
/// Current v1 constraints:
/// - Working format: stereo float (2ch), typically 48kHz.
/// - Track routing: sources mix into a per-track mixer bus, then into the mastering chain input.
/// - Clip envelope: `transitionIn/transitionOut` are applied as a gain envelope using `Clip.alpha(at:)`.
/// - Downmix: not yet required (sources are built at the working channel count).
public enum AudioMixing {

    public static let standardSampleRate: Double = 48_000
    public static let standardChannelCount: AVAudioChannelCount = 2

    public static func clipGain(clip: Clip, atTimelineSeconds timelineSeconds: Double) -> Float {
        // `alpha(at:)` implements transition fade-in/out; for audio, we interpret it as gain.
        return clip.alpha(at: Time(seconds: timelineSeconds))
    }

    public struct DialogCleanwaterRequest: Sendable, Equatable {
        public var globalGainDB: Float
        public init(globalGainDB: Float) {
            self.globalGainDB = globalGainDB
        }
    }

    public static func dialogCleanwaterV1Request(for timeline: Timeline) -> DialogCleanwaterRequest? {
        // Deterministic selection rule: take the smallest requested gain across all clips.
        // This is a safety-first merge and avoids order dependence.
        var minGain: Float?

        for track in timeline.tracks where track.kind == .audio {
            for clip in track.clips {
                guard let fx = clip.effects.first(where: { $0.id == "audio.dialogCleanwater.v1" }) else { continue }

                // Default gain if parameter omitted.
                var requested: Float = 6.0
                if let v = fx.parameters["globalGainDB"], case .float(let f) = v {
                    requested = Float(f)
                }

                if let cur = minGain {
                    minGain = min(cur, requested)
                } else {
                    minGain = requested
                }
            }
        }

        if let minGain {
            // Clamp defensively to match preset expectations.
            let clamped = min(max(minGain, 0.0), 6.0)
            return DialogCleanwaterRequest(globalGainDB: clamped)
        }
        return nil
    }
}
