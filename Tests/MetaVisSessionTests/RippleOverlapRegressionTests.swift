import XCTest
import MetaVisCore
import MetaVisTimeline
@testable import MetaVisSession

final class RippleOverlapRegressionTests: XCTestCase {

    func testRippleTrimInShiftsOverlappedNextClipByOrder() async throws {
        let fade = Transition.crossfade(duration: Time(seconds: 1.0))

        var a = Clip(
            name: "A",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 3.0),
            offset: Time(seconds: 0.0)
        )
        a.transitionOut = fade

        var b = Clip(
            name: "B",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0), // overlap: 1.0s
            duration: Time(seconds: 2.0)
        )
        b.transitionIn = fade

        let track = Track(name: "V", kind: .video, clips: [a, b])
        var timeline = Timeline(tracks: [track], duration: Time(seconds: 4.0))

        let executor = CommandExecutor(trace: NoOpTraceSink())
        // Ripple trim-in increases offset (shortens clip), which moves the end earlier by 0.5.
        // Downstream clips should shift by the same delta even if they were overlapped.
        await executor.execute([.rippleTrimIn(target: .clipId(a.id), newOffsetSeconds: 0.5)], in: &timeline)

        let updatedA = try XCTUnwrap(timeline.tracks[0].clips.first(where: { $0.id == a.id }))
        let updatedB = try XCTUnwrap(timeline.tracks[0].clips.first(where: { $0.id == b.id }))

        XCTAssertEqual(updatedA.endTime.seconds, 2.5, accuracy: 0.0001)
        XCTAssertEqual(updatedB.startTime.seconds, 1.5, accuracy: 0.0001)

        let out = try XCTUnwrap(updatedA.transitionOut)
        let `in` = try XCTUnwrap(updatedB.transitionIn)
        XCTAssertEqual(out.duration.seconds, 1.0, accuracy: 0.0001)
        XCTAssertEqual(`in`.duration.seconds, 1.0, accuracy: 0.0001)
    }

    func testRippleDeleteShiftsOverlappedDownstreamClipsByOrder() async throws {
        let fade = Transition.crossfade(duration: Time(seconds: 0.5))

        var a = Clip(
            name: "A",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )
        a.transitionOut = fade

        var b = Clip(
            name: "B",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 3.0)
        )
        b.transitionIn = fade
        b.transitionOut = fade

        var c = Clip(
            name: "C",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate"),
            startTime: Time(seconds: 4.5), // overlaps B end (5.0) by 0.5s
            duration: Time(seconds: 1.0)
        )
        c.transitionIn = fade

        let track = Track(name: "V", kind: .video, clips: [a, b, c])
        var timeline = Timeline(tracks: [track], duration: Time(seconds: 5.5))

        let executor = CommandExecutor(trace: NoOpTraceSink())
        await executor.execute([.rippleDelete(target: .clipId(b.id))], in: &timeline)

        XCTAssertNil(timeline.tracks[0].clips.first(where: { $0.id == b.id }))

        let updatedA = try XCTUnwrap(timeline.tracks[0].clips.first(where: { $0.id == a.id }))
        let updatedC = try XCTUnwrap(timeline.tracks[0].clips.first(where: { $0.id == c.id }))

        // C must shift earlier by -B.duration (3s) even though it started before B's end.
        XCTAssertEqual(updatedC.startTime.seconds, 1.5, accuracy: 0.0001)

        // Deleting B should not leave A.fadeOut / C.fadeIn attached to a now-different boundary.
        XCTAssertNil(updatedA.transitionOut)
        XCTAssertNil(updatedC.transitionIn)
    }

    func testRippleTrimOutShortenShiftsOverlappedNextClipByOrder() async throws {
        let fade = Transition.crossfade(duration: Time(seconds: 1.0))

        var a = Clip(
            name: "A",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 3.0)
        )
        a.transitionOut = fade

        var b = Clip(
            name: "B",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0), // overlap: 1.0s
            duration: Time(seconds: 2.0)
        )
        b.transitionIn = fade

        let track = Track(name: "V", kind: .video, clips: [a, b])
        var timeline = Timeline(tracks: [track], duration: Time(seconds: 4.0))

        let executor = CommandExecutor(trace: NoOpTraceSink())
        // Shorten A by 0.5s (old end 3.0 -> new end 2.5). Downstream clip should shift by -0.5
        // even though it begins before the old end due to overlap.
        await executor.execute([.rippleTrimOut(target: .clipId(a.id), newEndSeconds: 2.5)], in: &timeline)

        let updatedA = try XCTUnwrap(timeline.tracks[0].clips.first(where: { $0.id == a.id }))
        let updatedB = try XCTUnwrap(timeline.tracks[0].clips.first(where: { $0.id == b.id }))

        XCTAssertEqual(updatedA.endTime.seconds, 2.5, accuracy: 0.0001)
        XCTAssertEqual(updatedB.startTime.seconds, 1.5, accuracy: 0.0001)

        let out = try XCTUnwrap(updatedA.transitionOut)
        let `in` = try XCTUnwrap(updatedB.transitionIn)
        XCTAssertEqual(out.duration.seconds, 1.0, accuracy: 0.0001)
        XCTAssertEqual(`in`.duration.seconds, 1.0, accuracy: 0.0001)
    }
}
