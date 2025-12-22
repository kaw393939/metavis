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
        func defaultPersonId() -> String {
            sensors.videoSamples
                .lazy
                .flatMap { $0.faces }
                .compactMap { $0.personId }
                .first ?? "P0"
        }

        let stride = max(0.01, sensors.sampling.videoStrideSeconds)
        // Similar to the diarize command: half-stride + tiny bias.
        let sampleWindow = max(0.12, (stride / 2.0) + 0.02)

        func faceArea(_ f: MasterSensors.Face) -> Double {
            let r = f.rect
            return max(0.0, Double(r.width * r.height))
        }

        func clamp01(_ x: Double) -> Double {
            if x <= 0 { return 0 }
            if x >= 1 { return 1 }
            return x
        }

        func inferredPersonId(for window: (start: Time, end: Time)) -> String {
            let startSec = window.start.seconds
            let endSec = window.end.seconds

            // Consider a slightly widened interval to align audio segments to video sample stride.
            let lo = startSec - sampleWindow
            let hi = endSec + sampleWindow
            let candidates = sensors.videoSamples.filter { $0.time >= lo && $0.time <= hi }
            if candidates.isEmpty { return defaultPersonId() }

            // Gather eligible personIds and detect whether mouth ratios are present at all.
            var personIds: [String] = []
            personIds.reserveCapacity(4)
            var anyMouth = false
            for s in candidates {
                for f in s.faces {
                    if let pid = f.personId {
                        personIds.append(pid)
                    }
                    if f.mouthOpenRatio != nil { anyMouth = true }
                }
            }

            let uniquePersonIds = Array(Set(personIds)).sorted()
            if uniquePersonIds.isEmpty { return defaultPersonId() }
            if uniquePersonIds.count == 1 { return uniquePersonIds[0] }

            // Fallback stats used whether or not mouth ratios exist.
            var presenceCount: [String: Int] = [:]
            var areaSum: [String: Double] = [:]
            for pid in uniquePersonIds {
                presenceCount[pid] = 0
                areaSum[pid] = 0
            }

            // When mouth ratios exist, do per-sample "winner" voting.
            var mouthVotes: [String: Int] = [:]
            if anyMouth {
                for pid in uniquePersonIds { mouthVotes[pid] = 0 }
            }

            for s in candidates {
                // Track presence/area for all visible faces.
                for f in s.faces {
                    guard let pid = f.personId else { continue }
                    presenceCount[pid, default: 0] += 1
                    areaSum[pid, default: 0] += faceArea(f)
                }

                guard anyMouth else { continue }

                // Vote for the face with highest mouthOpenRatio at this sample.
                var bestPid: String?
                var bestScore = -Double.greatestFiniteMagnitude
                for f in s.faces {
                    guard let pid = f.personId else { continue }
                    let m = clamp01(f.mouthOpenRatio ?? 0)
                    // Break ties deterministically by personId.
                    if m > bestScore || (m == bestScore && (bestPid == nil || pid < bestPid!)) {
                        bestScore = m
                        bestPid = pid
                    }
                }
                if let bestPid, bestScore > 0 {
                    mouthVotes[bestPid, default: 0] += 1
                }
            }

            func bestByPresenceThenArea() -> String {
                uniquePersonIds.max { a, b in
                    let pa = presenceCount[a, default: 0]
                    let pb = presenceCount[b, default: 0]
                    if pa != pb { return pa < pb }
                    let aa = areaSum[a, default: 0]
                    let ab = areaSum[b, default: 0]
                    if aa != ab { return aa < ab }
                    return a > b
                } ?? defaultPersonId()
            }

            guard anyMouth else {
                return bestByPresenceThenArea()
            }

            // Prefer mouth-vote winner when it is meaningfully supported.
            let sortedByVotes = uniquePersonIds.sorted { a, b in
                let va = mouthVotes[a, default: 0]
                let vb = mouthVotes[b, default: 0]
                if va != vb { return va > vb }
                // Secondary: presence
                let pa = presenceCount[a, default: 0]
                let pb = presenceCount[b, default: 0]
                if pa != pb { return pa > pb }
                // Secondary: area
                let aa = areaSum[a, default: 0]
                let ab = areaSum[b, default: 0]
                if aa != ab { return aa > ab }
                return a < b
            }
            let winner = sortedByVotes[0]
            let winnerVotes = mouthVotes[winner, default: 0]
            let runnerUpVotes = mouthVotes[sortedByVotes[1], default: 0]

            // If votes are too weak/ambiguous, fall back to presence/area.
            if winnerVotes < 2 || winnerVotes == runnerUpVotes {
                return bestByPresenceThenArea()
            }
            return winner
        }

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
            let pid = inferredPersonId(for: w)
            return BiteMap.Bite(start: w.start, end: w.end, personId: pid, reason: "speech_energy")
        }

        return BiteMap(bites: bites)
    }
}
