import Foundation
import MetaVisCore

public enum AudioEmbeddingSpeakerDiarizer {

    public struct Options: Sendable, Equatable {
        public var windowSeconds: Double
        public var hopSeconds: Double
        public var cooccurrenceThreshold: Double
        public var clusterSimilarityThreshold: Float
        public var minWindowRMS: Float

        public init(
            windowSeconds: Double = 3.0,
            hopSeconds: Double = 0.5,
            cooccurrenceThreshold: Double = 0.8,
            clusterSimilarityThreshold: Float = 0.80,
            minWindowRMS: Float = 0
        ) {
            self.windowSeconds = windowSeconds
            self.hopSeconds = hopSeconds
            self.cooccurrenceThreshold = cooccurrenceThreshold
            self.clusterSimilarityThreshold = clusterSimilarityThreshold
            self.minWindowRMS = minWindowRMS
        }
    }

    public struct Result: Sendable, Equatable {
        public var words: [TranscriptWordV1]
        public var speakerMap: SpeakerDiarizer.SpeakerMapV1

        public init(words: [TranscriptWordV1], speakerMap: SpeakerDiarizer.SpeakerMapV1) {
            self.words = words
            self.speakerMap = speakerMap
        }
    }

    public static func diarize(
        words: [TranscriptWordV1],
        sensors: MasterSensors,
        movieURL: URL,
        embeddingModel: any SpeakerEmbeddingModel,
        options: Options = Options()
    ) throws -> Result {
        guard !words.isEmpty else {
            return Result(words: words, speakerMap: .init(speakers: []))
        }

        // 1) Read mono audio at model sample rate.
        let audio = try AudioPCMExtractor.readMonoFloat32(
            movieURL: movieURL,
            startSeconds: 0,
            durationSeconds: min(sensors.source.durationSeconds, sensors.sampling.audioAnalyzeSeconds),
            targetSampleRate: embeddingModel.sampleRate,
            maxSamples: Int(embeddingModel.sampleRate * 60.0 * 30.0)
        )

        // 2) Determine gating segments: prefer speechLike if present; otherwise non-silence.
        let speechLike = sensors.audioSegments.filter { $0.kind == .speechLike }
        let gateSegments: [MasterSensors.AudioSegment]
        if !speechLike.isEmpty {
            gateSegments = speechLike
        } else {
            gateSegments = sensors.audioSegments.filter { $0.kind != .silence }
        }

        // If sensor gating is too broad (e.g., a single non-silence segment spanning the clip),
        // refine it using transcript word timings so we don't embed long non-speech regions.
        // This reduces spurious clusters in multi-scene fixtures.
        let refinedGateSegments: [MasterSensors.AudioSegment]
        if gateSegments.count == 1,
           let only = gateSegments.first,
           (only.end - only.start) >= min(8.0, sensors.source.durationSeconds * 0.75),
           words.count >= 8 {
            let padding: Double = 0.5
            struct Seg { var start: Double; var end: Double }
            var segs: [Seg] = []
            segs.reserveCapacity(min(64, words.count))

            func wordSeconds(_ w: TranscriptWordV1) -> (start: Double, end: Double) {
                let st = Double(w.timelineTimeTicks ?? w.sourceTimeTicks) / 60000.0
                let et = Double(w.timelineTimeEndTicks ?? w.sourceTimeEndTicks) / 60000.0
                let s = min(st, et)
                let e = max(st, et)
                return (s, e)
            }

            for w in words {
                let t = wordSeconds(w)
                let s = max(0.0, t.start - padding)
                let e = min(sensors.source.durationSeconds, t.end + padding)
                if e > s { segs.append(Seg(start: s, end: e)) }
            }

            segs.sort { a, b in
                if a.start != b.start { return a.start < b.start }
                return a.end < b.end
            }

            // Merge overlapping.
            var merged: [Seg] = []
            merged.reserveCapacity(segs.count)
            for s in segs {
                if var last = merged.last, s.start <= last.end {
                    last.end = max(last.end, s.end)
                    merged[merged.count - 1] = last
                } else {
                    merged.append(s)
                }
            }

            refinedGateSegments = merged.map { seg in
                MasterSensors.AudioSegment(
                    start: seg.start,
                    end: seg.end,
                    kind: .speechLike,
                    confidence: 1.0,
                    rmsDB: nil,
                    spectralCentroidHz: nil,
                    dominantFrequencyHz: nil,
                    spectralFlatness: nil
                )
            }
        } else {
            refinedGateSegments = gateSegments
        }

        func isGatedIn(_ t: Double) -> Bool {
            guard !refinedGateSegments.isEmpty else { return true }
            for seg in refinedGateSegments {
                if t >= seg.start && t < seg.end { return true }
            }
            return false
        }

        // 3) Generate fixed windows and embeddings.
        let sr = embeddingModel.sampleRate
        let windowSamples = Int((options.windowSeconds * sr).rounded(.toNearestOrAwayFromZero))
        let hopSamples = max(1, Int((options.hopSeconds * sr).rounded(.toNearestOrAwayFromZero)))

        let isShortWindowModel = options.windowSeconds <= 3.5

        // Precompute a Hann taper for short-window models to reduce edge mixing.
        // (We avoid importing Accelerate here; this stays tiny and deterministic.)
        let taper: [Float]? = {
            guard isShortWindowModel, windowSamples >= 2 else { return nil }
            var w: [Float] = []
            w.reserveCapacity(windowSamples)
            let denom = Double(max(1, windowSamples - 1))
            for i in 0..<windowSamples {
                let x = Double(i) / denom
                let v = 0.5 - 0.5 * cos(2.0 * Double.pi * x)
                w.append(Float(v))
            }
            return w
        }()

        var windows: [AudioSpeakerClusterer.WindowEmbedding] = []
        if windowSamples > 0, audio.count >= 1 {
            // Deterministic uniform sliding windows.
            // If `minWindowRMS` is enabled, skip low-energy windows and avoid tail padding,
            // which can otherwise create spurious extra clusters.
            let requiresFullWindow = options.minWindowRMS > 0

            func rms(of buf: [Float]) -> Float {
                guard !buf.isEmpty else { return 0 }
                var sumSq: Float = 0
                for x in buf { sumSq += x * x }
                return sqrt(sumSq / Float(buf.count))
            }

            var start = 0
            while start < audio.count {
                if requiresFullWindow, (start + windowSamples) > audio.count { break }

                let midSeconds = (Double(start) + (Double(windowSamples) * 0.5)) / sr
                if isGatedIn(midSeconds) {
                    var buf = [Float](repeating: 0, count: windowSamples)
                    let copyCount = min(windowSamples, max(0, audio.count - start))
                    if copyCount > 0 {
                        buf[0..<copyCount] = audio[start..<(start + copyCount)]
                    }

                    if options.minWindowRMS > 0 {
                        let r = rms(of: buf)
                        if r < options.minWindowRMS {
                            start += hopSamples
                            continue
                        }
                    }

                    if let taper {
                        for i in 0..<windowSamples {
                            buf[i] *= taper[i]
                        }
                    }

                    let emb = try embeddingModel.embed(windowedMonoPCM: buf)
                    windows.append(.init(midSeconds: midSeconds, embeddingUnit: emb))
                }
                start += hopSamples
            }
        }

        // 4) Cluster embeddings.
        let clusterer = AudioSpeakerClusterer()
        var assignments = clusterer.cluster(
            windows,
            options: .init(similarityThreshold: options.clusterSimilarityThreshold)
        )

        // 4b) Post-merge small clusters to reduce over-fragmentation.
        // The online centroid assignment can splinter a single speaker into many tiny clusters.
        // We conservatively merge only when:
        // - cosine similarity is high, and
        // - at least one cluster is "small" relative to the total.
        if assignments.count >= 3 {
            struct ClusterStats {
                var sum: [Float]
                var count: Int
            }

            var stats: [String: ClusterStats] = [:]
            stats.reserveCapacity(8)

            for (w, a) in zip(windows, assignments) {
                if var s = stats[a.clusterId] {
                    for i in 0..<s.sum.count { s.sum[i] += w.embeddingUnit[i] }
                    s.count += 1
                    stats[a.clusterId] = s
                } else {
                    stats[a.clusterId] = ClusterStats(sum: w.embeddingUnit, count: 1)
                }
            }

            func centroidUnit(for clusterId: String) -> [Float]? {
                guard let s = stats[clusterId] else { return nil }
                return SpeakerEmbeddingMath.l2Normalize(s.sum)
            }

            let total = assignments.count
            let smallMax: Int
            let mergeThreshold: Float
            if isShortWindowModel {
                // Short-window models can over-split a single speaker into a few mid-sized clusters.
                // Allow merging when one side is "small" (relative to the clip) and similarity is very high.
                smallMax = max(4, Int((Double(total) * 0.50).rounded(.toNearestOrAwayFromZero)))
                mergeThreshold = max(0.0, options.clusterSimilarityThreshold - 0.05)
            } else {
                smallMax = max(2, Int((Double(total) * 0.20).rounded(.toNearestOrAwayFromZero)))
                mergeThreshold = max(0.0, options.clusterSimilarityThreshold - 0.10)
            }

            var parent: [String: String] = [:]
            parent.reserveCapacity(stats.count)

            func find(_ x: String) -> String {
                var cur = x
                while let p = parent[cur], p != cur { cur = p }
                return cur
            }

            func union(_ a: String, _ b: String) {
                let ra = find(a)
                let rb = find(b)
                guard ra != rb else { return }
                let ca = stats[ra]?.count ?? 0
                let cb = stats[rb]?.count ?? 0
                // Merge smaller into larger; deterministic tie-break by id.
                let into: String
                let from: String
                if ca > cb {
                    into = ra; from = rb
                } else if cb > ca {
                    into = rb; from = ra
                } else {
                    into = min(ra, rb)
                    from = (into == ra) ? rb : ra
                }
                parent[from] = into
                parent[into] = into

                // Update stats for the destination centroid.
                if var dst = stats[into], let src = stats[from] {
                    for i in 0..<dst.sum.count { dst.sum[i] += src.sum[i] }
                    dst.count += src.count
                    stats[into] = dst
                }
            }

            // Initialize parent pointers.
            for k in stats.keys { parent[k] = k }

            var didMerge = true
            while didMerge {
                didMerge = false

                let clusterIds = stats.keys.sorted()
                outer: for i in 0..<clusterIds.count {
                    for j in (i + 1)..<clusterIds.count {
                        let a = find(clusterIds[i])
                        let b = find(clusterIds[j])
                        if a == b { continue }
                        guard let sa = stats[a], let sb = stats[b] else { continue }
                        let small = min(sa.count, sb.count)
                        if small > smallMax { continue }
                        guard let ca = centroidUnit(for: a), let cb = centroidUnit(for: b) else { continue }
                        let sim = SpeakerEmbeddingMath.cosineSimilarityUnitVectors(ca, cb)
                        if sim >= mergeThreshold {
                            union(a, b)
                            didMerge = true
                            break outer
                        }
                    }
                }
            }

            // Remap cluster ids.
            if parent.values.contains(where: { $0 != parent[$0] }) || parent.keys.contains(where: { find($0) != $0 }) {
                for idx in assignments.indices {
                    let root = find(assignments[idx].clusterId)
                    assignments[idx].clusterId = root
                }
            }
        }

        // 4c) Collapse high-similarity splinters (size-independent).
        // Some models (notably short-window waveform embeddings) can splinter a single speaker into
        // multiple mid-sized clusters. HAC can preserve these splinters at higher thresholds.
        // Merge only when centroid similarity is *very* high, so distinct speakers stay separate.
        if assignments.count >= 3 {
            struct ClusterStats {
                var sum: [Float]
                var count: Int
                var firstMid: Double
            }

            func buildStats() -> [String: ClusterStats] {
                var stats: [String: ClusterStats] = [:]
                stats.reserveCapacity(8)
                for (w, a) in zip(windows, assignments) {
                    if var s = stats[a.clusterId] {
                        for i in 0..<s.sum.count { s.sum[i] += w.embeddingUnit[i] }
                        s.count += 1
                        s.firstMid = min(s.firstMid, a.midSeconds)
                        stats[a.clusterId] = s
                    } else {
                        stats[a.clusterId] = ClusterStats(sum: w.embeddingUnit, count: 1, firstMid: a.midSeconds)
                    }
                }
                return stats
            }

            let highMergeThreshold: Float = isShortWindowModel ? 0.88 : 0.92

            var didMerge = true
            while didMerge {
                didMerge = false

                let stats = buildStats()
                let ids = stats.keys.sorted()
                guard ids.count >= 3 else { break }

                func centroidUnit(_ id: String) -> [Float]? {
                    guard let s = stats[id] else { return nil }
                    return SpeakerEmbeddingMath.l2Normalize(s.sum)
                }

                var bestPair: (a: String, b: String)? = nil
                var bestSim: Float = -1

                for i in 0..<(ids.count - 1) {
                    for j in (i + 1)..<ids.count {
                        guard let ca = centroidUnit(ids[i]), let cb = centroidUnit(ids[j]) else { continue }
                        let sim = SpeakerEmbeddingMath.cosineSimilarityUnitVectors(ca, cb)
                        if sim > bestSim {
                            bestSim = sim
                            bestPair = (a: ids[i], b: ids[j])
                        } else if sim == bestSim, let p = bestPair {
                            // Deterministic tie-break: earlier-first cluster wins.
                            let aFirst = min(stats[ids[i]]?.firstMid ?? 0, stats[ids[j]]?.firstMid ?? 0)
                            let pFirst = min(stats[p.a]?.firstMid ?? 0, stats[p.b]?.firstMid ?? 0)
                            if aFirst < pFirst {
                                bestPair = (a: ids[i], b: ids[j])
                            }
                        }
                    }
                }

                guard let pair = bestPair, bestSim >= highMergeThreshold else { break }

                let aFirst = stats[pair.a]?.firstMid ?? 0
                let bFirst = stats[pair.b]?.firstMid ?? 0
                let into: String
                let from: String
                if aFirst < bFirst {
                    into = pair.a
                    from = pair.b
                } else if bFirst < aFirst {
                    into = pair.b
                    from = pair.a
                } else {
                    into = min(pair.a, pair.b)
                    from = (into == pair.a) ? pair.b : pair.a
                }

                for idx in assignments.indices {
                    if assignments[idx].clusterId == from {
                        assignments[idx].clusterId = into
                    }
                }
                didMerge = true
            }
        }

        // 5) Map clusters to face tracks using co-occurrence.
        let clusterToSpeakerId = mapClustersToSpeakers(assignments: assignments, sensors: sensors, threshold: options.cooccurrenceThreshold)

        // 6) Assign speaker ids to words by nearest window mid.
        var diarized = words
        diarized.reserveCapacity(words.count)

        func ticksForTiming(_ w: TranscriptWordV1) -> (start: Int64, end: Int64) {
            let start = w.timelineTimeTicks ?? w.sourceTimeTicks
            let end = w.timelineTimeEndTicks ?? w.sourceTimeEndTicks
            return (start: start, end: max(start, end))
        }

        func midSeconds(startTicks: Int64, endTicks: Int64) -> Double {
            let midTicks = startTicks + (max(Int64(0), endTicks - startTicks) / 2)
            return Double(midTicks) / 60000.0
        }

        func nearestCluster(at t: Double) -> String? {
            guard !assignments.isEmpty else { return nil }
            var best = assignments[0]
            var bestDt = abs(best.midSeconds - t)
            for a in assignments.dropFirst() {
                let dt = abs(a.midSeconds - t)
                if dt < bestDt {
                    bestDt = dt
                    best = a
                }
            }
            return best.clusterId
        }

        for i in diarized.indices {
            let timing = ticksForTiming(diarized[i])
            let t = midSeconds(startTicks: timing.start, endTicks: timing.end)

            guard isGatedIn(t) else {
                diarized[i].speakerId = nil
                diarized[i].speakerLabel = nil
                continue
            }

            if let cid = nearestCluster(at: t), let sid = clusterToSpeakerId[cid] {
                diarized[i].speakerId = sid
            } else {
                diarized[i].speakerId = "OFFSCREEN"
            }
            diarized[i].speakerLabel = nil
        }

        // 6b) Collapse extremely rare speakers when the model over-splits.
        // Some fixtures produce an extra "speaker" for a couple of words due to noisy embeddings.
        // If we ended up with 5+ speakers, reassign words belonging to tiny clusters to the nearest
        // non-rare speaker by time.
        let nonNilSpeakerIds = diarized.compactMap { w -> String? in
            guard let sid = w.speakerId, sid != "OFFSCREEN" else { return nil }
            return sid
        }
        let uniqueSpeakerIds = Set(nonNilSpeakerIds)
        if uniqueSpeakerIds.count >= 5 {
            var counts: [String: Int] = [:]
            counts.reserveCapacity(uniqueSpeakerIds.count)
            for sid in nonNilSpeakerIds { counts[sid, default: 0] += 1 }

            let totalWithSpeaker = max(1, nonNilSpeakerIds.count)
            let rareMax = max(2, Int((Double(totalWithSpeaker) * 0.03).rounded(.up)))
            let rare = Set(counts.compactMap { (k, v) in v <= rareMax ? k : nil })

            if !rare.isEmpty {
                func midTicks(_ w: TranscriptWordV1) -> Int64 {
                    let timing = ticksForTiming(w)
                    return timing.start + (max(Int64(0), timing.end - timing.start) / 2)
                }

                for i in diarized.indices {
                    guard let sid = diarized[i].speakerId, rare.contains(sid) else { continue }

                    var bestId: String? = nil

                    // Search outward for the nearest non-rare speaker.
                    var step = 1
                    while (i - step) >= 0 || (i + step) < diarized.count {
                        if (i - step) >= 0 {
                            if let cand = diarized[i - step].speakerId, cand != "OFFSCREEN", !rare.contains(cand) {
                                bestId = cand
                                break
                            }
                        }
                        if (i + step) < diarized.count {
                            if let cand = diarized[i + step].speakerId, cand != "OFFSCREEN", !rare.contains(cand) {
                                bestId = cand
                                break
                            }
                        }
                        step += 1
                    }

                    if bestId == nil {
                        diarized[i].speakerId = "OFFSCREEN"
                    } else {
                        diarized[i].speakerId = bestId
                    }
                }
            }
        }

        // 7) Deterministic labels and speaker_map.
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

        var entries: [SpeakerDiarizer.SpeakerMapV1.Entry] = []
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

        return Result(words: diarized, speakerMap: .init(speakers: entries))
    }

    private static func mapClustersToSpeakers(
        assignments: [AudioSpeakerClusterer.Assignment],
        sensors: MasterSensors,
        threshold: Double
    ) -> [String: String] {
        guard !assignments.isEmpty else { return [:] }

        // Default behavior: do not collapse audio clusters to face IDs.
        // Using face track IDs as the primary speaker IDs can collapse multi-speaker scenes whenever
        // multiple people are visible, even if the audio embeddings separate well.
        //
        // We keep the hook for future fusion work, but for now preserve audio-only cluster identity.
        _ = sensors
        _ = threshold

        let allClusterIds: [String] = Array(Set(assignments.map { $0.clusterId })).sorted()

        // If there's exactly one on-screen face track across the whole clip,
        // treat the scene as single-speaker-on-camera and collapse audio clusters to it.
        var faceTrackCounts: [String: Int] = [:]
        faceTrackCounts.reserveCapacity(4)
        for sample in sensors.videoSamples {
            for f in sample.faces {
                faceTrackCounts[f.trackId.uuidString, default: 0] += 1
            }
        }
        if faceTrackCounts.keys.count == 1, let onlyTrackId = faceTrackCounts.keys.first {
            var out: [String: String] = [:]
            out.reserveCapacity(allClusterIds.count)
            for cid in allClusterIds { out[cid] = onlyTrackId }
            return out
        }

        var out: [String: String] = [:]
        out.reserveCapacity(allClusterIds.count)
        for cid in allClusterIds {
            out[cid] = cid
        }
        return out
    }
}
