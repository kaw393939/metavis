import XCTest
import MetaVisCore
import MetaVisTimeline
@testable import MetaVisSession

final class LinkedSelectionEditingTests: XCTestCase {

    func testRippleDeleteDeletesTimeAlignedAudioClipAndRipplesAcrossTracks() async throws {
        var v1a = Clip(
            name: "V1-A",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )

        let v1b = Clip(
            name: "V1-B",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0)
        )

        let a1a = Clip(
            name: "A1-A",
            asset: AssetReference(sourceFn: "ligm://audio/sine?freq=1000"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )

        let a1b = Clip(
            name: "A1-B",
            asset: AssetReference(sourceFn: "ligm://audio/sine?freq=2000"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0)
        )

        let video = Track(name: "V1", kind: .video, clips: [v1a, v1b])
        let audio = Track(name: "A1", kind: .audio, clips: [a1a, a1b])
        var timeline = Timeline(tracks: [video, audio], duration: Time(seconds: 4.0))

        let executor = CommandExecutor(trace: NoOpTraceSink())
        await executor.execute([.rippleDelete(target: .clipId(v1a.id))], in: &timeline)

        let vTrack = try XCTUnwrap(timeline.tracks.first(where: { $0.kind == .video }))
        let aTrack = try XCTUnwrap(timeline.tracks.first(where: { $0.kind == .audio }))

        XCTAssertEqual(vTrack.clips.count, 1)
        XCTAssertEqual(aTrack.clips.count, 1)

        let remainingV = try XCTUnwrap(vTrack.clips.first)
        let remainingA = try XCTUnwrap(aTrack.clips.first)

        XCTAssertEqual(remainingV.name, "V1-B")
        XCTAssertEqual(remainingA.name, "A1-B")

        // Both tracks should have rippled left by 2s.
        XCTAssertEqual(remainingV.startTime.seconds, 0.0, accuracy: 0.0001)
        XCTAssertEqual(remainingA.startTime.seconds, 0.0, accuracy: 0.0001)

        XCTAssertEqual(timeline.duration.seconds, 2.0, accuracy: 0.0001)
    }

    func testRippleTrimOutKeepsTimeAlignedAudioClipInSync() async throws {
        let v1a = Clip(
            name: "V1-A",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )

        let v1b = Clip(
            name: "V1-B",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0)
        )

        let a1a = Clip(
            name: "A1-A",
            asset: AssetReference(sourceFn: "ligm://audio/sine?freq=1000"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )

        let a1b = Clip(
            name: "A1-B",
            asset: AssetReference(sourceFn: "ligm://audio/sine?freq=2000"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0)
        )

        let video = Track(name: "V1", kind: .video, clips: [v1a, v1b])
        let audio = Track(name: "A1", kind: .audio, clips: [a1a, a1b])
        var timeline = Timeline(tracks: [video, audio], duration: Time(seconds: 4.0))

        let executor = CommandExecutor(trace: NoOpTraceSink())
        await executor.execute([.rippleTrimOut(target: .clipId(v1a.id), newEndSeconds: 3.0)], in: &timeline)

        let vTrack = try XCTUnwrap(timeline.tracks.first(where: { $0.kind == .video }))
        let aTrack = try XCTUnwrap(timeline.tracks.first(where: { $0.kind == .audio }))

        let updatedV1A = try XCTUnwrap(vTrack.clips.first(where: { $0.name == "V1-A" }))
        let updatedA1A = try XCTUnwrap(aTrack.clips.first(where: { $0.name == "A1-A" }))
        XCTAssertEqual(updatedV1A.duration.seconds, 3.0, accuracy: 0.0001)
        XCTAssertEqual(updatedA1A.duration.seconds, 3.0, accuracy: 0.0001)

        let updatedV1B = try XCTUnwrap(vTrack.clips.first(where: { $0.name == "V1-B" }))
        let updatedA1B = try XCTUnwrap(aTrack.clips.first(where: { $0.name == "A1-B" }))

        // Downstream clips should have shifted by +1s across all tracks.
        XCTAssertEqual(updatedV1B.startTime.seconds, 3.0, accuracy: 0.0001)
        XCTAssertEqual(updatedA1B.startTime.seconds, 3.0, accuracy: 0.0001)
    }
}
