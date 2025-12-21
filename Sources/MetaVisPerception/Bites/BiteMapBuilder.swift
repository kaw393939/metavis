import Foundation
import MetaVisCore

public enum BiteMapBuilder {
    /// Produces a deterministic, real-signal bite map from MasterSensors.
    ///
    /// MVP contract:
    /// - Groups contiguous (or near-contiguous) "speaking" segments per `personId`.
    /// - Uses a simple energy threshold (approxPeakDB) to gate speech presence.
    /// - No diarization or cross-person attribution beyond sensors' `personId`.
    public static func build(
        from sensors: MasterSensors,
        minBiteDuration: Time = Time(seconds: 0.35),
        mergeGap: Time = Time(seconds: 0.15),
        minSpeechConfidence: Double = 0.5
    ) -> BiteMap {
        // Determine which person to attribute. MVP: first observed face personId; else unknown.
        let personId = sensors.videoSamples
            .lazy
            .flatMap { $0.faces }
            .compactMap { $0.personId }
            .first ?? "P0"

        // Extract candidate speaking windows from audioSegments.
        // This keeps the bite map stable even when optional hop-sized frames are absent.
        var windows: [(start: Time, end: Time)] = sensors.audioSegments.compactMap { seg in
            guard seg.kind == .speechLike else { return nil }
            guard seg.confidence >= minSpeechConfidence else { return nil }
            return (start: Time(seconds: seg.start), end: Time(seconds: seg.end))
        }

        // Merge close windows.
        windows.sort { $0.start < $1.start }
        var merged: [(start: Time, end: Time)] = []
        for w in windows {
            if let last = merged.last, (w.start - last.end) <= mergeGap {
                merged[merged.count - 1] = (start: last.start, end: (last.end >= w.end ? last.end : w.end))
            } else {
                merged.append(w)
            }
        }

        // Filter and emit.
        let bites: [BiteMap.Bite] = merged.compactMap { w in
            let duration = w.end - w.start
            guard duration >= minBiteDuration else { return nil }
            return BiteMap.Bite(start: w.start, end: w.end, personId: personId, reason: "speech_energy")
        }

        return BiteMap(bites: bites)
    }
}
