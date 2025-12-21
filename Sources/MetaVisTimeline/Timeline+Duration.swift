import Foundation
import MetaVisCore

public extension Timeline {
    /// Recomputes `duration` from the max end-time of all clips on all tracks.
    /// Keeps the timeline model consistent after mutations.
    mutating func recomputeDuration() {
        var maxEnd: Time = .zero
        for track in tracks {
            for clip in track.clips {
                if clip.endTime > maxEnd {
                    maxEnd = clip.endTime
                }
            }
        }
        duration = maxEnd
    }
}
