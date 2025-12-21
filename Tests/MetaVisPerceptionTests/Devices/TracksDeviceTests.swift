import XCTest
import CoreVideo
import AVFoundation
import MetaVisCore
@testable import MetaVisPerception

final class TracksDeviceTests: XCTestCase {

    func test_tracks_device_produces_stable_track_ids_over_short_clip() async throws {
        let url = URL(fileURLWithPath: "Tests/Assets/people_talking/Two_men_talking_202512192152_8bc18.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        // ~2 seconds worth of frames; keep it quick.
        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 40, maxSeconds: 2.0)

        let device = TracksDevice()
        try await device.warmUp()

        var perFrame: [[UUID: CGRect]] = []
        perFrame.reserveCapacity(frames.count)

        for pb in frames {
            let tracks = try await device.track(in: pb)
            // Basic sanity for rect bounds.
            for (_, r) in tracks {
                XCTAssertGreaterThanOrEqual(r.minX, 0.0)
                XCTAssertGreaterThanOrEqual(r.minY, 0.0)
                XCTAssertLessThanOrEqual(r.maxX, 1.0)
                XCTAssertLessThanOrEqual(r.maxY, 1.0)
                XCTAssertGreaterThan(r.width, 0.0)
                XCTAssertGreaterThan(r.height, 0.0)
            }
            perFrame.append(tracks)
        }

        // We should see face tracks in a meaningful fraction of frames.
        let nonEmpty = perFrame.filter { !$0.isEmpty }.count
        XCTAssertGreaterThanOrEqual(nonEmpty, 6, "Expected tracks in at least a few frames; got \(nonEmpty)/\(perFrame.count)")

        // Should not explode into many tracks.
        let maxTracks = perFrame.map { $0.count }.max() ?? 0
        XCTAssertLessThanOrEqual(maxTracks, 4, "Too many tracks detected in a single frame: \(maxTracks)")

        // Stability heuristic: when consecutive frames both have tracks, at least one track ID should persist.
        var comparablePairs = 0
        var pairsWithIntersection = 0

        for i in 1..<perFrame.count {
            let a = perFrame[i - 1]
            let b = perFrame[i]
            if a.isEmpty || b.isEmpty { continue }

            comparablePairs += 1
            let sa = Set(a.keys)
            let sb = Set(b.keys)
            if !sa.intersection(sb).isEmpty {
                pairsWithIntersection += 1
            }
        }

        if comparablePairs >= 3 {
            let rate = Double(pairsWithIntersection) / Double(comparablePairs)
            XCTAssertGreaterThanOrEqual(rate, 0.60, "Track IDs look unstable across frames (intersection rate=\(rate))")
        }
    }

    func test_tracks_device_emits_evidence_confidence() async throws {
        let url = URL(fileURLWithPath: "Tests/Assets/people_talking/Two_men_talking_202512192152_8bc18.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 30, maxSeconds: 1.5)

        let device = TracksDevice()
        try await device.warmUp()

        var firstNonEmpty: TracksDevice.TrackResult? = nil
        for pb in frames {
            let res = try await device.trackResult(in: pb)
            if !res.tracks.isEmpty {
                firstNonEmpty = res
                break
            }
        }

        guard let res = firstNonEmpty else {
            XCTFail("Expected at least one frame with tracks")
            return
        }

        XCTAssertGreaterThanOrEqual(res.evidenceConfidence.score, 0.0)
        XCTAssertLessThanOrEqual(res.evidenceConfidence.score, 1.0)
        XCTAssertEqual(res.evidenceConfidence.reasons, res.evidenceConfidence.reasons.sorted())
        XCTAssertFalse(res.evidenceConfidence.sources.isEmpty)
        XCTAssertGreaterThan(res.metrics.trackCount, 0)
    }

    func test_tracks_device_single_person_is_mostly_one_track() async throws {
        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 30, maxSeconds: 2.0)

        let device = TracksDevice()
        try await device.warmUp()

        var counts: [Int] = []
        counts.reserveCapacity(frames.count)

        for pb in frames {
            let tracks = try await device.track(in: pb)
            counts.append(tracks.count)
        }

        // In this fixture we usually see exactly one face; allow 0/2 occasionally.
        let ones = counts.filter { $0 == 1 }.count
        XCTAssertGreaterThanOrEqual(Double(ones) / Double(max(1, counts.count)), 0.40, "Expected many frames with exactly one track; got \(counts)")
        XCTAssertLessThanOrEqual(counts.max() ?? 0, 3, "Unexpectedly high track count for single-person clip: \(counts)")
    }

    func test_tracks_device_cut_window_surfaces_reacquire_or_missing() async throws {
        let url = URL(fileURLWithPath: "Tests/Assets/people_talking/two_scene_four_speakers.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        // Read a mid-clip window likely to span the scene cut.
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let dur = duration.seconds.isFinite ? duration.seconds : 0.0
        let start = max(0.0, min(dur, dur * 0.45))
        let window = max(0.5, min(8.0, dur - start))
        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 160, startSeconds: start, maxSeconds: window)

        let device = TracksDevice()
        try await device.warmUp()

        var sawNonEmpty = false
        var reacquireCount = 0
        var missingCount = 0

        for pb in frames {
            let res = try await device.trackResult(in: pb)
            if !res.tracks.isEmpty { sawNonEmpty = true }
            if res.metrics.reacquired {
                reacquireCount += 1
                XCTAssertTrue(res.evidenceConfidence.reasons.contains(.track_reacquired))
                XCTAssertLessThanOrEqual(res.evidenceConfidence.score, 0.75)
            }
            if res.tracks.isEmpty {
                missingCount += 1
                XCTAssertTrue(res.evidenceConfidence.reasons.contains(.track_missing))
            }
        }

        XCTAssertTrue(sawNonEmpty, "Expected at least some frames with tracks")
        XCTAssertTrue(reacquireCount >= 1 || missingCount >= 1, "Expected cut window to surface reacquire and/or missing tracks")
    }
}
