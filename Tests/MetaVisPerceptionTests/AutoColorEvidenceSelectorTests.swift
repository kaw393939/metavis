import XCTest
import MetaVisPerception
import MetaVisCore

final class AutoColorEvidenceSelectorTests: XCTestCase {

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

    func test_budgeted_frames_are_capped_and_stable() {
        let sensors = makeSensors(videoSamples: [
            .init(time: 0.0, meanLuma: 0.10, skinLikelihood: 0.0, dominantColors: [], faces: []),
            .init(time: 1.0, meanLuma: 0.90, skinLikelihood: 0.0, dominantColors: [], faces: []),
            .init(time: 2.0, meanLuma: 0.50, skinLikelihood: 0.0, dominantColors: [], faces: [])
        ])

        let budgets = EvidencePack.Budgets(maxFrames: 2, maxVideoClips: 0, videoClipSeconds: 0.0, maxAudioClips: 0, audioClipSeconds: 0.0)
        let a = AutoColorEvidenceSelector.buildEvidencePack(from: sensors, options: .init(seed: "seed", cycleIndex: 0, budgets: budgets))
        let b = AutoColorEvidenceSelector.buildEvidencePack(from: sensors, options: .init(seed: "seed", cycleIndex: 0, budgets: budgets))

        XCTAssertEqual(a, b)
        XCTAssertLessThanOrEqual(a.assets.frames.count, 2)
        XCTAssertEqual(a.manifest.budgetsUsed.frames, a.assets.frames.count)
    }

    func test_escalation_adds_requested_frames_budgeted() {
        let sensors = makeSensors(videoSamples: [
            .init(time: 0.0, meanLuma: 0.10, skinLikelihood: 0.0, dominantColors: [], faces: []),
            .init(time: 1.0, meanLuma: 0.90, skinLikelihood: 0.0, dominantColors: [], faces: [])
        ])

        let budgets = EvidencePack.Budgets(maxFrames: 2, maxVideoClips: 0, videoClipSeconds: 0.0, maxAudioClips: 0, audioClipSeconds: 0.0)
        let base = AutoColorEvidenceSelector.buildEvidencePack(from: sensors, options: .init(seed: "seed", cycleIndex: 0, budgets: budgets))

        let esc = AcceptanceReport.RequestedEvidenceEscalation(addFramesAtSeconds: [3.0, 4.0, 5.0], extendOneAudioClipToSeconds: nil, notes: ["need more frames"]) 
        let escalated = AutoColorEvidenceSelector.buildEvidencePack(from: sensors, options: .init(seed: "seed", cycleIndex: 0, budgets: budgets, escalation: esc))

        XCTAssertLessThanOrEqual(escalated.assets.frames.count, 2)
        let times = escalated.assets.frames.map { $0.timeSeconds }.sorted()
        XCTAssertEqual(times, [3.0, 4.0])
        XCTAssertNotEqual(base.assets.frames, escalated.assets.frames)
    }
}
