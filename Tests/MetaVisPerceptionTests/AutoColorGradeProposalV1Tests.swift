import XCTest
import MetaVisPerception
import MetaVisCore

final class AutoColorGradeProposalV1Tests: XCTestCase {

    private func makeSensors(
        analyzedSeconds: Double = 10.0,
        videoSamples: [MasterSensors.VideoSample],
        descriptors: [MasterSensors.DescriptorSegment] = []
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
            videoSamples: videoSamples,
            audioSegments: [],
            warnings: [],
            descriptors: descriptors,
            summary: summary
        )
    }

    func test_proposal_is_deterministic_for_same_inputs() {
        let sensors = makeSensors(videoSamples: [
            .init(time: 0.0, meanLuma: 0.25, skinLikelihood: 0.0, dominantColors: [], faces: []),
            .init(time: 1.0, meanLuma: 0.55, skinLikelihood: 0.0, dominantColors: [], faces: [])
        ])

        let a = AutoColorGradeProposalV1.propose(from: sensors, options: .init(seed: "seed"))
        let b = AutoColorGradeProposalV1.propose(from: sensors, options: .init(seed: "seed"))

        XCTAssertEqual(a, b)
        XCTAssertEqual(a.grade.effectId, "com.metavis.fx.grade.simple")
        XCTAssertNotEqual(a.proposalId, "")
    }

    func test_avoidHeavyGrade_sets_flag_and_is_conservative() {
        let sensors = makeSensors(
            videoSamples: [
                .init(time: 0.0, meanLuma: 0.10, skinLikelihood: 0.0, dominantColors: [], faces: []),
                .init(time: 1.0, meanLuma: 0.20, skinLikelihood: 0.0, dominantColors: [], faces: [])
            ],
            descriptors: [
                .init(start: 0.0, end: 2.0, label: .avoidHeavyGrade, confidence: 1.0, veto: true)
            ]
        )

        let p = AutoColorGradeProposalV1.propose(from: sensors, options: .init(seed: "seed"))
        XCTAssertTrue(p.flags.contains("avoidHeavyGrade"))

        let exposure = p.grade.params["exposure"] ?? 0.0
        XCTAssertLessThanOrEqual(abs(exposure), 0.15 + 1e-6)
    }
}
