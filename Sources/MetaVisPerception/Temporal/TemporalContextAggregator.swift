import Foundation
import MetaVisCore

public enum TemporalContextAggregator {
    public struct Options: Sendable {
        public var minTrackStableSeconds: Double
        public var lumaShiftThreshold: Double

        public init(
            minTrackStableSeconds: Double = 2.0,
            lumaShiftThreshold: Double = 0.20
        ) {
            self.minTrackStableSeconds = minTrackStableSeconds
            self.lumaShiftThreshold = lumaShiftThreshold
        }
    }

    public static func aggregate(
        sensors: MasterSensors,
        words: [TranscriptWordV1] = [],
        options: Options = Options()
    ) -> TemporalContextV1 {
        var events: [TemporalEventV1] = []
        events.reserveCapacity(32)

        // 1) Face track stability: for each trackId, detect contiguous presence segments.
        // We treat a track as present in a sample if it appears in `sample.faces`.
        let samples = sensors.videoSamples.sorted { $0.time < $1.time }
        if !samples.isEmpty {
            // Collect all trackIds.
            var all: Set<UUID> = []
            for s in samples {
                for f in s.faces { all.insert(f.trackId) }
            }

            for trackId in all.sorted(by: { $0.uuidString < $1.uuidString }) {
                var segStart: Double? = nil
                var segEnd: Double? = nil
                var lastPersonId: String? = nil

                func flush() {
                    guard let a = segStart, let b = segEnd else { return }
                    let dur = b - a
                    guard dur >= options.minTrackStableSeconds else { return }
                    let conf = ConfidenceRecordV1.evidence(score: 1.0, sources: [.vision], reasons: [], evidenceRefs: [])
                    events.append(
                        TemporalEventV1(
                            kind: .faceTrackStable,
                            startSeconds: a,
                            endSeconds: b,
                            trackId: trackId,
                            personId: lastPersonId,
                            confidence: conf,
                            confidenceLevel: .deterministic,
                            provenance: [
                                .interval("MasterSensors.videoSamples", startSeconds: a, endSeconds: b)
                            ]
                        )
                    )
                }

                for s in samples {
                    let presentFace = s.faces.first(where: { $0.trackId == trackId })
                    let isPresent = (presentFace != nil)

                    if isPresent {
                        if segStart == nil {
                            segStart = s.time
                        }
                        segEnd = s.time
                        lastPersonId = presentFace?.personId ?? lastPersonId
                    } else {
                        flush()
                        segStart = nil
                        segEnd = nil
                    }
                }
                flush()
            }
        }

        // 2) Lighting shift: detect luma discontinuities.
        if samples.count >= 2 {
            for i in 1..<samples.count {
                let a = samples[i - 1]
                let b = samples[i]
                let d = abs(b.meanLuma - a.meanLuma)
                if d >= options.lumaShiftThreshold {
                    let conf = ConfidenceRecordV1.evidence(score: 0.80, sources: [.vision], reasons: [], evidenceRefs: [.metric("video.meanLuma.delta", value: d)])
                    events.append(
                        TemporalEventV1(
                            kind: .lightingShift,
                            startSeconds: a.time,
                            endSeconds: b.time,
                            confidence: conf,
                            confidenceLevel: .heuristic,
                            provenance: [
                                .metric("video.meanLuma.delta", value: d),
                                .interval("MasterSensors.videoSamples", startSeconds: a.time, endSeconds: b.time)
                            ]
                        )
                    )
                }
            }
        }

        // 3) Speaker changes (optional): based on diarized word stream.
        if words.count >= 2 {
            let sortedWords = words.sorted { (lhs, rhs) in
                let a = lhs.timelineTimeTicks ?? lhs.sourceTimeTicks
                let b = rhs.timelineTimeTicks ?? rhs.sourceTimeTicks
                if a != b { return a < b }
                return lhs.wordId < rhs.wordId
            }

            func ticksForTiming(_ w: TranscriptWordV1) -> (start: Int64, end: Int64) {
                let start = w.timelineTimeTicks ?? w.sourceTimeTicks
                let end = w.timelineTimeEndTicks ?? w.sourceTimeEndTicks
                return (start: start, end: max(start, end))
            }

            func midSeconds(startTicks: Int64, endTicks: Int64) -> Double {
                let midTicks = startTicks + (max(Int64(0), endTicks - startTicks) / 2)
                return Double(midTicks) / 60000.0
            }

            var prev = sortedWords[0]
            for i in 1..<sortedWords.count {
                let cur = sortedWords[i]
                let a = prev.speakerId
                let b = cur.speakerId
                if let a, let b, a != b {
                    let tA = ticksForTiming(prev)
                    let tB = ticksForTiming(cur)
                    let ta = midSeconds(startTicks: tA.start, endTicks: tA.end)
                    let tb = midSeconds(startTicks: tB.start, endTicks: tB.end)
                    let start = min(ta, tb)
                    let end = max(ta, tb)

                    let conf = ConfidenceRecordV1.evidence(
                        score: 0.70,
                        sources: [.audio],
                        reasons: [.cluster_boundary],
                        evidenceRefs: [
                            .interval("transcript.words", startSeconds: start, endSeconds: end)
                        ]
                    )
                    events.append(
                        TemporalEventV1(
                            kind: .speakerChange,
                            startSeconds: start,
                            endSeconds: end,
                            fromSpeakerId: a,
                            toSpeakerId: b,
                            confidence: conf,
                            confidenceLevel: .inferred,
                            provenance: [
                                .interval("transcript.words", startSeconds: start, endSeconds: end)
                            ]
                        )
                    )
                }
                prev = cur
            }
        }

        // Deterministic ordering.
        events.sort {
            if $0.startSeconds != $1.startSeconds { return $0.startSeconds < $1.startSeconds }
            if $0.endSeconds != $1.endSeconds { return $0.endSeconds < $1.endSeconds }
            if $0.kind.rawValue != $1.kind.rawValue { return $0.kind.rawValue < $1.kind.rawValue }
            let a = $0.trackId?.uuidString ?? ""
            let b = $1.trackId?.uuidString ?? ""
            if a != b { return a < b }
            let c = $0.fromSpeakerId ?? ""
            let d = $1.fromSpeakerId ?? ""
            if c != d { return c < d }
            return ($0.toSpeakerId ?? "") < ($1.toSpeakerId ?? "")
        }

        return TemporalContextV1(
            analyzedSeconds: sensors.summary.analyzedSeconds,
            events: events
        )
    }
}

private extension EvidenceRefV1 {
    static func interval(_ id: String, startSeconds: Double, endSeconds: Double) -> EvidenceRefV1 {
        // We encode time window information as a metric pair for v1; provenance carries richer structure.
        EvidenceRefV1(kind: .interval, id: id, field: nil, value: nil)
    }
}
