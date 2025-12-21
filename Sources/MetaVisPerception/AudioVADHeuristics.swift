import Foundation
import Accelerate

enum AudioVADHeuristics {

    struct Window: Sendable {
        var start: Double
        var end: Double
        var rmsDB: Double
        var centroidHz: Double
        var dominantHz: Double
        var flatness: Double
        var zcr: Double
    }

    /// Builds simple speech/silence segments from mono samples.
    static func segment(
        mono: [Float],
        sampleRate: Double,
        windowSeconds: Double = 0.5,
        hopSeconds: Double = 0.5
    ) -> [MasterSensors.AudioSegment] {
        guard sampleRate.isFinite, sampleRate > 1000, !mono.isEmpty else { return [] }

        let win = max(0.1, windowSeconds)
        let hop = max(0.05, hopSeconds)

        let winN = max(256, Int((win * sampleRate).rounded(.toNearestOrAwayFromZero)))
        let hopN = max(128, Int((hop * sampleRate).rounded(.toNearestOrAwayFromZero)))

        // Reuse one DFT setup for the whole pass for performance.
        let fftN = 1024
        let dftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftN), vDSP_DFT_Direction.FORWARD)
        defer {
            if let dftSetup { vDSP_DFT_DestroySetup(dftSetup) }
        }

        let hann = hannWindow(count: fftN)

        var real = [Float](repeating: 0, count: fftN)
        var imag = [Float](repeating: 0, count: fftN)
        var outReal = [Float](repeating: 0, count: fftN)
        var outImag = [Float](repeating: 0, count: fftN)
        var mags = [Float](repeating: 0, count: fftN / 2)

        let windows = computeWindows(
            mono: mono,
            sampleRate: sampleRate,
            winN: winN,
            hopN: hopN,
            dftSetup: dftSetup,
            hann: hann,
            real: &real,
            imag: &imag,
            outReal: &outReal,
            outImag: &outImag,
            mags: &mags
        )

        // Dynamic silence threshold: relative to a conservative noise floor estimate,
        // but never more aggressive than -45 dBFS.
        let silenceThresholdDB: Double = {
            guard !windows.isEmpty else { return -50 }
            let rmsSorted = windows.map { $0.rmsDB }.sorted()
            let idx = max(0, min(rmsSorted.count - 1, Int((0.15 * Double(rmsSorted.count)).rounded(.down))))
            let floorDB = rmsSorted[idx]
            return min(-45.0, max(-70.0, floorDB + 8.0))
        }()

        // Classify windows into hop-sized (non-overlapping) marks.
        struct Mark {
            var start: Double
            var end: Double
            var kind: MasterSensors.AudioSegmentKind
            var conf: Double
            var w: Window
        }
        var marks: [Mark] = []
        marks.reserveCapacity(windows.count)

        for w in windows {
            let segStart = w.start
            let segEnd = min(w.end, w.start + hop)
            if segEnd <= segStart + 0.0001 { continue }

            if w.rmsDB < silenceThresholdDB {
                marks.append(.init(start: segStart, end: segEnd, kind: .silence, conf: 0.8, w: w))
                continue
            }

            // For talking-head with mild background noise, prefer labeling as speechLike rather than oscillating unknown.
            // Confidence is reduced as the spectrum becomes flatter (more noise-like).
            let isSpeechBand = (w.centroidHz > 250 && w.centroidHz < 4200)
            let hasSpeechZCR = (w.zcr > 0.005 && w.zcr < 0.25)
            let hasVoiceFundamental = (w.dominantHz > 70 && w.dominantHz < 350)

            if w.rmsDB > silenceThresholdDB && isSpeechBand && hasSpeechZCR {
                // Map flatness to confidence: flatter → lower confidence.
                var conf = max(0.45, min(0.85, 0.85 - 0.6 * w.flatness))
                // Dominant bin is a weak heuristic; use as a confidence modifier, not a hard gate.
                conf = hasVoiceFundamental ? min(0.90, conf + 0.05) : max(0.40, conf - 0.08)
                marks.append(.init(start: segStart, end: segEnd, kind: .speechLike, conf: conf, w: w))
            } else if w.rmsDB > silenceThresholdDB && w.flatness < 0.22 && w.centroidHz < 6000 {
                marks.append(.init(start: segStart, end: segEnd, kind: .musicLike, conf: 0.60, w: w))
            } else {
                marks.append(.init(start: segStart, end: segEnd, kind: .unknown, conf: 0.40, w: w))
            }
        }

        // Coalesce consecutive segments and aggregate features deterministically.
        guard let first = marks.first else { return [] }
        var out: [MasterSensors.AudioSegment] = []
        var cur = first
        var sumDur: Double = 0.0
        var sumRmsDB: Double = 0.0
        var sumCentroid: Double = 0.0
        var sumDominant: Double = 0.0
        var sumFlatness: Double = 0.0

        func add(_ m: Mark) {
            let dur = max(0.0, m.end - m.start)
            guard dur > 0 else { return }
            sumDur += dur
            sumRmsDB += m.w.rmsDB * dur
            sumCentroid += m.w.centroidHz * dur
            sumDominant += m.w.dominantHz * dur
            sumFlatness += m.w.flatness * dur
        }

        // Seed with first mark.
        add(cur)

        func flushCurrent() {
            func cleanValue(_ v: Double?) -> Double? {
                guard let v, v.isFinite else { return nil }
                return abs(v) < 1e-9 ? nil : v
            }

            let rms = (sumDur > 1e-9) ? cleanValue(sumRmsDB / sumDur) : nil
            let centroid = (sumDur > 1e-9) ? cleanValue(sumCentroid / sumDur) : nil
            let dominant = (sumDur > 1e-9) ? cleanValue(sumDominant / sumDur) : nil
            let flat = (sumDur > 1e-9) ? cleanValue(sumFlatness / sumDur) : nil
            out.append(
                .init(
                    start: cur.start,
                    end: cur.end,
                    kind: cur.kind,
                    confidence: cur.conf,
                    rmsDB: rms,
                    spectralCentroidHz: centroid,
                    dominantFrequencyHz: dominant,
                    spectralFlatness: flat
                )
            )
        }

        for m in marks.dropFirst() {
            if m.kind == cur.kind {
                cur.end = m.end
                cur.conf = max(cur.conf, m.conf)
                add(m)
                continue
            }
            flushCurrent()
            cur = m
            sumDur = 0
            sumRmsDB = 0
            sumCentroid = 0
            sumDominant = 0
            sumFlatness = 0
            add(cur)
        }
        flushCurrent()

        // Suppress short transient musicLike blips (often tonal transients in speech).
        out = suppressShortMusicLike(in: out, minDurationSeconds: 1.5)

        // Drop tiny segments.
        return out.filter { ($0.end - $0.start) >= 0.2 }
    }

    /// Builds hop-sized audio frames for downstream beat/emphasis modeling.
    static func frames(
        mono: [Float],
        sampleRate: Double,
        windowSeconds: Double = 0.5,
        hopSeconds: Double = 0.25
    ) -> [MasterSensors.AudioFrame] {
        guard sampleRate.isFinite, sampleRate > 1000, !mono.isEmpty else { return [] }

        let win = max(0.1, windowSeconds)
        let hop = max(0.05, hopSeconds)

        let winN = max(256, Int((win * sampleRate).rounded(.toNearestOrAwayFromZero)))
        let hopN = max(128, Int((hop * sampleRate).rounded(.toNearestOrAwayFromZero)))

        let fftN = 1024
        let dftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftN), vDSP_DFT_Direction.FORWARD)
        defer {
            if let dftSetup { vDSP_DFT_DestroySetup(dftSetup) }
        }

        let hann = hannWindow(count: fftN)

        var real = [Float](repeating: 0, count: fftN)
        var imag = [Float](repeating: 0, count: fftN)
        var outReal = [Float](repeating: 0, count: fftN)
        var outImag = [Float](repeating: 0, count: fftN)
        var mags = [Float](repeating: 0, count: fftN / 2)

        let windows = computeWindows(
            mono: mono,
            sampleRate: sampleRate,
            winN: winN,
            hopN: hopN,
            dftSetup: dftSetup,
            hann: hann,
            real: &real,
            imag: &imag,
            outReal: &outReal,
            outImag: &outImag,
            mags: &mags
        )

        func cleanValue(_ v: Double?) -> Double? {
            guard let v, v.isFinite else { return nil }
            return abs(v) < 1e-9 ? nil : v
        }

        var out: [MasterSensors.AudioFrame] = []
        out.reserveCapacity(windows.count)

        var prevRms: Double?
        var prevCentroid: Double?
        var prevDominant: Double?
        var prevFlat: Double?
        var prevZcr: Double?
        var prevVoicing: Double?

        func clamp01(_ x: Double) -> Double { max(0.0, min(1.0, x)) }

        func voicingScore(flatness: Double?, zcr: Double?, pitchHz: Double?) -> Double? {
            guard let flatness, let zcr else { return nil }

            // Flatness: speech tends to be less noise-like than wind/birds.
            // Map flatness (0..1) → [1..0] with a soft knee.
            let flatScore = clamp01((0.75 - flatness) / 0.60)

            // ZCR: speech-like activity often sits in a moderate band.
            // Use a triangular preference around ~0.08.
            let zCenter = 0.08
            let zWidth = 0.08
            let zScore = clamp01(1.0 - abs(zcr - zCenter) / zWidth)

            // Pitch present (in a plausible vocal band) boosts confidence slightly.
            let pitchBoost: Double = (pitchHz != nil) ? 1.0 : 0.75

            return clamp01(flatScore * zScore * pitchBoost)
        }

        for w in windows {
            let start = w.start
            let end = min(w.end, w.start + hop)
            if end <= start + 0.0001 { continue }

            let rms = cleanValue(w.rmsDB)
            let centroid = cleanValue(w.centroidHz)
            let dominant = cleanValue(w.dominantHz)
            let flat = cleanValue(w.flatness)
            let zcr = cleanValue(w.zcr)

            let rmsDelta = (rms != nil && prevRms != nil) ? cleanValue(rms! - prevRms!) : nil
            let centroidDelta = (centroid != nil && prevCentroid != nil) ? cleanValue(centroid! - prevCentroid!) : nil
            let dominantDelta = (dominant != nil && prevDominant != nil) ? cleanValue(dominant! - prevDominant!) : nil
            let flatDelta = (flat != nil && prevFlat != nil) ? cleanValue(flat! - prevFlat!) : nil
            let zcrDelta = (zcr != nil && prevZcr != nil) ? cleanValue(zcr! - prevZcr!) : nil

            // Very lightweight pitch heuristic: treat dominant bin as pitch when it sits in a plausible vocal range
            // and the spectrum is not too noise-like.
            let pitchHz: Double?
            if let d = dominant, let f = flat, d >= 70, d <= 350, f <= 0.45 {
                pitchHz = d
            } else {
                pitchHz = nil
            }

            let voice = cleanValue(voicingScore(flatness: flat, zcr: zcr, pitchHz: pitchHz))
            let voiceDelta = (voice != nil && prevVoicing != nil) ? cleanValue(voice! - prevVoicing!) : nil

            out.append(
                .init(
                    start: start,
                    end: end,
                    rmsDB: rms,
                    rmsDeltaDB: rmsDelta,
                    spectralCentroidHz: centroid,
                    centroidDeltaHz: centroidDelta,
                    dominantFrequencyHz: dominant,
                    dominantDeltaHz: dominantDelta,
                    spectralFlatness: flat,
                    flatnessDelta: flatDelta,
                    zeroCrossingRate: zcr,
                    zcrDelta: zcrDelta,
                    voicingScore: voice,
                    voicingDelta: voiceDelta,
                    pitchHz: pitchHz
                )
            )

            prevRms = rms
            prevCentroid = centroid
            prevDominant = dominant
            prevFlat = flat
            prevZcr = zcr
            prevVoicing = voice
        }

        return out
    }

    /// Deterministic beat candidates derived from audioFrames.
    static func beats(from frames: [MasterSensors.AudioFrame]) -> [MasterSensors.AudioBeat] {
        guard frames.count >= 2 else { return [] }

        func clamp01(_ x: Double) -> Double { max(0.0, min(1.0, x)) }

        var out: [MasterSensors.AudioBeat] = []
        out.reserveCapacity(max(1, frames.count / 6))

        // Emphasis: detect onsets where energy rises quickly.
        let onsetDB = 3.0
        let impactOffsetSeconds = 0.200

        func snapToHopNearest(_ t: Double, hop: Double) -> Double {
            guard hop.isFinite, hop > 0.000001 else { return t }
            return (t / hop).rounded(.toNearestOrAwayFromZero) * hop
        }

        // Prefer snapping to the audio frame hop so “impact” lands on a stable grid.
        let hopSeconds = max(0.000001, frames[1].start - frames[0].start)

        for i in 1..<frames.count {
            let f = frames[i]
            let prev = frames[i - 1]
            guard let d = f.rmsDeltaDB, let rms = f.rmsDB else { continue }
            // Ignore silence-ish frames.
            if rms < -50 { continue }

            let prevD = prev.rmsDeltaDB ?? 0.0
            if d >= onsetDB && prevD < onsetDB {
                // Make onsets steeper so real emphases land “editor-visible”.
                let base = clamp01((d - onsetDB) / 4.0)
                let voicing = clamp01(f.voicingScore ?? 0.0)

                // Down-rank energy spikes that don't look speech-like.
                // voicingScale: 0.35..1.0
                let voicingScale = 0.35 + 0.65 * voicing
                var conf = clamp01(base * voicingScale)
                if voicing >= 0.55 {
                    conf = max(conf, 0.65)
                }

                let onsetTime = f.start
                let impact = max(onsetTime, snapToHopNearest(onsetTime + impactOffsetSeconds, hop: hopSeconds))
                let reasons: [String] = (voicing >= 0.55)
                    ? ["energy_onset", "voicing_ok"]
                    : ["energy_onset", "voicing_low"]
                out.append(
                    .init(
                        time: onsetTime,
                        timeImpact: impact,
                        kind: .emphasis,
                        confidence: conf,
                        reasons: reasons
                    )
                )
            }
        }

        // Pause boundary beats: speech → silence transitions are often the most editor-visible anchors.
        // Emit a boundary beat when silence persists >= ~300ms.
        let minSilenceSeconds = 0.30
        var silenceRunStartIndex: Int?
        var silenceRunDuration: Double = 0.0

        func flushSilenceRun(endIndexExclusive: Int) {
            guard let startIndex = silenceRunStartIndex else { return }
            guard silenceRunDuration >= minSilenceSeconds else { return }
            let boundaryIndex = startIndex
            guard boundaryIndex > 0 else { return }
            let before = frames[boundaryIndex - 1]
            let beforeVoicing = clamp01(before.voicingScore ?? 0.0)
            guard beforeVoicing >= 0.55 || (before.rmsDB ?? -100) > -45 else { return }

            let t = frames[boundaryIndex].start
            out.append(
                .init(
                    time: t,
                    timeImpact: snapToHopNearest(t, hop: hopSeconds),
                    kind: .boundary,
                    confidence: min(0.95, 0.75 + 0.20 * beforeVoicing),
                    reasons: ["pause_boundary", "silence_run"]
                )
            )
        }

        for i in 0..<frames.count {
            let f = frames[i]
            let rms = f.rmsDB ?? -100
            let isSilence = rms < -50
            if isSilence {
                if silenceRunStartIndex == nil {
                    silenceRunStartIndex = i
                    silenceRunDuration = 0.0
                }
                silenceRunDuration += max(0.0, f.end - f.start)
            } else {
                flushSilenceRun(endIndexExclusive: i)
                silenceRunStartIndex = nil
                silenceRunDuration = 0.0
            }
        }
        flushSilenceRun(endIndexExclusive: frames.count)

        // Deterministic ordering.
        out.sort {
            if abs($0.time - $1.time) > 1e-9 { return $0.time < $1.time }
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.confidence > $1.confidence
        }

        return out
    }

    private static func computeWindows(
        mono: [Float],
        sampleRate: Double,
        winN: Int,
        hopN: Int,
        dftSetup: OpaquePointer?,
        hann: [Float],
        real: inout [Float],
        imag: inout [Float],
        outReal: inout [Float],
        outImag: inout [Float],
        mags: inout [Float]
    ) -> [Window] {
        var windows: [Window] = []
        windows.reserveCapacity(max(1, mono.count / hopN))
        mono.withUnsafeBufferPointer { ptr in
            var i = 0
            while i + winN <= ptr.count {
                let start = Double(i) / sampleRate
                let end = Double(i + winN) / sampleRate
                let base = ptr.baseAddress!.advanced(by: i)
                let rms = rmsDB(base, count: winN)
                let (centroid, dominantHz, flatness) = spectralFeatures(
                    base,
                    count: winN,
                    sampleRate: sampleRate,
                    dftSetup: dftSetup,
                    hann: hann,
                    real: &real,
                    imag: &imag,
                    outReal: &outReal,
                    outImag: &outImag,
                    mags: &mags
                )
                let z = zeroCrossingRate(base, count: winN)
                windows.append(Window(start: start, end: end, rmsDB: rms, centroidHz: centroid, dominantHz: dominantHz, flatness: flatness, zcr: z))
                i += hopN
            }
        }
        return windows
    }

    private static func suppressShortMusicLike(
        in segments: [MasterSensors.AudioSegment],
        minDurationSeconds: Double
    ) -> [MasterSensors.AudioSegment] {
        guard minDurationSeconds > 0, segments.count >= 2 else { return segments }

        struct Seg {
            var start: Double
            var end: Double
            var kind: MasterSensors.AudioSegmentKind
            var confidence: Double
            var rmsDB: Double?
            var spectralCentroidHz: Double?
            var dominantFrequencyHz: Double?
            var spectralFlatness: Double?
        }

        // First pass: relabel short musicLike segments.
        var relabeled: [Seg] = segments.map {
            Seg(
                start: $0.start,
                end: $0.end,
                kind: $0.kind,
                confidence: $0.confidence,
                rmsDB: $0.rmsDB,
                spectralCentroidHz: $0.spectralCentroidHz,
                dominantFrequencyHz: $0.dominantFrequencyHz,
                spectralFlatness: $0.spectralFlatness
            )
        }
        for i in relabeled.indices {
            guard relabeled[i].kind == .musicLike else { continue }
            let dur = relabeled[i].end - relabeled[i].start
            guard dur < minDurationSeconds else { continue }

            let prevKind: MasterSensors.AudioSegmentKind? = (i > 0) ? relabeled[i - 1].kind : nil
            let nextKind: MasterSensors.AudioSegmentKind? = (i + 1 < relabeled.count) ? relabeled[i + 1].kind : nil

            // Prefer collapsing into speechLike when the transient is adjacent to speech.
            let newKind: MasterSensors.AudioSegmentKind = (prevKind == .speechLike || nextKind == .speechLike) ? .speechLike : .unknown
            let newConfidence: Double
            switch newKind {
            case .speechLike:
                newConfidence = min(relabeled[i].confidence, 0.55)
            case .unknown:
                newConfidence = min(relabeled[i].confidence, 0.40)
            default:
                newConfidence = relabeled[i].confidence
            }

            relabeled[i].kind = newKind
            relabeled[i].confidence = newConfidence
        }

        // Second pass: coalesce adjacent segments with the same kind and aggregate features deterministically.
        guard var current = relabeled.first else { return [] }
        var out: [Seg] = []

        var sumDur: Double = 0.0
        var sumRmsDB: Double = 0.0
        var sumCentroid: Double = 0.0
        var sumDominant: Double = 0.0
        var sumFlatness: Double = 0.0

        func add(_ seg: Seg) {
            let dur = max(0.0, seg.end - seg.start)
            guard dur > 0 else { return }
            sumDur += dur
            if let v = seg.rmsDB { sumRmsDB += v * dur }
            if let v = seg.spectralCentroidHz { sumCentroid += v * dur }
            if let v = seg.dominantFrequencyHz { sumDominant += v * dur }
            if let v = seg.spectralFlatness { sumFlatness += v * dur }
        }

        func flush() {
            func cleanValue(_ v: Double?) -> Double? {
                guard let v, v.isFinite else { return nil }
                return abs(v) < 1e-9 ? nil : v
            }

            let rms = (sumDur > 1e-9) ? cleanValue(sumRmsDB / sumDur) : nil
            let centroid = (sumDur > 1e-9) ? cleanValue(sumCentroid / sumDur) : nil
            let dominant = (sumDur > 1e-9) ? cleanValue(sumDominant / sumDur) : nil
            let flat = (sumDur > 1e-9) ? cleanValue(sumFlatness / sumDur) : nil

            out.append(
                Seg(
                    start: current.start,
                    end: current.end,
                    kind: current.kind,
                    confidence: current.confidence,
                    rmsDB: rms,
                    spectralCentroidHz: centroid,
                    dominantFrequencyHz: dominant,
                    spectralFlatness: flat
                )
            )
        }

        add(current)
        for seg in relabeled.dropFirst() {
            if seg.kind == current.kind {
                current.end = seg.end
                current.confidence = max(current.confidence, seg.confidence)
                add(seg)
            } else {
                flush()
                current = seg
                sumDur = 0
                sumRmsDB = 0
                sumCentroid = 0
                sumDominant = 0
                sumFlatness = 0
                add(current)
            }
        }
        flush()
        return out.map {
            .init(
                start: $0.start,
                end: $0.end,
                kind: $0.kind,
                confidence: $0.confidence,
                rmsDB: $0.rmsDB,
                spectralCentroidHz: $0.spectralCentroidHz,
                dominantFrequencyHz: $0.dominantFrequencyHz,
                spectralFlatness: $0.spectralFlatness
            )
        }
    }

    private static func rmsDB(_ base: UnsafePointer<Float>, count: Int) -> Double {
        guard count > 0 else { return -100 }
        // Use AC RMS (mean-removed) so DC offsets don't look like audible energy.
        var meanSquare: Float = 0
        vDSP_measqv(base, 1, &meanSquare, vDSP_Length(count))

        var mean: Float = 0
        vDSP_meanv(base, 1, &mean, vDSP_Length(count))

        let acMeanSquare = max(0, meanSquare - mean * mean)
        let rms = sqrt(acMeanSquare)
        return rms > 0 ? Double(20.0 * log10(rms)) : -100
    }

    private static func spectralFeatures(
        _ base: UnsafePointer<Float>,
        count: Int,
        sampleRate: Double,
        dftSetup: OpaquePointer?,
        hann: [Float],
        real: inout [Float],
        imag: inout [Float],
        outReal: inout [Float],
        outImag: inout [Float],
        mags: inout [Float]
    ) -> (centroidHz: Double, dominantHz: Double, flatness: Double) {
        // Use a fixed FFT size for determinism/perf.
        let n = real.count
        guard let dftSetup else { return (0, 0, 1.0) }

        if count <= 0 { return (0, 0, 1.0) }

        // Build a deterministic analysis slice of length n from the full window.
        // If the window is longer than n, downsample by block-averaging across the whole window
        // so FFT features represent the same time span as RMS/ZCR.
        if count >= n {
            var start = 0
            for i in 0..<n {
                let end = ((i + 1) * count) / n
                let hi = max(start + 1, end)
                var sum: Float = 0
                for j in start..<hi {
                    sum += base[j]
                }
                real[i] = sum / Float(hi - start)
                start = end
            }
        } else {
            let copyN = count
            real.withUnsafeMutableBufferPointer { r in
                r.baseAddress!.update(from: base, count: copyN)
            }
            if copyN < n {
                for i in copyN..<n { real[i] = 0 }
            }
        }

        // Remove DC offset (mean) before FFT to reduce leakage and stabilize ZCR/flatness heuristics.
        var mean: Float = 0
        vDSP_meanv(real, 1, &mean, vDSP_Length(n))
        var negMean = -mean
        vDSP_vsadd(real, 1, &negMean, &real, 1, vDSP_Length(n))

        // Apply Hann window to reduce spectral leakage.
        let hwCount = min(n, hann.count)
        if hwCount > 0 {
            real.withUnsafeMutableBufferPointer { rPtr in
                hann.withUnsafeBufferPointer { hPtr in
                    guard let r = rPtr.baseAddress, let h = hPtr.baseAddress else { return }
                    vDSP_vmul(r, 1, h, 1, r, 1, vDSP_Length(hwCount))
                }
            }
        }

        // Ensure imag input is zeroed deterministically (it's a reused buffer).
        imag.withUnsafeMutableBufferPointer { iPtr in
            guard let ip = iPtr.baseAddress else { return }
            vDSP_vclr(ip, 1, vDSP_Length(n))
        }

        vDSP_DFT_Execute(dftSetup, &real, &imag, &outReal, &outImag)

        let bins = n / 2
        outReal.withUnsafeMutableBufferPointer { rPtr in
            outImag.withUnsafeMutableBufferPointer { iPtr in
                var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(bins))
            }
        }

        // Ignore DC.
        if bins > 0 { mags[0] = 0 }

        // Dominant frequency.
        var maxVal: Float = 0
        var maxIndex: vDSP_Length = 0
        vDSP_maxvi(&mags, 1, &maxVal, &maxIndex, vDSP_Length(bins))

        let binHz = (sampleRate / 2.0) / Double(bins)
        let dominantHz = Double(maxIndex) * binHz

        // Spectral centroid + flatness.
        var sumMag: Double = 0
        var sumWeighted: Double = 0
        var sumLog: Double = 0

        // Avoid log(0).
        let eps = 1e-12
        for i in 1..<bins {
            let m = Double(mags[i]) + eps
            sumMag += m
            sumWeighted += m * (Double(i) * binHz)
            sumLog += log(m)
        }
        if sumMag <= 1e-9 {
            return (0, dominantHz, 1.0)
        }
        let centroid = sumWeighted / sumMag
        let geoMean = exp(sumLog / Double(max(1, bins - 1)))
        let arithMean = sumMag / Double(max(1, bins - 1))
        let flatness = (arithMean > 0) ? (geoMean / arithMean) : 1.0

        // Quantize to stabilize tiny floating-point drift across repeated runs.
        // This keeps downstream classification behavior effectively unchanged while making
        // Equatable comparisons and stable JSON determinism robust.
        func quantize(_ x: Double, step: Double) -> Double {
            guard x.isFinite, step > 0 else { return x }
            return (x / step).rounded() * step
        }
        let centroidQ = quantize(centroid, step: 1e-3) // 0.001 Hz
        let flatQ = quantize(min(1.0, max(0.0, flatness)), step: 1e-6)
        return (centroidQ, dominantHz, flatQ)
    }

    private static func zeroCrossingRate(_ base: UnsafePointer<Float>, count: Int) -> Double {
        guard count > 1 else { return 0 }
        // Remove DC offset so crossings aren't suppressed by bias.
        var mean: Float = 0
        vDSP_meanv(base, 1, &mean, vDSP_Length(count))
        var crossings: Int = 0
        var prev = base[0] - mean
        for i in 1..<count {
            let cur = base[i] - mean
            if (prev >= 0 && cur < 0) || (prev < 0 && cur >= 0) {
                crossings += 1
            }
            prev = cur
        }
        return Double(crossings) / Double(count - 1)
    }

    private static func hannWindow(count: Int) -> [Float] {
        guard count > 1 else { return [Float](repeating: 1, count: max(0, count)) }
        var out = [Float](repeating: 0, count: count)
        let denom = Float(count - 1)
        for i in 0..<count {
            let x = Float(i) / denom
            out[i] = 0.5 - 0.5 * cosf(2.0 * Float.pi * x)
        }
        return out
    }
}
