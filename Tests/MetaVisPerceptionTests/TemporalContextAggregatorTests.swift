import XCTest
import MetaVisPerception
import MetaVisCore

final class TemporalContextAggregatorTests: XCTestCase {
    func test_aggregate_isDeterministic_onSyntheticInputs() throws {
        let trackA = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let faceA = MasterSensors.Face(trackId: trackA, rect: .init(x: 0.1, y: 0.1, width: 0.2, height: 0.2), personId: "P1")

        let samples: [MasterSensors.VideoSample] = [
            .init(time: 0.0, meanLuma: 0.2, skinLikelihood: 0.0, dominantColors: [], faces: [faceA]),
            .init(time: 1.0, meanLuma: 0.2, skinLikelihood: 0.0, dominantColors: [], faces: [faceA]),
            .init(time: 2.1, meanLuma: 0.5, skinLikelihood: 0.0, dominantColors: [], faces: [faceA])
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

        let a = TemporalContextAggregator.aggregate(sensors: sensors, options: .init(minTrackStableSeconds: 2.0, lumaShiftThreshold: 0.25))
        let b = TemporalContextAggregator.aggregate(sensors: sensors, options: .init(minTrackStableSeconds: 2.0, lumaShiftThreshold: 0.25))
        XCTAssertEqual(a, b)

        // Should emit a stable-track event.
        XCTAssertTrue(a.events.contains(where: { $0.kind == .faceTrackStable && $0.trackId == trackA }))
    }
}
