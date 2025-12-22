import XCTest
@testable import MetaVisPerception

final class BiteMapBuilderE2ETests: XCTestCase {
    func test_biteMapBuilder_attributesBitesToDifferentPeople_whenMouthEvidenceExists() throws {
        func sample(at t: Double, p0Mouth: Double, p1Mouth: Double) -> MasterSensors.VideoSample {
            MasterSensors.VideoSample(
                time: t,
                meanLuma: 0,
                skinLikelihood: 0,
                dominantColors: [],
                faces: [
                    .init(trackId: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, rect: CGRect(x: 0.55, y: 0.2, width: 0.20, height: 0.20), personId: "P0", mouthOpenRatio: p0Mouth),
                    .init(trackId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, rect: CGRect(x: 0.25, y: 0.2, width: 0.18, height: 0.18), personId: "P1", mouthOpenRatio: p1Mouth)
                ],
                personMaskPresence: nil,
                peopleCountEstimate: 2
            )
        }

        // Two disjoint speech segments: first dominated by P0 mouth activity, second by P1.
        let sensors = MasterSensors(
            source: .init(path: "synthetic", durationSeconds: 10, width: nil, height: nil, nominalFPS: nil),
            sampling: .init(videoStrideSeconds: 0.5, maxVideoSeconds: 10, audioAnalyzeSeconds: 10),
            videoSamples: [
                sample(at: 0.5, p0Mouth: 0.0, p1Mouth: 0.0),
                sample(at: 1.0, p0Mouth: 0.7, p1Mouth: 0.1),
                sample(at: 1.5, p0Mouth: 0.8, p1Mouth: 0.1),
                sample(at: 2.0, p0Mouth: 0.6, p1Mouth: 0.1),
                sample(at: 3.5, p0Mouth: 0.0, p1Mouth: 0.0),
                sample(at: 4.0, p0Mouth: 0.1, p1Mouth: 0.7),
                sample(at: 4.5, p0Mouth: 0.1, p1Mouth: 0.8),
                sample(at: 5.0, p0Mouth: 0.1, p1Mouth: 0.6)
            ],
            audioSegments: [
                .init(start: 1.0, end: 2.0, kind: .speechLike, confidence: 0.95),
                .init(start: 4.0, end: 5.0, kind: .speechLike, confidence: 0.95)
            ],
            audioFrames: nil,
            audioBeats: nil,
            warnings: [],
            descriptors: nil,
            suggestedStart: nil,
            summary: .init(
                analyzedSeconds: 10,
                scene: .init(
                    indoorOutdoor: .init(label: .unknown, confidence: 0),
                    lightSource: .init(label: .unknown, confidence: 0)
                ),
                audio: .init(approxRMSdBFS: -20, approxPeakDB: -1, dominantFrequencyHz: nil, spectralCentroidHz: nil)
            )
        )

        let bites = BiteMapBuilder.build(from: sensors)
        XCTAssertEqual(bites.bites.count, 2)

        XCTAssertEqual(bites.bites[0].personId, "P0")
        XCTAssertEqual(bites.bites[1].personId, "P1")
    }

    func test_biteMapBuilder_keithTalk_producesDeterministicNonEmptyBites() async throws {
        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        let sensors = try await MasterSensorIngestor().ingest(url: url)

        let bites = BiteMapBuilder.build(from: sensors)

        XCTAssertEqual(bites.schemaVersion, BiteMap.schemaVersion)
        XCTAssertFalse(bites.bites.isEmpty, "Expected some speech bites for keith_talk.mov")

        // Determinism: build twice from same sensors should match exactly.
        let bites2 = BiteMapBuilder.build(from: sensors)
        XCTAssertEqual(bites, bites2)

        // Basic invariants.
        for b in bites.bites {
            XCTAssertLessThan(b.start, b.end)
            XCTAssertFalse(b.personId.isEmpty)
            XCTAssertFalse(b.reason.isEmpty)
        }

        // Single-person fixture expectation.
        let personIds = Set(bites.bites.map { $0.personId })
        XCTAssertEqual(personIds, ["P0"])
    }
}
