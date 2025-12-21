import XCTest
import MetaVisCore
import MetaVisTimeline
@testable import MetaVisSession

final class OverlapPolicyTraceTests: XCTestCase {

    func testMoveAllowsOverlapButEmitsWarningTrace() async throws {
        let clipA = Clip(
            name: "A",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )
        let clipB = Clip(
            name: "B",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 2.0),
            duration: Time(seconds: 2.0)
        )

        let track = Track(name: "V", kind: .video, clips: [clipA, clipB])
        var timeline = Timeline(tracks: [track], duration: Time(seconds: 4.0))

        let trace = InMemoryTraceSink()
        let executor = CommandExecutor(trace: trace)

        // Move clip B left into clip A's range (overlap is allowed, but should warn).
        await executor.execute([.moveClip(target: .clipId(clipB.id), toStartSeconds: 1.0)], in: &timeline)

        XCTAssertEqual(timeline.tracks[0].clips.count, 2)
        let movedB = try XCTUnwrap(timeline.tracks[0].clips.first(where: { $0.id == clipB.id }))
        XCTAssertEqual(movedB.startTime.seconds, 1.0, accuracy: 0.0001)

        let events = await trace.snapshot()
        XCTAssertTrue(events.contains(where: { $0.name == "timeline.overlap.detected" }))
    }
}
