import Foundation

enum AutoStartHeuristics {

    static func suggestStart(
        videoSamples: [MasterSensors.VideoSample],
        audioSegments: [MasterSensors.AudioSegment],
        analyzedSeconds: Double
    ) -> MasterSensors.SuggestedStart? {
        guard analyzedSeconds > 0.2 else { return nil }

        // 1) Find first sustained speech-like region.
        let speechCandidates = audioSegments
            .filter { $0.kind == .speechLike }
            .map { (start: max(0.0, $0.start), end: min(analyzedSeconds, $0.end)) }
            .filter { ($0.end - $0.start) >= 0.8 }
            .sorted { $0.start < $1.start }

        guard let speech = speechCandidates.first else { return nil }

        // Candidate start is at speech onset (after any throat-clear / settling).
        var candidateTime = max(0.0, min(speech.start, analyzedSeconds))
        var reasons: [String] = ["speech_onset"]
        var confidence: Double = 0.6

        // If there is a short unknown segment right before speech, treat it as a throat-clear / pre-roll cue.
        if let prior = audioSegments
            .filter({ $0.end <= speech.start + 0.05 })
            .sorted(by: { $0.end > $1.end })
            .first,
           prior.kind == .unknown,
           (prior.end - prior.start) <= 0.7 {
            reasons.append("pre_speech_transient")
            confidence = max(confidence, 0.65)
        }

        // 2) Require "looking at camera" proxy: face is present, centered, and reasonably sized.
        // If not satisfied at candidate time, slide forward within the speech segment.
        if let improved = refineByFaceProxy(videoSamples: videoSamples, within: speech, start: candidateTime) {
            reasons.append("face_centered")
            candidateTime = improved.time
            confidence = max(confidence, improved.confidence)
        } else {
            // If we can't validate face at all, keep candidate but lower confidence.
            reasons.append("face_uncertain")
            confidence = min(confidence, 0.55)
        }

        // If speech begins immediately at t=0, emitting a zero suggested start is not useful
        // (and prevents the suggested_start descriptor from being emitted because it would be empty).
        // Bias to a tiny non-zero trim point when there's enough content.
        let minNonZeroStart = 0.12
        if candidateTime < minNonZeroStart, speech.end >= minNonZeroStart + 0.05 {
            candidateTime = minNonZeroStart
            reasons.append("avoid_zero_start")
            confidence = max(confidence, 0.60)
        }

        // Clamp.
        candidateTime = max(0.0, min(candidateTime, analyzedSeconds))

        return MasterSensors.SuggestedStart(time: candidateTime, reasons: reasons, confidence: min(0.95, confidence))
    }

    private static func refineByFaceProxy(
        videoSamples: [MasterSensors.VideoSample],
        within speech: (start: Double, end: Double),
        start: Double
    ) -> (time: Double, confidence: Double)? {
        guard !videoSamples.isEmpty else { return nil }

        // Consider samples that fall within the speech segment.
        let candidates = videoSamples
            .filter { $0.time >= speech.start - 0.25 && $0.time <= speech.end }
            .sorted { $0.time < $1.time }

        func isFaceCentered(_ face: MasterSensors.Face) -> Bool {
            let r = face.rect
            let cx = r.midX
            let cy = r.midY
            // Wide tolerance: avoids overfitting; this is just "looking at camera" proxy.
            return abs(cx - 0.5) <= 0.20 && abs(cy - 0.5) <= 0.20
        }

        func faceArea(_ face: MasterSensors.Face) -> Double {
            return Double(max(0.0, min(1.0, face.rect.width * face.rect.height)))
        }

        // Start scanning at/after `start`.
        for s in candidates {
            if s.time + 0.0001 < start { continue }
            guard s.faces.count == 1, let f = s.faces.first else { continue }
            let area = faceArea(f)
            if area < 0.02 { continue }
            if !isFaceCentered(f) { continue }

            // Confidence bonus if the next sample is also stable.
            let base: Double = 0.7
            let next = candidates.first(where: { $0.time > s.time + 0.01 })
            if let next, next.faces.count == 1, let nf = next.faces.first {
                let da = abs(faceArea(nf) - area)
                let dc = abs(nf.rect.midX - f.rect.midX) + abs(nf.rect.midY - f.rect.midY)
                if da <= 0.03 && dc <= 0.10 {
                    return (time: max(s.time, speech.start), confidence: min(0.9, base + 0.15))
                }
            }
            return (time: max(s.time, speech.start), confidence: base)
        }

        return nil
    }
}
