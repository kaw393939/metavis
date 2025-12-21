import XCTest
import AVFoundation
@testable import MetaVisPerception

final class MasterSensorsIngestorTests: XCTestCase {

    func testKeithTalkLooksLikeOutdoorSinglePersonNaturalLight() async throws {
        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        let ingestor = MasterSensorIngestor(
            videoStrideSeconds: 1.0,
            maxVideoSeconds: 6.0,
            audioAnalyzeSeconds: 10.0
        )

        let sensors = try await ingestor.ingest(url: url)

        XCTAssertEqual(sensors.schemaVersion, 4)
        XCTAssertGreaterThan(sensors.videoSamples.count, 2)

        // Scene context expectations based on your description: one person outdoors in daylight.
        let scene = sensors.summary.scene
        XCTAssertEqual(scene.indoorOutdoor.label, .outdoor)
        XCTAssertGreaterThanOrEqual(scene.indoorOutdoor.confidence, 0.55)

        XCTAssertEqual(scene.lightSource.label, .natural)
        XCTAssertGreaterThanOrEqual(scene.lightSource.confidence, 0.55)

        // Faces: should usually find exactly one.
        let faceCounts = sensors.videoSamples.map { $0.faces.count }
        let ones = faceCounts.filter { $0 == 1 }.count
        XCTAssertGreaterThanOrEqual(Double(ones) / Double(faceCounts.count), 0.60, "Expected >=60% samples with exactly one face; got \(faceCounts)")
        XCTAssertLessThanOrEqual(faceCounts.max() ?? 0, 2, "Should not look like a multi-person scene: \(faceCounts)")

        // Identity MVP: when a face is present, personId should be set and stable.
        let oneFaceSamples = sensors.videoSamples.filter { $0.faces.count == 1 }
        if let first = oneFaceSamples.first {
            let pid = first.faces[0].personId
            XCTAssertNotNil(pid)
            XCTAssertEqual(pid, "P0", "Expected the single-person fixture to resolve to P0")

            for s in oneFaceSamples {
                XCTAssertEqual(s.faces[0].personId, pid)
            }
        }

        // Audio should not be pure silence.
        XCTAssertGreaterThan(sensors.summary.audio.approxPeakDB, -60)
        XCTAssertGreaterThan(sensors.summary.audio.approxRMSdBFS, -80)

        // FFT-derived audio features should be present when audio analysis is enabled.
        if let domHz = sensors.summary.audio.dominantFrequencyHz {
            XCTAssertTrue(domHz.isFinite)
            XCTAssertGreaterThan(domHz, 0.0)
            XCTAssertLessThan(domHz, 24_000.0)
        } else {
            XCTFail("Expected dominantFrequencyHz to be present")
        }
        if let centroidHz = sensors.summary.audio.spectralCentroidHz {
            XCTAssertTrue(centroidHz.isFinite)
            XCTAssertGreaterThanOrEqual(centroidHz, 0.0)
            XCTAssertLessThan(centroidHz, 24_000.0)
        } else {
            XCTFail("Expected spectralCentroidHz to be present")
        }

        // Segmentation: should see a person mask sometimes.
        let maskRates = sensors.videoSamples.compactMap { $0.personMaskPresence }
        XCTAssertFalse(maskRates.isEmpty, "Expected personMaskPresence samples")
        XCTAssertGreaterThan(maskRates.max() ?? 0.0, 0.01, "Expected some non-trivial person segmentation")

        // VAD / speech-like: should find at least one speech-like segment.
        let speechSeconds = sensors.audioSegments
            .filter { $0.kind == .speechLike }
            .map { max(0.0, $0.end - $0.start) }
            .reduce(0.0, +)
        XCTAssertGreaterThan(speechSeconds, 1.0, "Expected >1s speech-like audio")

        // Auto-start: should suggest trimming past initial pre-roll (e.g., throat clear / settling) for this fixture.
        XCTAssertNotNil(sensors.suggestedStart)
        if let s = sensors.suggestedStart {
            XCTAssertGreaterThanOrEqual(s.time, 0.0)
            XCTAssertLessThanOrEqual(s.time, sensors.summary.analyzedSeconds)
            XCTAssertGreaterThan(s.time, 0.1, "Expected non-zero suggested start")
            XCTAssertGreaterThanOrEqual(s.confidence, 0.5)
        }

        // Descriptors (LLM-friendly): should be present and well-formed.
        XCTAssertNotNil(sensors.descriptors, "Expected descriptors to be computed")
        let descriptors = sensors.descriptors ?? []
        XCTAssertFalse(descriptors.isEmpty, "Expected at least one descriptor")

        // Deterministic ordering + bounds.
        var lastStart: Double = -1.0
        var lastEnd: Double = -1.0
        var lastLabel: String = ""
        for d in descriptors {
            XCTAssertGreaterThanOrEqual(d.start, 0.0)
            XCTAssertLessThanOrEqual(d.end, sensors.summary.analyzedSeconds + 0.001)
            XCTAssertGreaterThan(d.end, d.start)
            XCTAssertGreaterThanOrEqual(d.confidence, 0.0)
            XCTAssertLessThanOrEqual(d.confidence, 1.0)

            // Sorted by start, then end, then label.
            if d.start < lastStart - 0.000001 {
                XCTFail("Descriptors not sorted by start")
            } else if abs(d.start - lastStart) <= 0.000001 {
                if d.end < lastEnd - 0.000001 {
                    XCTFail("Descriptors not sorted by end")
                } else if abs(d.end - lastEnd) <= 0.000001 {
                    if d.label.rawValue < lastLabel {
                        XCTFail("Descriptors not sorted by label")
                    }
                }
            }

            lastStart = d.start
            lastEnd = d.end
            lastLabel = d.label.rawValue
        }

        // Expected high-level tags based on earlier asserted evidence.
        XCTAssertTrue(descriptors.contains(where: { $0.label == .suggestedStart }), "Expected suggested_start descriptor")
        XCTAssertTrue(descriptors.contains(where: { $0.label == .singleSubject }), "Expected single_subject descriptor")
        XCTAssertTrue(descriptors.contains(where: { $0.label == .continuousSpeech }), "Expected continuous_speech descriptor")

        // Warnings: should not be dominated by red.
        let analyzedDuration = sensors.summary.analyzedSeconds
        let redSeconds = sensors.warnings
            .filter { $0.severity == .red }
            .map { max(0.0, $0.end - $0.start) }
            .reduce(0.0, +)
        if analyzedDuration > 0.001 {
            XCTAssertLessThanOrEqual(redSeconds / analyzedDuration, 0.20, "Too many red warnings for a clean talking-head outdoor clip")
        }
    }
}
