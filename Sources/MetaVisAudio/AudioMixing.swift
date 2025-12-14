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

    public static func timelineRequestsDialogCleanwaterV1(_ timeline: Timeline) -> Bool {
        for track in timeline.tracks where track.kind == .audio {
            for clip in track.clips {
                if clip.effects.contains(where: { $0.id == "audio.dialogCleanwater.v1" }) {
                    return true
                }
            }
        }
        return false
    }
}
