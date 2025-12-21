import XCTest
import MetaVisPerception
import MetaVisCore

final class AutoSpeakerAudioProposalV1Tests: XCTestCase {

    func test_proposal_is_deterministic_for_same_sensors_and_seed() throws {
        let sensors = MasterSensors(
            schemaVersion: 4,
            source: .init(path: "fixture.mov", durationSeconds: 10, width: 1920, height: 1080, nominalFPS: 24),
            sampling: .init(videoStrideSeconds: 1.0, maxVideoSeconds: 10.0, audioAnalyzeSeconds: 10.0),
            videoSamples: [],
            audioSegments: [
                .init(start: 0.0, end: 1.0, kind: .silence, confidence: 1.0),
                .init(start: 1.0, end: 4.0, kind: .speechLike, confidence: 0.9, rmsDB: -20, spectralCentroidHz: 6500, dominantFrequencyHz: 220, spectralFlatness: 0.8)
            ],
            audioFrames: nil,
            audioBeats: nil,
            warnings: [
                .init(start: 0.0, end: 10.0, severity: .red, reasons: ["audio_noise_risk"]),
                .init(start: 0.0, end: 10.0, severity: .red, reasons: ["audio_clip_risk"])
            ],
            descriptors: nil,
            suggestedStart: nil,
            summary: .init(
                analyzedSeconds: 10.0,
                scene: .init(
                    indoorOutdoor: .init(label: .unknown, confidence: 0.2),
                    lightSource: .init(label: .unknown, confidence: 0.2)
                ),
                audio: .init(approxRMSdBFS: -20.0, approxPeakDB: -0.2, dominantFrequencyHz: 220, spectralCentroidHz: 6500)
            )
        )

        let p1 = AutoSpeakerAudioProposalV1.propose(from: sensors, options: .init(seed: "seedA"))
        let p2 = AutoSpeakerAudioProposalV1.propose(from: sensors, options: .init(seed: "seedA"))

        XCTAssertEqual(p1, p2)
        XCTAssertFalse(p1.proposalId.isEmpty)

        // With clip risk, v1 should prefer safety gain.
        let first = p1.chain.first
        XCTAssertEqual(first?.effectId, "audio.dialogCleanwater.v1")
        XCTAssertEqual(first?.params?["globalGainDB"], 3.0)
    }

    func test_evidence_selection_is_deterministic() {
        let sensors = MasterSensors(
            schemaVersion: 4,
            source: .init(path: "fixture.mov", durationSeconds: 6, width: nil, height: nil, nominalFPS: nil),
            sampling: .init(videoStrideSeconds: 1.0, maxVideoSeconds: 6.0, audioAnalyzeSeconds: 6.0),
            videoSamples: [],
            audioSegments: [
                .init(start: 0.0, end: 1.0, kind: .silence, confidence: 1.0),
                .init(start: 1.0, end: 2.0, kind: .speechLike, confidence: 0.9),
                .init(start: 2.0, end: 3.0, kind: .speechLike, confidence: 0.9),
            ],
            audioFrames: nil,
            audioBeats: nil,
            warnings: [
                .init(start: 0.0, end: 6.0, severity: .yellow, reasons: ["audio_noise_risk"])
            ],
            descriptors: nil,
            suggestedStart: nil,
            summary: .init(
                analyzedSeconds: 6.0,
                scene: .init(
                    indoorOutdoor: .init(label: .unknown, confidence: 0.2),
                    lightSource: .init(label: .unknown, confidence: 0.2)
                ),
                audio: .init(approxRMSdBFS: -30.0, approxPeakDB: -6.0)
            )
        )

        let budgets = EvidencePack.Budgets(maxFrames: 0, maxVideoClips: 0, videoClipSeconds: 0.0, maxAudioClips: 4, audioClipSeconds: 2.0)
        let e1 = AutoSpeakerAudioEvidenceSelector.buildEvidencePack(from: sensors, options: .init(seed: "seedA", cycleIndex: 0, budgets: budgets))
        let e2 = AutoSpeakerAudioEvidenceSelector.buildEvidencePack(from: sensors, options: .init(seed: "seedA", cycleIndex: 0, budgets: budgets))
        XCTAssertEqual(e1, e2)
        XCTAssertFalse(e1.assets.audioClips.isEmpty)
        XCTAssertEqual(e1.manifest.cycleIndex, 0)
    }
}
