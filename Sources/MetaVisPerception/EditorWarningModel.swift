import Foundation
import MetaVisCore

enum EditorWarningModel {

    static func warnings(from samples: [MasterSensors.VideoSample]) -> [MasterSensors.WarningSegment] {
        guard samples.count >= 2 else { return [] }

        // Per-sample severity based on simple, deterministic heuristics.
        struct Mark {
            var t: Double
            var sev: MasterSensors.TrafficLight
            var reasons: [ReasonCodeV1]
        }

        var marks: [Mark] = []
        marks.reserveCapacity(samples.count)

        var previous: MasterSensors.VideoSample? = nil
        for s in samples {
            var reasons: [ReasonCodeV1] = []
            var score: Double = 0.0

            if s.faces.isEmpty {
                reasons.append(.no_face_detected)
                score += 0.55
            } else if s.faces.count >= 2 {
                reasons.append(.multiple_faces_competing)
                score += 0.30
            }

            // Face too small.
            if let f = s.faces.first {
                let area = Double(f.rect.width * f.rect.height)
                if area < 0.03 {
                    reasons.append(.face_too_small)
                    score += 0.25
                }
            }

            // Exposure risk based on mean luma.
            if s.meanLuma < 0.10 {
                reasons.append(.underexposed_risk)
                score += 0.35
            } else if s.meanLuma > 0.92 {
                reasons.append(.overexposed_risk)
                score += 0.35
            }

            // Luma instability (flicker / exposure shift proxy): large per-sample change.
            if let previous {
                let d = abs(s.meanLuma - previous.meanLuma)
                if d > 0.22 {
                    reasons.append(.luma_instability_risk)
                    score += 0.30
                }

                // Framing jump proxy from face center delta.
                if previous.faces.count == 1, s.faces.count == 1, let fa = previous.faces.first, let fb = s.faces.first {
                    let ax = Double(fa.rect.midX)
                    let ay = Double(fa.rect.midY)
                    let bx = Double(fb.rect.midX)
                    let by = Double(fb.rect.midY)
                    let jump = abs(ax - bx) + abs(ay - by)
                    if jump > 0.22 {
                        reasons.append(.framing_jump_risk)
                        score += 0.25
                    }
                }
            }

            let sev: MasterSensors.TrafficLight
            if score > 0.70 {
                sev = .red
            } else if score > 0.35 {
                sev = .yellow
            } else {
                sev = .green
            }

            marks.append(Mark(t: s.time, sev: sev, reasons: reasons))

            previous = s
        }

        // Coalesce consecutive marks of same severity.
        var segments: [MasterSensors.WarningSegment] = []
        var current = marks[0]
        var start = current.t

        func flush(end: Double) {
            let mergedReasons = Array(Set(current.reasons)).sorted()
            // If this segment has no reasons and is green, omit it entirely.
            if mergedReasons.isEmpty && current.sev == .green {
                return
            }
            let seg = MasterSensors.WarningSegment(
                start: start,
                end: end,
                severity: current.sev,
                reasonCodes: mergedReasons
            )
            segments.append(seg)
        }

        for i in 1..<marks.count {
            let m = marks[i]
            if m.sev == current.sev {
                current.reasons.append(contentsOf: m.reasons)
                continue
            }
            flush(end: m.t)
            current = m
            start = m.t
        }

        if let last = marks.last {
            flush(end: last.t + 0.001)
        }

        return segments
    }
}
