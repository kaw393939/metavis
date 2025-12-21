import Foundation
import simd

enum SceneContextHeuristics {

    static func inferScene(from samples: [MasterSensors.VideoSample]) -> MasterSensors.SceneContext {
        guard !samples.isEmpty else {
            return MasterSensors.SceneContext(
                indoorOutdoor: .init(label: .unknown, confidence: 0.0),
                lightSource: .init(label: .unknown, confidence: 0.0)
            )
        }

        // Aggregate basic stats.
        let meanLuma = samples.map { $0.meanLuma }.reduce(0.0, +) / Double(samples.count)
        let meanSkin = samples.map { $0.skinLikelihood }.reduce(0.0, +) / Double(samples.count)

        // Count how often a sky-like blue shows up in dominant colors.
        var blueVotes = 0
        var greenVotes = 0
        var coolVotes = 0
        var warmVotes = 0

        for s in samples {
            for c in s.dominantColors {
                // sky-ish blue in gamma space
                if c.z > c.x + 0.06 && c.z > c.y + 0.06 && c.z > 0.35 {
                    blueVotes += 1
                    break
                }
            }

            for c in s.dominantColors {
                // foliage-ish green in gamma space
                if c.y > c.x + 0.05 && c.y > c.z + 0.05 && c.y > 0.30 {
                    greenVotes += 1
                    break
                }
            }

            for c in s.dominantColors {
                // Outdoor daylight often has a "cool" palette (cyan/teal) where both G and B exceed R.
                // This catches sky+foliage mixes that are not strongly blue-only or green-only.
                let gb = max(c.y, c.z)
                if gb > c.x + 0.06 && gb > 0.35 {
                    coolVotes += 1
                    break
                }
            }

            // warm/tungsten-ish dominance
            if let c = s.dominantColors.first {
                if c.x > c.z + 0.08 && c.x > c.y + 0.03 {
                    warmVotes += 1
                }
            }
        }

        let blueRate = Double(blueVotes) / Double(samples.count)
        let greenRate = Double(greenVotes) / Double(samples.count)
        let coolRate = Double(coolVotes) / Double(samples.count)
        let warmRate = Double(warmVotes) / Double(samples.count)

        // Indoor/outdoor: conservative, prefers unknown unless clear.
        var indoorOutdoor = MasterSensors.ScoredLabel(label: MasterSensors.SceneLabel.unknown, confidence: 0.2)

        let outdoorCue = max(max(blueRate, greenRate), coolRate)

        if meanLuma > 0.30 && outdoorCue > 0.35 {
            // Bright + sky/foliage/cool-daylight cues → outdoors.
            let conf = min(0.95, 0.55 + 0.4 * min(1.0, (outdoorCue - 0.35) / 0.65))
            indoorOutdoor = .init(label: .outdoor, confidence: conf)
        } else if meanLuma < 0.28 && warmRate > 0.45 {
            // Darker + warm dominance → likely indoor.
            let conf = min(0.9, 0.55 + 0.35 * min(1.0, (warmRate - 0.45) / 0.55))
            indoorOutdoor = .init(label: .indoor, confidence: conf)
        }

        // Light source: infer mostly from outdoor vs warm dominance; keep unknown otherwise.
        var light = MasterSensors.ScoredLabel(label: MasterSensors.LightSourceLabel.unknown, confidence: 0.2)

        switch indoorOutdoor.label {
        case .outdoor:
            // Outdoors in park → natural light unless strong warm cue says otherwise.
            let conf = max(indoorOutdoor.confidence, 0.6)
            light = .init(label: .natural, confidence: min(0.95, conf))
        case .indoor:
            if warmRate > 0.5 {
                light = .init(label: .artificial, confidence: min(0.9, 0.6 + 0.3 * warmRate))
            } else {
                light = .init(label: .mixed, confidence: 0.55)
            }
        case .unknown:
            if warmRate > 0.55 && meanLuma < 0.30 {
                light = .init(label: .artificial, confidence: 0.6)
            } else if (outdoorCue > 0.60) && meanLuma > 0.35 {
                light = .init(label: .natural, confidence: 0.6)
            }
        }

        // Use skin as a weak supporting cue; if no skin at all, reduce confidence a bit.
        if meanSkin < 0.02 {
            indoorOutdoor = .init(label: indoorOutdoor.label, confidence: max(0.0, indoorOutdoor.confidence - 0.1))
            light = .init(label: light.label, confidence: max(0.0, light.confidence - 0.1))
        }

        return MasterSensors.SceneContext(indoorOutdoor: indoorOutdoor, lightSource: light)
    }
}
