import XCTest
import MetaVisPerception
import MetaVisCore

final class IdentityBindingGraphBuilderMouthActivityTests: XCTestCase {
    func test_mouthActivity_biasesBinding_whenGeometryTies() throws {
        let trackA = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let trackB = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!

        // Intentionally identical geometry so the base heuristic is ambiguous.
        let rect = CGRect(x: 0.10, y: 0.10, width: 0.30, height: 0.30)

        // Track A has higher mouth activity (mouthOpenRatio changes over time).
        // Track B is steady.
        let samples: [MasterSensors.VideoSample] = [
            .init(
                time: 1.0,
                meanLuma: 0.2,
                skinLikelihood: 0.0,
                dominantColors: [],
                faces: [
                    .init(trackId: trackA, rect: rect, personId: "P1", mouthOpenRatio: 0.01),
                    .init(trackId: trackB, rect: rect, personId: "P2", mouthOpenRatio: 0.02)
                ]
            ),
            .init(
                time: 2.0,
                meanLuma: 0.2,
                skinLikelihood: 0.0,
                dominantColors: [],
                faces: [
                    .init(trackId: trackA, rect: rect, personId: "P1", mouthOpenRatio: 0.06),
                    .init(trackId: trackB, rect: rect, personId: "P2", mouthOpenRatio: 0.02)
                ]
            ),
            .init(
                time: 3.0,
                meanLuma: 0.2,
                skinLikelihood: 0.0,
                dominantColors: [],
                faces: [
                    .init(trackId: trackA, rect: rect, personId: "P1", mouthOpenRatio: 0.01),
                    .init(trackId: trackB, rect: rect, personId: "P2", mouthOpenRatio: 0.02)
                ]
            )
        ]

        let sensors = MasterSensors(
            source: .init(path: "/tmp/x", durationSeconds: 4.0, width: nil, height: nil, nominalFPS: nil),
            sampling: .init(videoStrideSeconds: 1.0, maxVideoSeconds: 4.0, audioAnalyzeSeconds: 4.0),
            videoSamples: samples,
            audioSegments: [.init(start: 0.0, end: 4.0, kind: .speechLike, confidence: 1.0)],
            warnings: [],
            summary: .init(
                analyzedSeconds: 4.0,
                scene: .init(
                    indoorOutdoor: .init(label: .unknown, confidence: 0.0),
                    lightSource: .init(label: .unknown, confidence: 0.0)
                ),
                audio: .init(approxRMSdBFS: -10, approxPeakDB: -3)
            )
        )

        // Word at 2s attributed to speaker C1.
        let w = TranscriptWordV1(
            wordId: "w_120000_120000_1",
            word: "hello",
            confidence: 1,
            sourceTimeTicks: 120000,
            sourceTimeEndTicks: 120000,
            speakerId: "C1",
            speakerLabel: "T1",
            timelineTimeTicks: 120000,
            timelineTimeEndTicks: 120000
        )

        var opts = IdentityBindingGraphBuilder.Options()
        opts.centerWeight = 0.0
        opts.motionWeight = 0.0
        opts.mouthActivityWeight = 1.0
        opts.mouthWindowSeconds = 1.25
        opts.sampleWindowSeconds = 0.25
        opts.maxFacesPerSample = 2
        opts.minFaceAreaFractionOfMax = 0.0

        let a = IdentityBindingGraphBuilder.build(sensors: sensors, words: [w], options: opts)
        let b = IdentityBindingGraphBuilder.build(sensors: sensors, words: [w], options: opts)
        XCTAssertEqual(a, b)

        let best = a.bindings.first(where: { $0.speakerId == "C1" })
        XCTAssertNotNil(best)
        XCTAssertEqual(best?.trackId, trackA)
        XCTAssertTrue((best?.posterior ?? 0.0) > 0.50)
    }
}
