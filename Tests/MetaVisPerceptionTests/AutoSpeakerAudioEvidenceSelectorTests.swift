import XCTest
import MetaVisPerception
import MetaVisCore

final class AutoSpeakerAudioEvidenceSelectorTests: XCTestCase {

    private func makeSensors(
        analyzedSeconds: Double = 20.0,
        warnings: [MasterSensors.WarningSegment],
        audioSegments: [MasterSensors.AudioSegment]
    ) -> MasterSensors {
        let source = MasterSensors.SourceInfo(path: "fixture.mov", durationSeconds: analyzedSeconds, width: nil, height: nil, nominalFPS: nil)
        let sampling = MasterSensors.SamplingInfo(videoStrideSeconds: 1.0, maxVideoSeconds: analyzedSeconds, audioAnalyzeSeconds: analyzedSeconds)
        let scene = MasterSensors.SceneContext(
            indoorOutdoor: .init(label: .unknown, confidence: 0.0),
            lightSource: .init(label: .unknown, confidence: 0.0)
        )
        let audio = MasterSensors.AudioSummary(approxRMSdBFS: -20.0, approxPeakDB: -3.0)
        let summary = MasterSensors.Summary(analyzedSeconds: analyzedSeconds, scene: scene, audio: audio)
        return MasterSensors(
            source: source,
            sampling: sampling,
            videoSamples: [],
            audioSegments: audioSegments,
            warnings: warnings,
            summary: summary
        )
    }

    func test_budgeted_selection_is_stable() {
        let sensors = makeSensors(
            warnings: [
                .init(start: 1.0, end: 3.0, severity: .yellow, reasons: ["audio_noise_risk"]),
                .init(start: 10.0, end: 12.0, severity: .yellow, reasons: ["audio_noise_risk"])
            ],
            audioSegments: [
                .init(start: 0.0, end: 2.0, kind: .silence, confidence: 1.0),
                .init(start: 2.0, end: 8.0, kind: .speechLike, confidence: 1.0, rmsDB: -18.0),
                .init(start: 8.0, end: 9.0, kind: .silence, confidence: 1.0),
                .init(start: 9.0, end: 15.0, kind: .speechLike, confidence: 1.0, rmsDB: -16.0)
            ]
        )

        let budgets = EvidencePack.Budgets(maxFrames: 0, maxVideoClips: 0, videoClipSeconds: 0.0, maxAudioClips: 3, audioClipSeconds: 2.0)
        let a = AutoSpeakerAudioEvidenceSelector.buildEvidencePack(from: sensors, options: .init(seed: "seed", cycleIndex: 0, budgets: budgets))
        let b = AutoSpeakerAudioEvidenceSelector.buildEvidencePack(from: sensors, options: .init(seed: "seed", cycleIndex: 0, budgets: budgets))

        XCTAssertEqual(a, b)
        XCTAssertLessThanOrEqual(a.assets.audioClips.count, 3)
        XCTAssertEqual(a.manifest.budgetsConfigured.maxAudioClips, 3)
        XCTAssertEqual(a.manifest.budgetsConfigured.audioClipSeconds, 2.0, accuracy: 0.0001)
    }

    func test_selection_changes_with_seed_when_choices_exist() {
        let sensors = makeSensors(
            warnings: [
                .init(start: 1.0, end: 3.0, severity: .yellow, reasons: ["audio_noise_risk"]),
                .init(start: 10.0, end: 12.0, severity: .yellow, reasons: ["audio_noise_risk"])
            ],
            audioSegments: [
                .init(start: 0.0, end: 2.0, kind: .silence, confidence: 1.0),
                .init(start: 2.0, end: 8.0, kind: .speechLike, confidence: 1.0, rmsDB: -18.0)
            ]
        )

        let budgets = EvidencePack.Budgets(maxFrames: 0, maxVideoClips: 0, videoClipSeconds: 0.0, maxAudioClips: 4, audioClipSeconds: 2.0)

        func noiseRiskChoiceIndex(seed: String) -> Int {
            let hex = StableHash.sha256Hex(utf8: "\(seed)|noise_risk")
            let prefix = hex.prefix(8)
            let value = Int(prefix, radix: 16) ?? 0
            return abs(value) % 2
        }

        let seedA = "seedA"
        var seedB = "seedB"
        if noiseRiskChoiceIndex(seed: seedA) == noiseRiskChoiceIndex(seed: seedB) {
            // deterministically find a different seed so this test isn't flaky
            for i in 0..<50 {
                let candidate = "seedB_\(i)"
                if noiseRiskChoiceIndex(seed: seedA) != noiseRiskChoiceIndex(seed: candidate) {
                    seedB = candidate
                    break
                }
            }
        }

        let a = AutoSpeakerAudioEvidenceSelector.buildEvidencePack(from: sensors, options: .init(seed: seedA, cycleIndex: 0, budgets: budgets))
        let b = AutoSpeakerAudioEvidenceSelector.buildEvidencePack(from: sensors, options: .init(seed: seedB, cycleIndex: 0, budgets: budgets))

        XCTAssertNotEqual(a.manifest.timestampsSelected, b.manifest.timestampsSelected)
    }

    func test_escalation_adds_targeted_evidence_only() {
        let sensors = makeSensors(
            warnings: [
                .init(start: 6.0, end: 8.0, severity: .yellow, reasons: ["audio_clip_risk"])
            ],
            audioSegments: [
                .init(start: 0.0, end: 4.0, kind: .speechLike, confidence: 1.0, rmsDB: -10.0),
                .init(start: 4.0, end: 5.0, kind: .silence, confidence: 1.0),
                .init(start: 5.0, end: 12.0, kind: .speechLike, confidence: 1.0, rmsDB: -8.0)
            ]
        )

        let budgets = EvidencePack.Budgets(maxFrames: 2, maxVideoClips: 0, videoClipSeconds: 0.0, maxAudioClips: 4, audioClipSeconds: 2.0)
        let base = AutoSpeakerAudioEvidenceSelector.buildEvidencePack(from: sensors, options: .init(seed: "seed", cycleIndex: 0, budgets: budgets))
        XCTAssertFalse(base.assets.audioClips.isEmpty)
        let baseDurations = base.assets.audioClips.map { $0.endSeconds - $0.startSeconds }
        XCTAssertTrue(baseDurations.allSatisfy { abs($0 - 2.0) < 0.0001 })
        XCTAssertTrue(base.assets.frames.isEmpty)

        let esc = AcceptanceReport.RequestedEvidenceEscalation(addFramesAtSeconds: [1.0, 2.0], extendOneAudioClipToSeconds: 5.0, notes: ["need more context"])
        let escalated = AutoSpeakerAudioEvidenceSelector.buildEvidencePack(from: sensors, options: .init(seed: "seed", cycleIndex: 0, budgets: budgets, escalation: esc))

        // Exactly one clip should be extended.
        let durations = escalated.assets.audioClips.map { $0.endSeconds - $0.startSeconds }
        XCTAssertEqual(durations.filter { abs($0 - 5.0) < 0.0001 }.count, 1)
        XCTAssertEqual(durations.filter { abs($0 - 2.0) < 0.0001 }.count, max(0, durations.count - 1))

        // Frames should be added but still budgeted.
        XCTAssertEqual(escalated.assets.frames.count, 2)
        XCTAssertLessThanOrEqual(escalated.assets.frames.count, budgets.maxFrames)

        // Escalation should not increase audio clip count beyond the base selection.
        XCTAssertEqual(escalated.assets.audioClips.count, base.assets.audioClips.count)
    }
}
