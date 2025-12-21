import Foundation
import MetaVisCore

public enum AutoColorEvidenceSelector {

    public struct Options: Sendable, Equatable {
        public var seed: String
        public var cycleIndex: Int
        public var budgets: EvidencePack.Budgets
        public var escalation: AcceptanceReport.RequestedEvidenceEscalation?

        public init(
            seed: String = "default",
            cycleIndex: Int = 0,
            budgets: EvidencePack.Budgets = EvidencePack.Budgets(
                maxFrames: 8,
                maxVideoClips: 0,
                videoClipSeconds: 0.0,
                maxAudioClips: 0,
                audioClipSeconds: 0.0
            ),
            escalation: AcceptanceReport.RequestedEvidenceEscalation? = nil
        ) {
            self.seed = seed
            self.cycleIndex = cycleIndex
            self.budgets = budgets
            self.escalation = escalation
        }
    }

    public static func buildEvidencePack(from sensors: MasterSensors, options: Options = Options()) -> EvidencePack {
        let maxFrames = max(0, options.budgets.maxFrames)

        // Lower priority number = higher priority.
        var frameTimes: [(time: Double, tags: [String], priority: Int)] = []

        func addTime(_ t: Double, tags: [String], priority: Int) {
            guard t.isFinite, t >= 0 else { return }
            frameTimes.append((time: t, tags: tags, priority: priority))
        }

        let samples = sensors.videoSamples.sorted { $0.time < $1.time }

        // 1) Descriptor midpoints (high signal for "avoid heavy grade")
        if let desc = sensors.descriptors {
            for d in desc {
                if d.label == .avoidHeavyGrade || d.label == .gradeConfidenceLow {
                    let mid = (d.start + d.end) * 0.5
                    addTime(mid, tags: [d.label.rawValue], priority: 1)
                }
            }
        }

        // 2) Luma extremes + midpoint
        if !samples.isEmpty {
            if let minS = samples.min(by: { $0.meanLuma < $1.meanLuma }) {
                addTime(minS.time, tags: ["min_luma"], priority: 2)
            }
            if let maxS = samples.max(by: { $0.meanLuma < $1.meanLuma }) {
                addTime(maxS.time, tags: ["max_luma"], priority: 2)
            }
            let mid = samples[samples.count / 2].time
            addTime(mid, tags: ["midpoint"], priority: 2)
        }

        // 3) Escalation: add targeted frame requests (budgeted)
        if let secs = options.escalation?.addFramesAtSeconds, !secs.isEmpty {
            for t in secs {
                addTime(t, tags: ["escalation"], priority: 0)
            }
        }

        // 4) Fill remaining budget with evenly spaced anchors across analyzed duration.
        let analyzed = max(0.0, sensors.summary.analyzedSeconds)
        if analyzed > 0.0 {
            let anchors: [Double] = [0.15, 0.35, 0.65, 0.85].map { $0 * analyzed }
            for t in anchors {
                addTime(t, tags: ["anchor"], priority: 3)
            }
        }

        // Deduplicate by millisecond timestamp, merge tags, keep highest priority.
        frameTimes.sort { a, b in
            if a.priority != b.priority { return a.priority < b.priority }
            if a.time != b.time { return a.time < b.time }
            return a.tags.joined(separator: ",") < b.tags.joined(separator: ",")
        }
        var dedup: [(time: Double, tags: [String], priority: Int)] = []
        var seenTags: [Int: Set<String>] = [:]
        var seenPriority: [Int: Int] = [:]
        for f in frameTimes {
            let ms = Int((f.time * 1000).rounded())
            var tagSet = seenTags[ms] ?? Set<String>()
            for t in f.tags { tagSet.insert(t) }
            seenTags[ms] = tagSet

            if let p = seenPriority[ms] {
                seenPriority[ms] = min(p, f.priority)
            } else {
                seenPriority[ms] = f.priority
            }
        }
        for (ms, tags) in seenTags {
            dedup.append((time: Double(ms) / 1000.0, tags: tags.sorted(), priority: seenPriority[ms] ?? 3))
        }

        // Sort for selection: priority first, then time.
        dedup.sort { a, b in
            if a.priority != b.priority { return a.priority < b.priority }
            if a.time != b.time { return a.time < b.time }
            return a.tags.joined(separator: ",") < b.tags.joined(separator: ",")
        }

        if maxFrames == 0 {
            dedup = []
        } else if dedup.count > maxFrames {
            dedup = Array(dedup.prefix(maxFrames))
        }

        let frames: [EvidencePack.FrameAsset] = dedup.map { f in
            let ms = Int((f.time * 1000).rounded())
            return EvidencePack.FrameAsset(
                path: "evidence/frame_\(ms)ms.jpg",
                timeSeconds: f.time,
                rationaleTags: f.tags
            )
        }

        let budgetsUsed = EvidencePack.BudgetsUsed(
            frames: frames.count,
            videoClips: 0,
            audioClips: 0,
            totalAudioSeconds: 0.0,
            totalVideoSeconds: 0.0
        )

        var selectionNotes: [String] = []
        if let desc = sensors.descriptors {
            let veto = desc.contains(where: { ($0.label == .avoidHeavyGrade || $0.label == .gradeConfidenceLow) && ($0.veto ?? false) })
            selectionNotes.append("avoidHeavyVeto=\(veto)")
        }
        if let esc = options.escalation {
            if let framesReq = esc.addFramesAtSeconds, !framesReq.isEmpty { selectionNotes.append("escalation=add_frames") }
            if !esc.notes.isEmpty { selectionNotes.append("escalation_notes=\(esc.notes.prefix(2).joined(separator: ","))") }
        }

        let manifest = EvidencePack.Manifest(
            cycleIndex: options.cycleIndex,
            seed: options.seed,
            policyVersion: AutoColorGradeProposalV1.policyVersion,
            budgetsConfigured: options.budgets,
            budgetsUsed: budgetsUsed,
            timestampsSelected: frames.map { $0.timeSeconds }.sorted(),
            selectionNotes: selectionNotes
        )

        let summary = buildTextSummary(sensors: sensors)

        return EvidencePack(
            manifest: manifest,
            assets: EvidencePack.Assets(frames: frames),
            textSummary: summary
        )
    }

    private static func buildTextSummary(sensors: MasterSensors) -> String {
        var lines: [String] = []
        lines.append("COLOR EVIDENCE SUMMARY (deterministic):")
        lines.append(String(format: "- analyzedSeconds=%.3f", sensors.summary.analyzedSeconds))

        if sensors.videoSamples.isEmpty {
            lines.append("- videoSamples=0")
        } else {
            let lumas = sensors.videoSamples.map { $0.meanLuma }
            let mean = lumas.reduce(0.0, +) / Double(lumas.count)
            let minV = lumas.min() ?? mean
            let maxV = lumas.max() ?? mean
            lines.append(String(format: "- videoSamples=%d", sensors.videoSamples.count))
            lines.append(String(format: "- meanLuma≈%.3f (min=%.3f max=%.3f)", mean, minV, maxV))
        }

        if let desc = sensors.descriptors, !desc.isEmpty {
            let labels = desc.map { $0.label.rawValue }.sorted()
            lines.append("- descriptors=\(labels.prefix(8).joined(separator: ","))")
        } else {
            lines.append("- descriptors=none")
        }

        return lines.joined(separator: "\n")
    }
}
