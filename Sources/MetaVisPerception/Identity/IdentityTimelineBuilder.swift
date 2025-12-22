import Foundation
import MetaVisCore

public enum IdentityTimelineBuilder {

    public static func build(
        sensors: MasterSensors,
        diarizedWords: [TranscriptWordV1],
        attributions: [TranscriptAttributionV1],
        bindings: IdentityBindingGraphV1
    ) -> IdentityTimelineV1 {
        // Index attribution confidence by wordId for aggregation.
        var attributionByWordId: [String: TranscriptAttributionV1] = [:]
        attributionByWordId.reserveCapacity(attributions.count)
        for a in attributions {
            attributionByWordId[a.wordId] = a
        }

        func wordTimingSeconds(_ w: TranscriptWordV1) -> (start: Double, end: Double) {
            let startTicks = w.timelineTimeTicks ?? w.sourceTimeTicks
            let endTicks = w.timelineTimeEndTicks ?? w.sourceTimeEndTicks
            let s = Double(min(startTicks, endTicks)) / 60000.0
            let e = Double(max(startTicks, endTicks)) / 60000.0
            return (start: s, end: max(s, e))
        }

        // Collect per-speaker lifecycle aggregates.
        struct SpeakerAgg {
            var speakerId: String
            var speakerLabel: String?
            var bornAt: Double
            var lastActiveAt: Double
            var confidenceSum: Double
            var confidenceCount: Int
            var activeDurationSum: Double
        }

        var bySpeaker: [String: SpeakerAgg] = [:]

        for w in diarizedWords {
            guard let speakerId = w.speakerId, let speakerLabel = w.speakerLabel else { continue }
            let t = wordTimingSeconds(w)

            let score: Double
            if let a = attributionByWordId[w.wordId] {
                score = Double(a.attributionConfidence.score)
            } else {
                score = 0.0
            }

            if var agg = bySpeaker[speakerId] {
                agg.speakerLabel = agg.speakerLabel ?? speakerLabel
                agg.bornAt = min(agg.bornAt, t.start)
                agg.lastActiveAt = max(agg.lastActiveAt, t.end)
                agg.confidenceSum += score
                agg.confidenceCount += 1
                agg.activeDurationSum += max(0.0, t.end - t.start)
                bySpeaker[speakerId] = agg
            } else {
                bySpeaker[speakerId] = SpeakerAgg(
                    speakerId: speakerId,
                    speakerLabel: speakerLabel,
                    bornAt: t.start,
                    lastActiveAt: t.end,
                    confidenceSum: score,
                    confidenceCount: 1,
                    activeDurationSum: max(0.0, t.end - t.start)
                )
            }
        }

        // Best bindings per speaker (deterministic sort and selection).
        struct BestBinding {
            var trackId: UUID
            var personId: String?
            var posterior: Double
        }
        var bestBindingBySpeakerId: [String: BestBinding] = [:]
        for e in bindings.bindings {
            // Prefer higher posterior; tie-break by UUID string for determinism.
            if let cur = bestBindingBySpeakerId[e.speakerId] {
                let better = (e.posterior > cur.posterior) || (e.posterior == cur.posterior && e.trackId.uuidString < cur.trackId.uuidString)
                if better {
                    bestBindingBySpeakerId[e.speakerId] = BestBinding(trackId: e.trackId, personId: e.personId, posterior: e.posterior)
                }
            } else {
                bestBindingBySpeakerId[e.speakerId] = BestBinding(trackId: e.trackId, personId: e.personId, posterior: e.posterior)
            }
        }

        // Deterministic merge candidates: speakers that bind to the same personId with strong posterior.
        var speakersByPersonId: [String: [String]] = [:]
        for (sid, b) in bestBindingBySpeakerId {
            guard let pid = b.personId else { continue }
            guard b.posterior >= 0.50 else { continue }
            speakersByPersonId[pid, default: []].append(sid)
        }
        for (pid, sids) in speakersByPersonId {
            speakersByPersonId[pid] = sids.sorted()
        }

        // Build speaker records.
        var speakers: [IdentitySpeakerV1] = []
        speakers.reserveCapacity(bySpeaker.count)
        let freezeMinActiveSeconds = 2.0
        for (speakerId, agg) in bySpeaker {
            let meanConfidence = agg.confidenceCount > 0 ? (agg.confidenceSum / Double(agg.confidenceCount)) : 0.0
            let isOffscreen = speakerId == "OFFSCREEN"
            let frozen = (!isOffscreen) && (agg.activeDurationSum >= freezeMinActiveSeconds)
            let frozenAt = frozen ? (agg.bornAt + min(freezeMinActiveSeconds, max(0.0, agg.lastActiveAt - agg.bornAt))) : nil

            let best = bestBindingBySpeakerId[speakerId]
            let mergeCandidates: [String]
            if let pid = best?.personId, let sids = speakersByPersonId[pid] {
                mergeCandidates = sids.filter { $0 != speakerId }
            } else {
                mergeCandidates = []
            }

            speakers.append(
                IdentitySpeakerV1(
                    speakerId: speakerId,
                    speakerLabel: agg.speakerLabel,
                    bornAtSeconds: agg.bornAt,
                    lastActiveAtSeconds: agg.lastActiveAt,
                    frozen: frozen,
                    frozenAtSeconds: frozenAt,
                    confidenceScore: meanConfidence,
                    mergeCandidates: mergeCandidates,
                    bestPersonId: best?.personId,
                    bestTrackId: best?.trackId,
                    bestPosterior: best?.posterior
                )
            )
        }
        speakers.sort { lhs, rhs in
            if lhs.bornAtSeconds != rhs.bornAtSeconds { return lhs.bornAtSeconds < rhs.bornAtSeconds }
            return lhs.speakerId < rhs.speakerId
        }

        // Build contiguous spans by speakerId from diarized words.
        struct TimedSpeakerWord {
            var speakerId: String
            var speakerLabel: String?
            var start: Double
            var end: Double
        }
        let timedWords: [TimedSpeakerWord] = diarizedWords.compactMap { w in
            guard let speakerId = w.speakerId else { return nil }
            let t = wordTimingSeconds(w)
            return TimedSpeakerWord(speakerId: speakerId, speakerLabel: w.speakerLabel, start: t.start, end: t.end)
        }.sorted { a, b in
            if a.start != b.start { return a.start < b.start }
            if a.end != b.end { return a.end < b.end }
            return a.speakerId < b.speakerId
        }

        var spans: [IdentitySpanV1] = []
        spans.reserveCapacity(max(1, timedWords.count / 6))

        let mergeGapSeconds = 0.4
        var currentSpeakerId: String? = nil
        var currentSpeakerLabel: String? = nil
        var currentStart: Double = 0
        var currentEnd: Double = 0
        var currentCount: Int = 0

        func flushSpan() {
            guard let sid = currentSpeakerId else { return }
            spans.append(
                IdentitySpanV1(
                    speakerId: sid,
                    speakerLabel: currentSpeakerLabel,
                    startSeconds: currentStart,
                    endSeconds: currentEnd,
                    wordCount: currentCount
                )
            )
            currentSpeakerId = nil
            currentSpeakerLabel = nil
            currentCount = 0
        }

        for w in timedWords {
            if currentSpeakerId == nil {
                currentSpeakerId = w.speakerId
                currentSpeakerLabel = w.speakerLabel
                currentStart = w.start
                currentEnd = w.end
                currentCount = 1
                continue
            }

            let sameSpeaker = currentSpeakerId == w.speakerId
            let smallGap = (w.start - currentEnd) <= mergeGapSeconds
            if sameSpeaker && smallGap {
                currentEnd = max(currentEnd, w.end)
                currentCount += 1
            } else {
                flushSpan()
                currentSpeakerId = w.speakerId
                currentSpeakerLabel = w.speakerLabel
                currentStart = w.start
                currentEnd = w.end
                currentCount = 1
            }
        }
        flushSpan()

        // Bindings are already a deterministic, versioned surface.
        let sortedBindings = bindings.bindings.sorted { a, b in
            if a.speakerId != b.speakerId { return a.speakerId < b.speakerId }
            if a.posterior != b.posterior { return a.posterior > b.posterior }
            return a.trackId.uuidString < b.trackId.uuidString
        }

        return IdentityTimelineV1(
            analyzedSeconds: sensors.summary.analyzedSeconds,
            speakers: speakers,
            spans: spans,
            bindings: sortedBindings
        )
    }
}
