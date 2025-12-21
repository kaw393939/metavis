import Foundation
import MetaVisCore

enum AudioWarningModel {

    /// Produces deterministic warning segments from audio summary + VAD segments.
    ///
    /// Reason codes (stable):
    /// - `audio_silence`
    /// - `audio_clip_risk`
    /// - `audio_noise_risk`
    static func warnings(
        audio: MasterSensors.AudioSummary,
        segments: [MasterSensors.AudioSegment],
        analyzedSeconds: Double
    ) -> [MasterSensors.WarningSegment] {
        guard analyzedSeconds.isFinite, analyzedSeconds > 0 else { return [] }

        var out: [MasterSensors.WarningSegment] = []

        // 1) Silence segments → yellow/red.
        for s in segments {
            guard s.kind == .silence else { continue }
            let start = max(0.0, min(analyzedSeconds, s.start))
            let end = max(0.0, min(analyzedSeconds, s.end))
            let dur = max(0.0, end - start)
            if dur < 0.25 { continue }

            let sev: MasterSensors.TrafficLight
            if dur >= 1.25 {
                sev = .red
            } else {
                sev = .yellow
            }

            out.append(
                .init(
                    start: start,
                    end: end,
                    severity: sev,
                    reasonCodes: [.audio_silence]
                )
            )
        }

        // 2) Clip risk (global) — our peak is derived from max(abs(sample)); 0 dBFS ~ 1.0.
        // Avoid false positives on isolated peaks when overall program level is modest.
        // Heuristic:
        // - Always warn when very close to full scale.
        // - Otherwise only warn when both peak is near full scale AND overall RMS is quite loud.
        let peakDB = Double(audio.approxPeakDB)
        let rmsDB = Double(audio.approxRMSdBFS)
        let shouldWarnClipRisk: Bool =
            (peakDB.isFinite && peakDB > -0.3) ||
            (peakDB.isFinite && peakDB > -1.0 && rmsDB.isFinite && rmsDB > -18.0)

        if shouldWarnClipRisk {
            out.append(
                .init(
                    start: 0.0,
                    end: analyzedSeconds,
                    severity: .red,
                    reasonCodes: [.audio_clip_risk]
                )
            )
        }

        // 3) Noise risk (global, heuristic): high centroid while not quiet.
        // Prefer segment-level detection when we have features.
        var emittedSegmentNoise = false
        for s in segments {
            guard s.kind != .silence else { continue }
            guard let centroid = s.spectralCentroidHz, let flat = s.spectralFlatness, let rmsDB = s.rmsDB else { continue }
            // Only consider segments that are not quiet.
            if rmsDB <= -45 { continue }

            let start = max(0.0, min(analyzedSeconds, s.start))
            let end = max(0.0, min(analyzedSeconds, s.end))
            let dur = end - start
            // Avoid noisy false positives on brief transients.
            if dur < 0.75 { continue }

            // Broadband-ish noise proxy: high centroid + high flatness.
            // Be more lenient during speech-like segments.
            let flatRed = (s.kind == .speechLike) ? 0.75 : 0.65
            let flatYellow = (s.kind == .speechLike) ? 0.65 : 0.50
            let centroidRed = (s.kind == .speechLike) ? 7000.0 : 6000.0
            let centroidYellow = (s.kind == .speechLike) ? 5500.0 : 4800.0

            if centroid > centroidRed && flat > flatRed {
                out.append(.init(start: start, end: end, severity: .red, reasonCodes: [.audio_noise_risk]))
                emittedSegmentNoise = true
            } else if centroid > centroidYellow && flat > flatYellow {
                out.append(.init(start: start, end: end, severity: .yellow, reasonCodes: [.audio_noise_risk]))
                emittedSegmentNoise = true
            }
        }

        // Fallback: global heuristic when segment features are unavailable.
        if !emittedSegmentNoise,
           let centroid = audio.spectralCentroidHz,
           centroid.isFinite,
           audio.approxRMSdBFS.isFinite {
            let rmsDB = Double(audio.approxRMSdBFS)
            if rmsDB > -45 {
                if centroid > 5200 {
                    out.append(.init(start: 0.0, end: analyzedSeconds, severity: .red, reasonCodes: [.audio_noise_risk]))
                } else if centroid > 3600 {
                    out.append(.init(start: 0.0, end: analyzedSeconds, severity: .yellow, reasonCodes: [.audio_noise_risk]))
                }
            }
        }

        // Deterministic ordering.
        out.sort {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            if $0.severity.rawValue != $1.severity.rawValue { return $0.severity.rawValue < $1.severity.rawValue }
            return $0.governedReasonCodes.map { $0.rawValue }.joined(separator: ",") < $1.governedReasonCodes.map { $0.rawValue }.joined(separator: ",")
        }

        return out
    }
}
