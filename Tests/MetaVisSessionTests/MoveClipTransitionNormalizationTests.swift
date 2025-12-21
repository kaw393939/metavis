import XCTest
import MetaVisCore
import MetaVisTimeline
@testable import MetaVisSession

final class MoveClipTransitionNormalizationTests: XCTestCase {

    func testMoveClampsPairedTransitionDurationsToNewOverlap() async throws {
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
            startTime: Time(seconds: 2.0), // initial overlap: 1.0s
            duration: Time(seconds: 2.0)
        )
        b.transitionIn = fade

        let track = Track(name: "V", kind: .video, clips: [a, b])
        var timeline = Timeline(tracks: [track], duration: Time(seconds: 4.0))

        let executor = CommandExecutor(trace: NoOpTraceSink())
        // Move B later so overlap shrinks to 0.3s (A ends at 3.0; B starts at 2.7).
        await executor.execute([.moveClip(target: .clipId(b.id), toStartSeconds: 2.7)], in: &timeline)

        let updatedA = try XCTUnwrap(timeline.tracks[0].clips.first(where: { $0.id == a.id }))
        let updatedB = try XCTUnwrap(timeline.tracks[0].clips.first(where: { $0.id == b.id }))

        let out = try XCTUnwrap(updatedA.transitionOut)
        let `in` = try XCTUnwrap(updatedB.transitionIn)

        XCTAssertEqual(updatedA.endTime.seconds, 3.0, accuracy: 0.0001)
        XCTAssertEqual(updatedB.startTime.seconds, 2.7, accuracy: 0.0001)
        XCTAssertEqual(out.duration.seconds, 0.3, accuracy: 0.0001)
        XCTAssertEqual(`in`.duration.seconds, 0.3, accuracy: 0.0001)
    }

    func testMoveClearsPairedTransitionsWhenNoOverlapRemains() async throws {
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
            startTime: Time(seconds: 2.0), // overlap initially
            duration: Time(seconds: 2.0)
        )
        b.transitionIn = fade

        let track = Track(name: "V", kind: .video, clips: [a, b])
        var timeline = Timeline(tracks: [track], duration: Time(seconds: 4.0))

        let executor = CommandExecutor(trace: NoOpTraceSink())
        // Move B to start exactly at A end -> overlap becomes 0, paired transitions should clear.
        await executor.execute([.moveClip(target: .clipId(b.id), toStartSeconds: 3.0)], in: &timeline)

        let updatedA = try XCTUnwrap(timeline.tracks[0].clips.first(where: { $0.id == a.id }))
        let updatedB = try XCTUnwrap(timeline.tracks[0].clips.first(where: { $0.id == b.id }))

        XCTAssertEqual(updatedA.endTime.seconds, 3.0, accuracy: 0.0001)
        XCTAssertEqual(updatedB.startTime.seconds, 3.0, accuracy: 0.0001)
        XCTAssertNil(updatedA.transitionOut)
        XCTAssertNil(updatedB.transitionIn)
    }
}
