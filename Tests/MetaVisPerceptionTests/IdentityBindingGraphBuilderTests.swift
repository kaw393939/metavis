import XCTest
import MetaVisPerception
import MetaVisCore

final class IdentityBindingGraphBuilderTests: XCTestCase {
    func test_build_isDeterministic_andEmitsPosteriorEdges() throws {
        let trackA = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let trackB = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!

        // Construct a case where a tiny centered face could incorrectly win if center is overweighted.
        // We expect the larger face to win (area dominates; center is only a tiebreak).
        let faceA = MasterSensors.Face(trackId: trackA, rect: .init(x: 0.0, y: 0.0, width: 0.2, height: 0.2), personId: "P1")
        let faceB = MasterSensors.Face(trackId: trackB, rect: .init(x: 0.455, y: 0.455, width: 0.09, height: 0.09), personId: "P2")

        let samples: [MasterSensors.VideoSample] = [
            .init(time: 1.0, meanLuma: 0.2, skinLikelihood: 0.0, dominantColors: [], faces: [faceA, faceB])
        ]

        let sensors = MasterSensors(
            source: .init(path: "/tmp/x", durationSeconds: 3.0, width: nil, height: nil, nominalFPS: nil),
            sampling: .init(videoStrideSeconds: 1.0, maxVideoSeconds: 3.0, audioAnalyzeSeconds: 3.0),
            videoSamples: samples,
            audioSegments: [.init(start: 0.0, end: 3.0, kind: .unknown, confidence: 1.0)],
            warnings: [],
            summary: .init(
                analyzedSeconds: 3.0,
                scene: .init(
                    indoorOutdoor: .init(label: .unknown, confidence: 0.0),
                    lightSource: .init(label: .unknown, confidence: 0.0)
                ),
                audio: .init(approxRMSdBFS: -10, approxPeakDB: -3)
            )
        )

        // Word at 1s attributed to speaker C1.
        let w = TranscriptWordV1(
            wordId: "w_60000_60000_1",
            word: "hi",
            confidence: 1,
            sourceTimeTicks: 60000,
            sourceTimeEndTicks: 60000,
            speakerId: "C1",
            speakerLabel: "T1",
            timelineTimeTicks: 60000,
            timelineTimeEndTicks: 60000
        )

        let a = IdentityBindingGraphBuilder.build(sensors: sensors, words: [w])
        let b = IdentityBindingGraphBuilder.build(sensors: sensors, words: [w])
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.schema, "identity.bindings.v1")

        // Should bind to the larger face (trackA) with posterior >= trackB.
        XCTAssertFalse(a.bindings.isEmpty)
        let best = a.bindings.first(where: { $0.speakerId == "C1" })
        XCTAssertNotNil(best)
        XCTAssertEqual(best?.trackId, trackA)
        XCTAssertEqual(best?.personId, "P1")
        XCTAssertTrue((best?.posterior ?? 0.0) > 0.5)
    }
}
