import XCTest
import MetaVisCore
import MetaVisTimeline
@testable import MetaVisSession

final class TransitionAwareEditingTests: XCTestCase {

    func testRippleTrimOutShiftsOverlappedNextClipWhenCrossfadeOverlapExists() async throws {
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
            startTime: Time(seconds: 2.0), // overlaps A by 1s
            duration: Time(seconds: 2.0)
        )
        b.transitionIn = fade

        let track = Track(name: "V", kind: .video, clips: [a, b])
        var timeline = Timeline(tracks: [track], duration: Time(seconds: 4.0))

        let executor = CommandExecutor(trace: NoOpTraceSink())
        // Extend A by +1s (new end = 4.0). Ripple should shift B by +1s too.
        await executor.execute([.rippleTrimOut(target: .clipId(a.id), newEndSeconds: 4.0)], in: &timeline)

        let updatedA = try XCTUnwrap(timeline.tracks[0].clips.first(where: { $0.id == a.id }))
        let updatedB = try XCTUnwrap(timeline.tracks[0].clips.first(where: { $0.id == b.id }))
        XCTAssertEqual(updatedA.endTime.seconds, 4.0, accuracy: 0.0001)
        XCTAssertEqual(updatedB.startTime.seconds, 3.0, accuracy: 0.0001)

        // Transition durations should remain valid (<= overlap).
        let out = try XCTUnwrap(updatedA.transitionOut)
        let `in` = try XCTUnwrap(updatedB.transitionIn)
        XCTAssertEqual(out.duration.seconds, 1.0, accuracy: 0.0001)
        XCTAssertEqual(`in`.duration.seconds, 1.0, accuracy: 0.0001)
    }

    func testTrimEndClearsPairedTransitionsWhenNoOverlapRemains() async throws {
        let fade = Transition.crossfade(duration: Time(seconds: 0.5))

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
            startTime: Time(seconds: 2.6), // initial overlap: 0.4s
            duration: Time(seconds: 1.0)
        )
        b.transitionIn = fade

        let track = Track(name: "V", kind: .video, clips: [a, b])
        var timeline = Timeline(tracks: [track], duration: Time(seconds: 3.6))

        let executor = CommandExecutor(trace: NoOpTraceSink())
        // Trim A so it ends before B starts (overlap becomes <= 0).
        await executor.execute([.trimClipEnd(target: .clipId(a.id), atSeconds: 2.5)], in: &timeline)

        let updatedA = try XCTUnwrap(timeline.tracks[0].clips.first(where: { $0.id == a.id }))
        let updatedB = try XCTUnwrap(timeline.tracks[0].clips.first(where: { $0.id == b.id }))

        XCTAssertEqual(updatedA.endTime.seconds, 2.5, accuracy: 0.0001)
        XCTAssertNil(updatedA.transitionOut)
        XCTAssertNil(updatedB.transitionIn)
    }

    func testRippleDeleteClearsNeighborTransitionsAtDeletedBoundary() async throws {
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
            startTime: Time(seconds: 1.5),
            duration: Time(seconds: 2.0)
        )
        b.transitionIn = fade
        b.transitionOut = fade

        var c = Clip(
            name: "C",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate"),
            startTime: Time(seconds: 3.0),
            duration: Time(seconds: 2.0)
        )
        c.transitionIn = fade

        let track = Track(name: "V", kind: .video, clips: [a, b, c])
        var timeline = Timeline(tracks: [track], duration: Time(seconds: 5.0))

        let executor = CommandExecutor(trace: NoOpTraceSink())
        await executor.execute([.rippleDelete(target: .clipId(b.id))], in: &timeline)

        XCTAssertNil(timeline.tracks[0].clips.first(where: { $0.id == b.id }))

        let updatedA = try XCTUnwrap(timeline.tracks[0].clips.first(where: { $0.id == a.id }))
        let updatedC = try XCTUnwrap(timeline.tracks[0].clips.first(where: { $0.id == c.id }))

        // Deleting B should not leave A.fadeOut / C.fadeIn attached to a now-different boundary.
        XCTAssertNil(updatedA.transitionOut)
        XCTAssertNil(updatedC.transitionIn)
    }
}
