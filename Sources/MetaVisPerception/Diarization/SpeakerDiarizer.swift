import Foundation
import MetaVisCore

/// Speaker diarization v1 (Sticky Fusion).
///
/// This is a deterministic heuristic that fuses:
/// - transcript word timing (ticks, 1/60000s)
/// - `MasterSensors` speech-like segments
/// - `MasterSensors` face tracks (deterministic `trackId` already produced by ingest)
public enum SpeakerDiarizer {

    public struct Options: Sendable, Equatable {
        /// Minimum confidence for a `.speechLike` segment to be considered.
        public var minSpeechConfidence: Double

        /// Hysteresis ratio required to switch away from the current speaker when both are plausible.
        ///
        /// Example: 1.15 means the new candidate must be at least 15% stronger.
        public var switchRatio: Double

        /// Small additive margin to avoid switching on tiny numeric differences.
        public var switchAdditive: Double

        public init(
            minSpeechConfidence: Double = 0.5,
            switchRatio: Double = 1.15,
            switchAdditive: Double = 0.005
        ) {
            self.minSpeechConfidence = minSpeechConfidence
            self.switchRatio = switchRatio
            self.switchAdditive = switchAdditive
        }
    }

    public struct SpeakerMapV1: Codable, Sendable, Equatable {
        public var schema: String
        public var createdAt: Date
        public var speakers: [Entry]

        public init(schema: String = "speaker_map.v1", createdAt: Date = Date(), speakers: [Entry]) {
            self.schema = schema
            self.createdAt = createdAt
            self.speakers = speakers
        }

        public struct Entry: Codable, Sendable, Equatable {
            public var speakerId: String
            public var speakerLabel: String
            public var firstSeenTimeTicks: Int64

            public init(speakerId: String, speakerLabel: String, firstSeenTimeTicks: Int64) {
                self.speakerId = speakerId
                self.speakerLabel = speakerLabel
                self.firstSeenTimeTicks = firstSeenTimeTicks
            }
        }
    }

    public struct Result: Sendable, Equatable {
        public var words: [TranscriptWordV1]
        public var speakerMap: SpeakerMapV1

        public init(words: [TranscriptWordV1], speakerMap: SpeakerMapV1) {
            self.words = words
            self.speakerMap = speakerMap
        }
    }

    public static func diarize(
        words: [TranscriptWordV1],
        sensors: MasterSensors,
        options: Options = Options()
    ) -> Result {
        guard !words.isEmpty else {
            return Result(words: words, speakerMap: SpeakerMapV1(speakers: []))
        }

        // Pre-filter speech-like segments for gating.
        let speechLike: [MasterSensors.AudioSegment] = sensors.audioSegments.filter { seg in
            seg.kind == .speechLike && seg.confidence >= options.minSpeechConfidence
        }

        // Fallback: if ingest couldn't confidently classify speech, still allow diarization
        // within any non-silence audio segment window (e.g. `.unknown` spanning the clip).
        let gateSegments: [MasterSensors.AudioSegment]
        if !speechLike.isEmpty {
            gateSegments = speechLike
        } else {
            gateSegments = sensors.audioSegments.filter { $0.kind != .silence }
        }

        // Video sample lookup window: half stride with a small minimum to tolerate drift.
        let stride = max(0.01, sensors.sampling.videoStrideSeconds)
        let sampleWindow = max(0.12, (stride / 2.0) + 0.02)

        func ticksForTiming(_ w: TranscriptWordV1) -> (start: Int64, end: Int64) {
            let start = w.timelineTimeTicks ?? w.sourceTimeTicks
            let end = w.timelineTimeEndTicks ?? w.sourceTimeEndTicks
            return (start: start, end: max(start, end))
        }

        func midSeconds(startTicks: Int64, endTicks: Int64) -> Double {
            let midTicks = startTicks + (max(Int64(0), endTicks - startTicks) / 2)
            return Double(midTicks) / 60000.0
        }

        func isInSpeech(_ t: Double) -> Bool {
            // If we have no usable audio segmentation, don't block diarization entirely.
            guard !gateSegments.isEmpty else { return true }

            for seg in gateSegments {
                if t >= seg.start && t < seg.end { return true }
            }
            return false
        }

        struct Candidate {
            var speakerId: String
            var score: Double
        }

        func candidates(at t: Double) -> [Candidate] {
            // Find nearest video sample.
            var bestSample: MasterSensors.VideoSample?
            var bestDt = Double.greatestFiniteMagnitude
            for s in sensors.videoSamples {
                let dt = abs(s.time - t)
                if dt < bestDt {
                    bestDt = dt
                    bestSample = s
                }
            }

            let faces: [MasterSensors.Face]
            if let sample = bestSample, bestDt <= sampleWindow {
                faces = sample.faces
            } else {
                faces = []
            }

            if faces.isEmpty {
                return [Candidate(speakerId: "OFFSCREEN", score: 1.0)]
            }

            func faceScore(_ f: MasterSensors.Face) -> Double {
                let r = f.rect
                let area = max(0.0, Double(r.width * r.height))
                let cx = Double(r.midX)
                let cy = Double(r.midY)
                let dx = cx - 0.5
                let dy = cy - 0.5
                let dist = sqrt(dx * dx + dy * dy) // 0..~0.707
                let center = max(0.0, 1.0 - (dist / 0.70710678))
                // Area dominates; center proximity is a weak tiebreaker.
                return area + (0.05 * center)
            }

            var out: [Candidate] = []
            out.reserveCapacity(faces.count)
            for f in faces {
                out.append(Candidate(speakerId: f.trackId.uuidString, score: faceScore(f)))
            }
            out.sort {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.speakerId < $1.speakerId
            }
            return out
        }

        func chooseSpeaker(previous: String?, candidates: [Candidate], options: Options) -> String? {
            guard let best = candidates.first else { return nil }
            guard let prev = previous else { return best.speakerId }

            if let prevCand = candidates.first(where: { $0.speakerId == prev }) {
                if best.speakerId == prev { return prev }
                // Stickiness: require meaningful dominance to switch.
                let threshold = (prevCand.score * options.switchRatio) + options.switchAdditive
                if best.score >= threshold {
                    return best.speakerId
                }
                return prev
            }

            return best.speakerId
        }

        var diarized = words
        diarized.reserveCapacity(words.count)

        var currentSpeakerId: String? = nil

        for i in diarized.indices {
            let timing = ticksForTiming(diarized[i])
            let t = midSeconds(startTicks: timing.start, endTicks: timing.end)

            // Speech gating: outside speechLike → leave unassigned.
            guard isInSpeech(t) else {
                diarized[i].speakerId = nil
                diarized[i].speakerLabel = nil
                continue
            }

            let c = candidates(at: t)
            let chosen = chooseSpeaker(previous: currentSpeakerId, candidates: c, options: options)
            diarized[i].speakerId = chosen
            // speakerLabel assigned after we compute deterministic mapping.
            diarized[i].speakerLabel = nil
            currentSpeakerId = chosen
        }

        // Build deterministic speaker label mapping by first appearance time.
        var firstSeenBySpeakerId: [String: Int64] = [:]
        firstSeenBySpeakerId.reserveCapacity(16)

        for w in diarized {
            guard let sid = w.speakerId else { continue }
            let timing = ticksForTiming(w)
            let mid = timing.start + (max(Int64(0), timing.end - timing.start) / 2)
            if let existing = firstSeenBySpeakerId[sid] {
                if mid < existing { firstSeenBySpeakerId[sid] = mid }
            } else {
                firstSeenBySpeakerId[sid] = mid
            }
        }

        let orderedSpeakerIds: [String] = firstSeenBySpeakerId
            .sorted { a, b in
                if a.value != b.value { return a.value < b.value }
                return a.key < b.key
            }
            .map { $0.key }

        var labelBySpeakerId: [String: String] = [:]
        labelBySpeakerId.reserveCapacity(orderedSpeakerIds.count)

        var tIndex = 1
        for sid in orderedSpeakerIds {
            if sid == "OFFSCREEN" {
                labelBySpeakerId[sid] = "OFFSCREEN"
            } else {
                labelBySpeakerId[sid] = "T\(tIndex)"
                tIndex += 1
            }
        }

        var entries: [SpeakerMapV1.Entry] = []
        entries.reserveCapacity(orderedSpeakerIds.count)
        for sid in orderedSpeakerIds {
            guard let first = firstSeenBySpeakerId[sid], let label = labelBySpeakerId[sid] else { continue }
            entries.append(.init(speakerId: sid, speakerLabel: label, firstSeenTimeTicks: first))
        }

        for i in diarized.indices {
            if let sid = diarized[i].speakerId {
                diarized[i].speakerLabel = labelBySpeakerId[sid]
            }
        }

        return Result(words: diarized, speakerMap: SpeakerMapV1(speakers: entries))
    }
}
