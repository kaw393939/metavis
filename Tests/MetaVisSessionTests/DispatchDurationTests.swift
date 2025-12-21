import XCTest
import MetaVisCore
import MetaVisTimeline
@testable import MetaVisSession

final class DispatchDurationTests: XCTestCase {

    func testDispatchAddAndRemoveClipRecomputesTimelineDuration() async {
        let track = Track(name: "V", kind: .video, clips: [])
        let session = ProjectSession(initialState: ProjectState(timeline: Timeline(tracks: [track], duration: .zero)), trace: NoOpTraceSink())

        let clipA = Clip(
            name: "A",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0.0),
            duration: Time(seconds: 2.0)
        )
        let clipB = Clip(
            name: "B",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 10.0),
            duration: Time(seconds: 1.0)
        )

        await session.dispatch(.addClip(clipA, toTrackId: track.id))
        await session.dispatch(.addClip(clipB, toTrackId: track.id))

        let afterAdds = await session.state.timeline
        XCTAssertEqual(afterAdds.duration.seconds, 11.0, accuracy: 0.0001)

        await session.dispatch(.removeClip(id: clipB.id, fromTrackId: track.id))
        let afterRemove = await session.state.timeline
        XCTAssertEqual(afterRemove.duration.seconds, 2.0, accuracy: 0.0001)
    }
}
