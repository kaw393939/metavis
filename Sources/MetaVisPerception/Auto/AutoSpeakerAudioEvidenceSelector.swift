import Foundation
import MetaVisCore

public enum AutoSpeakerAudioEvidenceSelector {

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
                maxAudioClips: 4,
                audioClipSeconds: 2.0
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
        let analyzed = max(0.0, sensors.summary.analyzedSeconds)
        let baseSnippetSeconds = max(0.25, min(10.0, options.budgets.audioClipSeconds))

        let reasons = sensors.warnings.flatMap { $0.governedReasonCodes }
        let hasNoiseRisk = reasons.contains(.audio_noise_risk)
        let hasClipRisk = reasons.contains(.audio_clip_risk)

        typealias Window = (label: String, startSeconds: Double, endSeconds: Double)
        var windows: [Window] = []

        func addWindow(label: String, center: Double, seconds: Double = baseSnippetSeconds) {
            guard analyzed > 0 else { return }
            let dur = max(0.25, min(10.0, seconds))
            let half = dur * 0.5
            var start = max(0.0, center - half)
            start = min(start, max(0.0, analyzed - dur))
            let end = min(analyzed, start + dur)
            windows.append((label: label, startSeconds: start, endSeconds: end))
        }

        func stableIndex(seed: String, salt: String, count: Int) -> Int {
            guard count > 0 else { return 0 }
            let hex = StableHash.sha256Hex(utf8: "\(seed)|\(salt)")
            let prefix = hex.prefix(8)
            let value = Int(prefix, radix: 16) ?? 0
            return abs(value) % count
        }

        // Escalation hint: extend ONE audio window duration (deterministic choice).
        let extendOneToSeconds: Double? = {
            guard let esc = options.escalation else { return nil }
            guard let s = esc.extendOneAudioClipToSeconds, s.isFinite else { return nil }
            let v = max(baseSnippetSeconds, min(10.0, s))
            return v > baseSnippetSeconds ? v : nil
        }()

        // 1) Noise-risk window: choose deterministically among noise risk segments using the seed.
        if hasNoiseRisk {
            let candidates = sensors.warnings.filter { $0.governedReasonCodes.contains(.audio_noise_risk) }
            if let seg = candidates[safe: stableIndex(seed: options.seed, salt: "noise_risk", count: candidates.count)] {
                addWindow(label: "noise_risk", center: (seg.start + seg.end) * 0.5)
            }
        }

        // 2) Clip-risk window: loudest non-silence segment by rmsDB; fallback to first speech-like.
        if hasClipRisk {
            if let loud = sensors.audioSegments
                .filter({ $0.kind != .silence })
                .compactMap({ s -> (MasterSensors.AudioSegment, Double)? in
                    guard let rms = s.rmsDB, rms.isFinite else { return nil }
                    return (s, rms)
                })
                .sorted(by: { a, b in
                    if a.1 != b.1 { return a.1 > b.1 }
                    if a.0.start != b.0.start { return a.0.start < b.0.start }
                    return a.0.end < b.0.end
                })
                .first?.0 {
                addWindow(label: "clip_risk", center: (loud.start + loud.end) * 0.5)
            } else if let speech = sensors.audioSegments.first(where: { $0.kind == .speechLike }) {
                addWindow(label: "clip_risk", center: (speech.start + speech.end) * 0.5)
            } else {
                addWindow(label: "clip_risk", center: 0.5)
            }
        }

        // 3) Typical speech baseline: earliest speechLike.
        if let speech = sensors.audioSegments.first(where: { $0.kind == .speechLike }) {
            addWindow(label: "speech_baseline", center: (speech.start + speech.end) * 0.5)
        }

        // 4) Silence → speech transition: earliest boundary.
        if let transition = firstSilenceToSpeechTransition(in: sensors.audioSegments) {
            addWindow(label: "silence_to_speech", center: transition)
        }

        // Deduplicate windows by label+start (stable).
        windows.sort { a, b in
            if a.startSeconds != b.startSeconds { return a.startSeconds < b.startSeconds }
            if a.endSeconds != b.endSeconds { return a.endSeconds < b.endSeconds }
            return a.label < b.label
        }
        var deduped: [Window] = []
        var seen = Set<String>()
        for w in windows {
            let k = "\(w.label)|\(Int((w.startSeconds * 1000).rounded()))"
            if seen.contains(k) { continue }
            seen.insert(k)
            deduped.append(w)
        }

        // Apply escalation extension to exactly one window, if requested.
        if let extendSeconds = extendOneToSeconds, !deduped.isEmpty {
            let priority: [String] = ["clip_risk", "noise_risk", "speech_baseline", "silence_to_speech"]
            let chosenIndex: Int = {
                for p in priority {
                    if let idx = deduped.firstIndex(where: { $0.label == p }) { return idx }
                }
                return 0
            }()
            windows = []
            // Rebuild with per-window override for chosen.
            for (i, win) in deduped.enumerated() {
                let seconds = (i == chosenIndex) ? extendSeconds : baseSnippetSeconds
                addWindow(label: win.label, center: (win.startSeconds + win.endSeconds) * 0.5, seconds: seconds)
            }
            windows.sort { a, b in
                if a.startSeconds != b.startSeconds { return a.startSeconds < b.startSeconds }
                if a.endSeconds != b.endSeconds { return a.endSeconds < b.endSeconds }
                return a.label < b.label
            }
            deduped = windows
        }

        // Keep it minimal: cap by configured budget.
        let maxAudio = max(0, options.budgets.maxAudioClips)
        if maxAudio > 0, deduped.count > maxAudio {
            deduped = Array(deduped.prefix(maxAudio))
        } else if maxAudio == 0 {
            deduped = []
        }

        let selectionNotes: [String] = {
            var notes: [String] = []
            if hasNoiseRisk { notes.append("risk=audio_noise") }
            if hasClipRisk { notes.append("risk=audio_clip") }
            if notes.isEmpty { notes.append("risk=none") }
            if let esc = options.escalation {
                if let extend = esc.extendOneAudioClipToSeconds { notes.append("escalation=extend_audio_to_\(extend)") }
                if let frames = esc.addFramesAtSeconds, !frames.isEmpty { notes.append("escalation=add_frames") }
                if !esc.notes.isEmpty { notes.append("escalation_notes=\(esc.notes.prefix(2).joined(separator: ","))") }
            }
            return notes
        }()

        // Deterministic asset pathing: pick a stable, human-readable name per window.
        let audioClips: [EvidencePack.AudioClipAsset] = deduped.map { w in
            let startMs = Int((w.startSeconds * 1000).rounded())
            let path = "evidence/audio_\(w.label)_\(startMs)ms.wav"
            return EvidencePack.AudioClipAsset(
                path: path,
                startSeconds: w.startSeconds,
                endSeconds: w.endSeconds,
                rationaleTags: [w.label]
            )
        }

        // Escalation: add targeted frames if requested (budgeted).
        let frames: [EvidencePack.FrameAsset] = {
            guard let secs = options.escalation?.addFramesAtSeconds, !secs.isEmpty else { return [] }
            let maxFrames = max(0, options.budgets.maxFrames)
            if maxFrames == 0 { return [] }
            let sorted = secs
                .filter { $0.isFinite && $0 >= 0 }
                .sorted()
            let capped = Array(sorted.prefix(maxFrames))
            return capped.map { t in
                let ms = Int((t * 1000).rounded())
                let path = "evidence/frame_\(ms)ms.jpg"
                return EvidencePack.FrameAsset(path: path, timeSeconds: t, rationaleTags: ["escalation"])
            }
        }()

        let timestamps = deduped
            .map { (w: Window) -> Double in (w.startSeconds + w.endSeconds) * 0.5 }
            .sorted()

        let timestampsAll = (timestamps + frames.map { $0.timeSeconds }).sorted()

        let budgetsConfigured = options.budgets
        let totalAudioSeconds = audioClips.reduce(0.0) { $0 + max(0.0, $1.endSeconds - $1.startSeconds) }
        let budgetsUsed = EvidencePack.BudgetsUsed(
            frames: frames.count,
            videoClips: 0,
            audioClips: audioClips.count,
            totalAudioSeconds: totalAudioSeconds,
            totalVideoSeconds: 0.0
        )

        let manifest = EvidencePack.Manifest(
            cycleIndex: options.cycleIndex,
            seed: options.seed,
            policyVersion: AutoSpeakerAudioProposalV1.policyVersion,
            budgetsConfigured: budgetsConfigured,
            budgetsUsed: budgetsUsed,
            timestampsSelected: timestampsAll,
            selectionNotes: selectionNotes
        )

        let summary = buildTextSummary(sensors: sensors, hasNoiseRisk: hasNoiseRisk, hasClipRisk: hasClipRisk)
        return EvidencePack(
            manifest: manifest,
            assets: EvidencePack.Assets(frames: frames, audioClips: audioClips),
            textSummary: summary
        )
    }

    private static func firstSilenceToSpeechTransition(in segments: [MasterSensors.AudioSegment]) -> Double? {
        guard segments.count >= 2 else { return nil }
        let sorted = segments.sorted { a, b in
            if a.start != b.start { return a.start < b.start }
            return a.end < b.end
        }
        for i in 0..<(sorted.count - 1) {
            let a = sorted[i]
            let b = sorted[i + 1]
            if a.kind == .silence && b.kind == .speechLike {
                return b.start
            }
        }
        return nil
    }

    private static func buildTextSummary(sensors: MasterSensors, hasNoiseRisk: Bool, hasClipRisk: Bool) -> String {
        let audio = sensors.summary.audio
        let analyzed = sensors.summary.analyzedSeconds
        let silenceSeconds = sensors.audioSegments
            .filter { $0.kind == .silence }
            .map { max(0.0, $0.end - $0.start) }
            .reduce(0.0, +)
        let silenceFrac = analyzed > 0 ? (silenceSeconds / analyzed) : 0.0

        var lines: [String] = []
        lines.append("AUDIO SUMMARY (deterministic):")
        lines.append(String(format: "- analyzedSeconds=%.3f", analyzed))
        lines.append(String(format: "- approxPeakDB=%.2f", Double(audio.approxPeakDB)))
        lines.append(String(format: "- approxRMSdBFS=%.2f", Double(audio.approxRMSdBFS)))
        lines.append(String(format: "- silenceFraction≈%.2f", silenceFrac))
        lines.append("- warnings: noiseRisk=\(hasNoiseRisk), clipRisk=\(hasClipRisk)")
        return lines.joined(separator: "\n")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
