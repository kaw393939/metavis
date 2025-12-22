import Foundation
import MetaVisCore

public enum IdentityBindingGraphBuilder {
    public struct Options: Sendable {
        public var minSpeechConfidence: Double
        public var sampleWindowSeconds: Double
        public var minPosteriorForEdge: Double

        /// Maximum number of face candidates to consider per video sample.
        ///
        /// Rationale: relative-area filters alone can accidentally drop a legitimate second speaker
        /// (e.g. a farther subject in a 2-person interview). Keeping the top-K faces (by area)
        /// ensures binding has at least a chance to form distinct edges.
        public var maxFacesPerSample: Int

        /// Absolute minimum face box area (normalized 0..1 coords) for a face to participate in binding.
        public var minFaceArea: Double

        /// Per-frame relative face area filter: ignore faces with area < (maxFaceArea * minFaceAreaFractionOfMax).
        /// This removes tiny, always-present faces that tend to hijack center-weighted heuristics.
        public var minFaceAreaFractionOfMax: Double

        /// How much to use center proximity as a *tiebreak* (not a primary signal).
        /// Score is computed as: area * (1 + centerWeight * centerProximity)
        public var centerWeight: Double

        /// Additional multiplicative weight applied based on per-track face motion energy.
        /// Motion is computed deterministically from successive face-rect center deltas per track
        /// and normalized within the candidate set for the selected video sample.
        ///
        /// Score becomes:
        ///   area * (1 + centerWeight * centerProximity) * (1 + motionWeight * motionNorm)
        public var motionWeight: Double

        /// Time window (seconds) used to aggregate motion energy per track.
        /// A short window is more likely to correlate with near-term speaking activity than
        /// raw frame-to-frame jitter.
        public var motionWindowSeconds: Double

        /// Additional multiplicative weight applied based on per-track mouth activity.
        ///
        /// Mouth activity is computed deterministically from the absolute delta of
        /// `MasterSensors.Face.mouthOpenRatio` over a short window.
        ///
        /// Score becomes (when enabled):
        ///   ... * (1 + mouthActivityWeight * mouthNorm)
        public var mouthActivityWeight: Double

        /// Time window (seconds) used to aggregate mouth activity per track.
        public var mouthWindowSeconds: Double

        /// Additional multiplicative weight applied based on per-track mouth openness.
        ///
        /// This uses the instantaneous `MasterSensors.Face.mouthOpenRatio` at the selected sample time
        /// (normalized within the candidate set) as a lightweight visual speaking proxy.
        ///
        /// Score becomes (when enabled):
        ///   ... * (1 + mouthOpenWeight * mouthOpenNorm)
        public var mouthOpenWeight: Double

        /// When multiple speakers map to the same face track, penalize that track for the weaker speaker
        /// using a deterministic competition term based on other-speaker support.
        ///
        /// The penalty is applied as:
        ///   adjustedWeight = speakerWeight / (1 + competition) ^ exponent
        /// where competition = globalTrackWeight - speakerWeight.
        public var competitionPenaltyExponent: Double

        /// If the top two posteriors for a speaker are too close, treat the binding as ambiguous.
        /// This does not remove edges; it only adds an explicit reason code.
        public var minPosteriorGapForConfidentBinding: Double

        public init(
            minSpeechConfidence: Double = 0.30,
            sampleWindowSeconds: Double = 0.20,
            minPosteriorForEdge: Double = 0.20,
            competitionPenaltyExponent: Double = 1.2,
            minPosteriorGapForConfidentBinding: Double = 0.15
        ) {
            self.minSpeechConfidence = minSpeechConfidence
            self.sampleWindowSeconds = sampleWindowSeconds
            self.minPosteriorForEdge = minPosteriorForEdge
            self.competitionPenaltyExponent = competitionPenaltyExponent
            self.minPosteriorGapForConfidentBinding = minPosteriorGapForConfidentBinding

            self.maxFacesPerSample = 2

            // Defaults tuned to be conservative on common talking-head footage:
            // keep two main faces, drop tiny persistent faces.
            self.minFaceArea = 0.0
            self.minFaceAreaFractionOfMax = 0.05
            self.centerWeight = 0.20

            // Conservative: motion can help resolve who is speaking in ambiguous clips,
            // but should not override area dominance.
            self.motionWeight = 0.35

            // Short-window motion aggregation (matches typical sensor stride defaults).
            self.motionWindowSeconds = 0.75

            // Mouth activity can be a strong disambiguator when two faces are on-screen.
            // Keep conservative defaults; it should help, not override, geometry.
            self.mouthActivityWeight = 0.60
            self.mouthWindowSeconds = 0.75

            // Prefer instantaneous mouth openness (word-time aligned) by default.
            self.mouthOpenWeight = 1.20
        }
    }

    public static func build(
        sensors: MasterSensors,
        words: [TranscriptWordV1],
        options: Options = Options()
    ) -> IdentityBindingGraphV1 {
        // Gate to speech-like audio when available; fall back to non-silence segments.
        let speechLike = sensors.audioSegments.filter { $0.kind == .speechLike && $0.confidence >= options.minSpeechConfidence }
        let gateSegments: [MasterSensors.AudioSegment] = !speechLike.isEmpty ? speechLike : sensors.audioSegments.filter { $0.kind != .silence }

        func isInSpeech(_ t: Double) -> Bool {
            guard !gateSegments.isEmpty else { return true }
            for seg in gateSegments {
                if t >= seg.start && t < seg.end { return true }
            }
            return false
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

        func faceArea(_ f: MasterSensors.Face) -> Double {
            let r = f.rect
            return max(0.0, Double(r.width * r.height))
        }

        func centerProximity(_ f: MasterSensors.Face) -> Double {
            let r = f.rect
            let cx = Double(r.midX)
            let cy = Double(r.midY)
            let dx = cx - 0.5
            let dy = cy - 0.5
            let dist = sqrt(dx * dx + dy * dy)
            return max(0.0, 1.0 - (dist / 0.70710678))
        }

        func faceScore(_ f: MasterSensors.Face) -> Double {
            // Area must dominate. Center is only a small multiplicative tiebreak.
            let area = faceArea(f)
            let c = centerProximity(f)
            return area * (1.0 + (options.centerWeight * c))
        }

        func faceCenter(_ f: MasterSensors.Face) -> (x: Double, y: Double) {
            let r = f.rect
            return (x: Double(r.midX), y: Double(r.midY))
        }

        // Precompute raw per-sample motion energy for each track.
        // Motion is derived deterministically from rect deltas (center + size), which tends to be
        // more sensitive than center-only deltas on talking-head footage.
        // IMPORTANT: computed in sample order and face trackId order to preserve determinism.
        var rawMotionBySampleIndex: [[UUID: Double]] = Array(repeating: [:], count: sensors.videoSamples.count)
        var lastRectByTrack: [UUID: CGRect] = [:]
        if !sensors.videoSamples.isEmpty {
            for (i, s) in sensors.videoSamples.enumerated() {
                let faces = s.faces.sorted { a, b in a.trackId.uuidString < b.trackId.uuidString }
                for f in faces {
                    let r = f.rect
                    if let prev = lastRectByTrack[f.trackId] {
                        let dx = Double(r.midX - prev.midX)
                        let dy = Double(r.midY - prev.midY)
                        let dw = Double(r.width - prev.width)
                        let dh = Double(r.height - prev.height)
                        // Size deltas get a small weight; helps capture detector jitter during speech.
                        let sizeWeight = 0.5
                        let d = sqrt((dx * dx) + (dy * dy) + (sizeWeight * ((dw * dw) + (dh * dh))))
                        rawMotionBySampleIndex[i][f.trackId] = d
                    } else {
                        rawMotionBySampleIndex[i][f.trackId] = 0.0
                    }
                    lastRectByTrack[f.trackId] = r
                }
            }
        }

        // Aggregate raw motion into a short-window energy per sample.
        // This is computed only for tracks present at each sample, keeping it deterministic.
        var motionEnergyBySampleIndex: [[UUID: Double]] = Array(repeating: [:], count: sensors.videoSamples.count)
        if options.motionWeight > 0.0, options.motionWindowSeconds > 0.0, sensors.videoSamples.count > 1 {
            for i in sensors.videoSamples.indices {
                let t = sensors.videoSamples[i].time
                let windowStart = t - options.motionWindowSeconds
                for (trackId, _) in rawMotionBySampleIndex[i] {
                    var sum = 0.0
                    var j = i
                    while j >= 0 {
                        let tj = sensors.videoSamples[j].time
                        if tj < windowStart { break }
                        sum += (rawMotionBySampleIndex[j][trackId] ?? 0.0)
                        if j == 0 { break }
                        j -= 1
                    }
                    motionEnergyBySampleIndex[i][trackId] = sum
                }
            }
        } else {
            motionEnergyBySampleIndex = rawMotionBySampleIndex
        }

        // Precompute raw per-sample mouth delta for each track from mouthOpenRatio.
        // IMPORTANT: computed in sample order and face trackId order to preserve determinism.
        var rawMouthDeltaBySampleIndex: [[UUID: Double]] = Array(repeating: [:], count: sensors.videoSamples.count)
        var lastMouthByTrack: [UUID: Double] = [:]
        if options.mouthActivityWeight > 0.0, !sensors.videoSamples.isEmpty {
            for (i, s) in sensors.videoSamples.enumerated() {
                let faces = s.faces.sorted { a, b in a.trackId.uuidString < b.trackId.uuidString }
                for f in faces {
                    guard let m = f.mouthOpenRatio, m.isFinite else {
                        rawMouthDeltaBySampleIndex[i][f.trackId] = 0.0
                        continue
                    }
                    if let prev = lastMouthByTrack[f.trackId], prev.isFinite {
                        rawMouthDeltaBySampleIndex[i][f.trackId] = abs(m - prev)
                    } else {
                        rawMouthDeltaBySampleIndex[i][f.trackId] = 0.0
                    }
                    lastMouthByTrack[f.trackId] = m
                }
            }
        }

        // Aggregate mouth deltas into a short-window energy per sample.
        var mouthEnergyBySampleIndex: [[UUID: Double]] = Array(repeating: [:], count: sensors.videoSamples.count)
        if options.mouthActivityWeight > 0.0, options.mouthWindowSeconds > 0.0, sensors.videoSamples.count > 1 {
            for i in sensors.videoSamples.indices {
                let t = sensors.videoSamples[i].time
                let windowStart = t - options.mouthWindowSeconds
                for (trackId, _) in rawMouthDeltaBySampleIndex[i] {
                    var sum = 0.0
                    var j = i
                    while j >= 0 {
                        let tj = sensors.videoSamples[j].time
                        if tj < windowStart { break }
                        sum += (rawMouthDeltaBySampleIndex[j][trackId] ?? 0.0)
                        if j == 0 { break }
                        j -= 1
                    }
                    mouthEnergyBySampleIndex[i][trackId] = sum
                }
            }
        } else {
            mouthEnergyBySampleIndex = rawMouthDeltaBySampleIndex
        }

        // Per-sample instantaneous mouth openness by track.
        var mouthOpenBySampleIndex: [[UUID: Double]] = Array(repeating: [:], count: sensors.videoSamples.count)
        if options.mouthOpenWeight > 0.0, !sensors.videoSamples.isEmpty {
            // Compute a per-track baseline (median) to reduce camera-distance / face-size bias.
            var samplesByTrack: [UUID: [Double]] = [:]
            for s in sensors.videoSamples {
                for f in s.faces {
                    if let m = f.mouthOpenRatio, m.isFinite {
                        samplesByTrack[f.trackId, default: []].append(max(0.0, min(1.0, m)))
                    }
                }
            }

            var medianByTrack: [UUID: Double] = [:]
            medianByTrack.reserveCapacity(samplesByTrack.count)
            for trackId in samplesByTrack.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                var arr = samplesByTrack[trackId] ?? []
                guard !arr.isEmpty else { continue }
                arr.sort()
                let mid = arr.count / 2
                let med: Double
                if arr.count % 2 == 1 {
                    med = arr[mid]
                } else {
                    med = 0.5 * (arr[max(0, mid - 1)] + arr[mid])
                }
                medianByTrack[trackId] = med
            }

            for (i, s) in sensors.videoSamples.enumerated() {
                let faces = s.faces.sorted { a, b in a.trackId.uuidString < b.trackId.uuidString }
                for f in faces {
                    if let m = f.mouthOpenRatio, m.isFinite {
                        let raw = max(0.0, min(1.0, m))
                        let baseline = medianByTrack[f.trackId] ?? 0.0
                        // Only count "above-baseline" openness as speaking evidence.
                        mouthOpenBySampleIndex[i][f.trackId] = max(0.0, raw - baseline)
                    } else {
                        mouthOpenBySampleIndex[i][f.trackId] = 0.0
                    }
                }
            }
        }

        func nearestSample(at t: Double) -> (sample: MasterSensors.VideoSample?, index: Int?, dt: Double) {
            var best: MasterSensors.VideoSample?
            var bestIndex: Int?
            var bestDt = Double.greatestFiniteMagnitude
            for (i, s) in sensors.videoSamples.enumerated() {
                let dt = abs(s.time - t)
                if dt < bestDt {
                    bestDt = dt
                    best = s
                    bestIndex = i
                }
            }
            return (best, bestIndex, bestDt)
        }

        // speakerId -> trackId -> weight
        var weights: [String: [UUID: Double]] = [:]
        var labels: [String: String] = [:]
        var totalBySpeaker: [String: Double] = [:]

        let sortedWords = words.sorted {
            let a = $0.timelineTimeTicks ?? $0.sourceTimeTicks
            let b = $1.timelineTimeTicks ?? $1.sourceTimeTicks
            if a != b { return a < b }
            return $0.wordId < $1.wordId
        }

        for w in sortedWords {
            guard let speakerId = w.speakerId else { continue }
            labels[speakerId] = w.speakerLabel

            let timing = ticksForTiming(w)
            let t = midSeconds(startTicks: timing.start, endTicks: timing.end)
            guard isInSpeech(t) else { continue }

            let (sample, sampleIndex, dt) = nearestSample(at: t)
            // Float rounding can put a value that is conceptually on the boundary (e.g. 0.2)
            // slightly above it (e.g. 0.20000000000000018). Use a tiny epsilon to avoid
            // dropping legitimate matches.
            let windowEps = 1e-9
            guard let sample, let sampleIndex, dt <= (options.sampleWindowSeconds + windowEps) else { continue }
            guard !sample.faces.isEmpty else { continue }

            // Candidate selection (deterministic):
            // 1) apply an absolute min area (if any)
            // 2) sort by area desc (tie: trackId)
            // 3) keep the top-K faces
            // 4) optionally drop truly tiny faces relative to the max (but never below 1 candidate)
            let faces = sample.faces.filter { faceArea($0) >= options.minFaceArea }
            guard !faces.isEmpty else { continue }

            let sortedFaces = faces.sorted { a, b in
                let aa = faceArea(a)
                let bb = faceArea(b)
                if aa != bb { return aa > bb }
                return a.trackId.uuidString < b.trackId.uuidString
            }

            let k = max(1, min(options.maxFacesPerSample, sortedFaces.count))
            var candidates = Array(sortedFaces.prefix(k))

            // Additional guard: if the selected second face is *extremely* small relative to the max,
            // drop it to reduce hijacking by persistent tiny faces.
            if candidates.count > 1 {
                let maxArea = faceArea(candidates[0])
                let relMin = maxArea * max(0.0, min(1.0, options.minFaceAreaFractionOfMax))
                // Only drop down to 1 candidate.
                candidates = candidates.filter { faceArea($0) >= relMin }
                if candidates.isEmpty {
                    candidates = [sortedFaces[0]]
                }
            }

            // Candidate-local motion normalization (keeps it scale-free).
            let rawMotion = motionEnergyBySampleIndex[sampleIndex]
            var maxMotion = 0.0
            if options.motionWeight > 0.0 {
                for f in candidates {
                    maxMotion = max(maxMotion, rawMotion[f.trackId] ?? 0.0)
                }
            }


            // Candidate-local mouth activity normalization (keeps it scale-free).
            let rawMouth = mouthEnergyBySampleIndex[sampleIndex]
            var maxMouth = 0.0
            if options.mouthActivityWeight > 0.0 {
                for f in candidates {
                    maxMouth = max(maxMouth, rawMouth[f.trackId] ?? 0.0)
                }
            }

            // Candidate-local mouth openness normalization.
            let rawMouthOpen = mouthOpenBySampleIndex.isEmpty ? [:] : mouthOpenBySampleIndex[sampleIndex]
            var maxMouthOpen = 0.0
            if options.mouthOpenWeight > 0.0 {
                for f in candidates {
                    maxMouthOpen = max(maxMouthOpen, rawMouthOpen[f.trackId] ?? 0.0)
                }
            }

            func faceScoreWithVisualCues(_ f: MasterSensors.Face) -> Double {
                var s = faceScore(f)
                if options.motionWeight > 0.0, maxMotion > 0.000001 {
                    let m = max(0.0, (rawMotion[f.trackId] ?? 0.0) / maxMotion)
                    s *= (1.0 + (options.motionWeight * m))
                }
                if options.mouthActivityWeight > 0.0, maxMouth > 0.000001 {
                    let m = max(0.0, (rawMouth[f.trackId] ?? 0.0) / maxMouth)
                    s *= (1.0 + (options.mouthActivityWeight * m))
                }
                if options.mouthOpenWeight > 0.0, maxMouthOpen > 0.000001 {
                    let m = max(0.0, (rawMouthOpen[f.trackId] ?? 0.0) / maxMouthOpen)
                    s *= (1.0 + (options.mouthOpenWeight * m))
                }
                return s
            }

            // Soft evidence accumulation (deterministic): instead of winner-take-all selecting one face,
            // distribute a per-word evidence budget across candidates by normalized score.
            //
            // This prevents pathological cases where a second speaker ends up with only one candidate edge
            // (causing posterior=1.0 on a highly contested track), which then blocks one-to-one assignment.
            var sumScores = 0.0
            var maxScore = 0.0
            var scored: [(trackId: UUID, score: Double)] = []
            scored.reserveCapacity(candidates.count)
            for f in candidates {
                let s = max(0.000001, faceScoreWithVisualCues(f))
                sumScores += s
                maxScore = max(maxScore, s)
                scored.append((trackId: f.trackId, score: s))
            }
            guard sumScores > 0.000001 else { continue }

            // Confidence strength for this word-time: if the best face is only barely better than others,
            // treat the visual evidence as weaker.
            let strength = max(0.0, min(1.0, maxScore / sumScores))
            for item in scored {
                let frac = item.score / sumScores
                weights[speakerId, default: [:]][item.trackId, default: 0.0] += (strength * frac)
            }
            totalBySpeaker[speakerId, default: 0.0] += strength
        }

        // Emit edges with posteriors.
        var edges: [IdentityBindingEdgeV1] = []
        edges.reserveCapacity(16)

        // Track competition across speakers.
        // IMPORTANT: accumulate in a deterministic order to preserve byte-identical outputs.
        var globalByTrack: [UUID: Double] = [:]
        for speakerId in weights.keys.sorted() {
            let wmap = weights[speakerId] ?? [:]
            for trackId in wmap.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                globalByTrack[trackId, default: 0.0] += (wmap[trackId] ?? 0.0)
            }
        }

        for speakerId in weights.keys.sorted() {
            let wmap = weights[speakerId] ?? [:]
            let total = totalBySpeaker[speakerId] ?? 0.0
            guard total > 0.000001 else { continue }

            // Determine posteriors using a symmetric association score to discourage
            // multiple speakers collapsing onto one dominant face track.
            //
            // Intuition:
            // - P(track | speaker) alone favors whichever face is biggest/most central.
            // - Multiplying by P(speaker | track) penalizes tracks that are "claimed" by other speakers.
            //
            // This remains deterministic and still produces a proper per-speaker posterior distribution.
            let adjusted: [(trackId: UUID, weight: Double, posteriorRaw: Double)] = wmap
                .keys
                .sorted(by: { $0.uuidString < $1.uuidString })
                .map { trackId in
                    let w = wmap[trackId] ?? 0.0
                    let global = max(0.000001, globalByTrack[trackId] ?? 0.0)
                    let pTrackGivenSpeaker = w / total
                    let pSpeakerGivenTrack = w / global
                    // Association score in [0,1] (roughly), higher when a speaker both
                    // (a) frequently selects the track and (b) dominates that track globally.
                    // Emphasize exclusivity: penalize tracks that are more strongly claimed by
                    // other speakers by sharpening P(speaker | track).
                    let exclusivityPower = 2.0
                    var assoc = pTrackGivenSpeaker * pow(max(0.0, pSpeakerGivenTrack), exclusivityPower)

                    // Optional sharpening: when enabled, raise association to an exponent.
                    // This helps make clear winners more decisive without changing rank order.
                    if options.competitionPenaltyExponent > 0.0 {
                        assoc = pow(max(0.0, assoc), max(0.000001, options.competitionPenaltyExponent))
                    }

                    return (trackId: trackId, weight: max(0.0, assoc), posteriorRaw: pTrackGivenSpeaker)
                }

            let sumAdj = adjusted.reduce(0.0) { $0 + $1.weight }
            guard sumAdj > 0.000001 else { continue }

            let posteriors: [(trackId: UUID, posterior: Double)] = adjusted
                .map { (trackId: $0.trackId, posterior: $0.weight / sumAdj) }
                .sorted { a, b in
                    if a.posterior != b.posterior { return a.posterior > b.posterior }
                    return a.trackId.uuidString < b.trackId.uuidString
                }

            let top = posteriors.first?.posterior ?? 0.0
            let second = posteriors.dropFirst().first?.posterior ?? 0.0
            let isAmbiguous = (top - second) < options.minPosteriorGapForConfidentBinding

            for (trackId, p) in posteriors {
                guard p >= options.minPosteriorForEdge else { continue }

                // Best-effort personId lookup (stable and deterministic).
                let personId: String? = {
                    for s in sensors.videoSamples {
                        if let f = s.faces.first(where: { $0.trackId == trackId }) {
                            return f.personId
                        }
                    }
                    return nil
                }()

                var reasons: [ReasonCodeV1] = []
                if p < 0.70 || isAmbiguous { reasons.append(.speaker_binding_missing) }

                let conf = ConfidenceRecordV1.evidence(
                    score: Float(max(0.0, min(1.0, p))),
                    sources: [.fused],
                    reasons: reasons,
                    evidenceRefs: [
                        .metric("binding.posterior", value: p),
                        .metric("binding.supportWeight", value: wmap[trackId] ?? 0.0),
                        .metric("binding.totalWeight", value: total),
                        .metric("binding.globalTrackWeight", value: globalByTrack[trackId] ?? 0.0),
                        .metric("binding.sampleWindowSeconds", value: options.sampleWindowSeconds),
                        .metric("binding.motionWeight", value: options.motionWeight),
                        .metric("binding.motionWindowSeconds", value: options.motionWindowSeconds),
                        .metric("binding.mouthActivityWeight", value: options.mouthActivityWeight),
                        .metric("binding.mouthWindowSeconds", value: options.mouthWindowSeconds),
                        .metric("binding.mouthOpenWeight", value: options.mouthOpenWeight),
                        .metric("binding.centerWeight", value: options.centerWeight)
                    ]
                )

                edges.append(
                    IdentityBindingEdgeV1(
                        speakerId: speakerId,
                        speakerLabel: labels[speakerId],
                        trackId: trackId,
                        personId: personId,
                        posterior: p,
                        confidence: conf,
                        confidenceLevel: .inferred,
                        provenance: [
                            .init(kind: .signal, id: "MasterSensors.videoSamples.faces.trackId"),
                            .init(kind: .signal, id: "transcript.words.speakerId")
                        ]
                    )
                )
            }
        }

        // Deterministic ordering.
        edges.sort {
            if $0.speakerId != $1.speakerId { return $0.speakerId < $1.speakerId }
            if $0.posterior != $1.posterior { return $0.posterior > $1.posterior }
            return $0.trackId.uuidString < $1.trackId.uuidString
        }

        return IdentityBindingGraphV1(
            analyzedSeconds: sensors.summary.analyzedSeconds,
            bindings: edges
        )
    }
}
